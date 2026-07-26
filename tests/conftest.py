"""Shared pytest fixtures (rule-of-two: promoted here once a fixture is used
by two or more test modules).

T3 adds the Firebase Auth emulator fixtures (Operator addendum #1): mint REAL
tokens against a live emulator so integration tests exercise true
verification semantics — expired/wrong-audience rejection, revocation via
`check_revoked` — with no mocked guard. The testcontainers-Postgres fixture
lives in `tests/integration/test_migrations.py` (single consumer so far, per
rule-of-two); a dedicated Redis fixture lives in the throttle test module for
the same reason.

IMPORTANT ordering note: `FIREBASE_PROJECT_ID` is set at COLLECTION time
(module import, below) — before any test can trigger `get_settings()` for
the first time. `Settings` reads env vars once and `get_settings()` caches
the result for the whole process, so setting this after another test has
already called `get_settings()` would be too late and every emulator-backed
test would fail on a project-id (audience) mismatch.
"""

import os

# Must run before ANY import that might transitively call get_settings() —
# see the module docstring.
os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-orbit-test")

import asyncio  # noqa: E402
import subprocess  # noqa: E402 — see ordering note above
import time  # noqa: E402
import uuid  # noqa: E402
from pathlib import Path  # noqa: E402

import pytest  # noqa: E402
import redis.asyncio as redis_asyncio  # noqa: E402
import requests  # noqa: E402
import sqlalchemy as sa  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import create_async_engine  # noqa: E402
from testcontainers.postgres import PostgresContainer  # noqa: E402
from testcontainers.redis import RedisContainer  # noqa: E402

from orbit.auth.firebase import reset_app_for_tests  # noqa: E402
from orbit.config.settings import get_settings  # noqa: E402
from orbit.edge import ratelimit as ratelimit_module  # noqa: E402
from orbit.main import create_app  # noqa: E402
from orbit.repositories.base import dispose_engine  # noqa: E402

_REPO_ROOT = Path(__file__).resolve().parent.parent
_FIREBASE_PROJECT_ID = "demo-orbit-test"
_FIREBASE_EMULATOR_HOST = "localhost:9099"
# The emulator ignores this value entirely (it never reaches a real Google
# endpoint) — required by the REST API's URL shape, never a live credential.
_EMULATOR_API_KEY = "fake-api-key"
# A throwaway password for ephemeral test users created against the LOCAL
# emulator only (never a real account, never sent to a real Google endpoint,
# discarded when the emulator process exits) — not a credential to protect.
_TEST_USER_PASSWORD = "Password123!"


@pytest.fixture
def client():
    """A TestClient bound to a fresh app instance for each test.

    Used as a context manager (not a bare `TestClient(...)` return) so its
    background event loop/portal is opened once and held for the whole
    test — letting it die and get silently recreated between calls broke an
    async resource (a pooled Redis connection) that was reused across two
    calls under two different, short-lived loops (reproduced empirically:
    "RuntimeError: Event loop is closed" on the first Redis call of every
    request after the first). This also correctly fires ASGI lifespan
    events, which a bare instantiation skips.
    """
    with TestClient(create_app()) as test_client:
        yield test_client


def _emulator_is_ready(host: str) -> bool:
    """Poll the emulator's own config endpoint — cheap, no side effects."""
    try:
        response = requests.get(
            f"http://{host}/emulator/v1/projects/{_FIREBASE_PROJECT_ID}/config", timeout=1
        )
        return response.status_code == 200
    except requests.RequestException:
        return False


@pytest.fixture(scope="session")
def firebase_emulator():
    """Start the Firebase Auth emulator for the whole test session (Operator
    addendum #1). Sets `FIREBASE_AUTH_EMULATOR_HOST` so `auth/firebase.py`'s
    credential resolution skips the real Secrets-Manager path and talks to
    the emulator instead. Yields the `host:port` string."""
    os.environ["FIREBASE_AUTH_EMULATOR_HOST"] = _FIREBASE_EMULATOR_HOST
    process = subprocess.Popen(
        ["firebase", "emulators:start", "--only", "auth", "--project", _FIREBASE_PROJECT_ID],
        cwd=_REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    deadline = time.monotonic() + 45
    ready = False
    while time.monotonic() < deadline:
        if _emulator_is_ready(_FIREBASE_EMULATOR_HOST):
            ready = True
            break
        if process.poll() is not None:
            break  # the process exited early — stop polling, report below
        time.sleep(0.5)

    if not ready:
        output = process.stdout.read() if process.stdout else ""
        process.terminate()
        raise RuntimeError(f"Firebase Auth emulator did not become ready in time.\n{output}")

    yield _FIREBASE_EMULATOR_HOST

    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
    del os.environ["FIREBASE_AUTH_EMULATOR_HOST"]


@pytest.fixture
def firebase_test_user(firebase_emulator):
    """Mint a real Firebase user + ID token against the running emulator
    (Identity Toolkit REST API — the same mechanism a real client uses to
    sign up). Resets the cached Admin app before and after so no test's
    Firebase state leaks into the next. Returns a dict with `uid`,
    `id_token`, and `email` (the last so a test can sign back in for a
    fresh token — the session-lifecycle / rotation-on-auth test)."""
    reset_app_for_tests()

    email = f"{uuid.uuid4().hex}@example.com"
    response = requests.post(
        f"http://{firebase_emulator}/identitytoolkit.googleapis.com/v1/accounts:signUp",
        params={"key": _EMULATOR_API_KEY},
        json={"email": email, "password": _TEST_USER_PASSWORD, "returnSecureToken": True},
        timeout=5,
    )
    response.raise_for_status()
    data = response.json()

    yield {"uid": data["localId"], "id_token": data["idToken"], "email": email}

    reset_app_for_tests()


@pytest.fixture
def firebase_sign_in(firebase_emulator):
    """Factory fixture: sign in an existing test user again, minting a FRESH
    ID token — Firebase mints a new token per sign-in (rotation on auth,
    ASVS 7.2.4); used by the session-lifecycle test to prove a fresh
    sign-in works after the prior token was revoked."""

    def _sign_in(email: str, password: str = _TEST_USER_PASSWORD) -> str:
        response = requests.post(
            f"http://{firebase_emulator}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword",
            params={"key": _EMULATOR_API_KEY},
            json={"email": email, "password": password, "returnSecureToken": True},
            timeout=5,
        )
        response.raise_for_status()
        return response.json()["idToken"]

    return _sign_in


# ---------------------------------------------------------------------------
# Postgres-backed app-database wiring (rule-of-two: promoted here once T5's
# `test_fuel.py` became the SECOND module needing a live, migrated Postgres
# behind the app's own DB engine — `test_profile.py` was the first consumer
# and originally carried these fixtures locally).
# ---------------------------------------------------------------------------


def _to_asyncpg_url(container_url: str) -> str:
    """Rewrite testcontainers' default `+psycopg2` URL to the `+asyncpg`
    dialect both the app and Alembic expect (mirrors `test_migrations.py`)."""
    if "+psycopg2" in container_url:
        return container_url.replace("+psycopg2", "+asyncpg")
    if container_url.startswith("postgresql://"):
        return container_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    return container_url


def _run_alembic(*args: str, database_url: str) -> None:
    """Run a real `alembic` CLI command against the given DSN — fails the
    test loudly (assert) rather than continuing on a broken migration."""
    env = os.environ.copy()
    env["DATABASE_URL"] = database_url
    result = subprocess.run(
        ["alembic", *args], cwd=_REPO_ROOT, env=env, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"alembic {' '.join(args)} failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


async def run_scalar_query(database_url: str, query: str, **params) -> object:
    """Run one scalar query against a fresh, throwaway Core connection — NOT
    an `AsyncSession`, so this stays correct even while a test has the ORM
    session's `execute` monkeypatched (e.g. a fault-injection test)."""
    engine = create_async_engine(database_url)
    try:
        async with engine.connect() as connection:
            result = await connection.execute(sa.text(query), params)
            return result.scalar_one()
    finally:
        await engine.dispose()


async def run_row_query(database_url: str, query: str, **params) -> list:
    """Run one multi-row query against a fresh, throwaway Core connection."""
    engine = create_async_engine(database_url)
    try:
        async with engine.connect() as connection:
            result = await connection.execute(sa.text(query), params)
            return result.all()
    finally:
        await engine.dispose()


def run_async(coroutine):
    """Run a bare coroutine to completion — the DB helpers above are async
    (real asyncpg round trips) but pytest's sync test functions need a
    blocking call; `asyncio_mode = "auto"` only auto-runs test/fixture
    coroutines, not ad-hoc ones built inline in a sync test body."""
    return asyncio.run(coroutine)


@pytest.fixture(scope="module")
def postgres_url():
    """One migrated testcontainers Postgres for the whole consuming module —
    module-scoped, so each test FILE that opts in gets its own isolated
    container rather than sharing state with another file."""
    with PostgresContainer("postgres:16-alpine") as container:
        url = _to_asyncpg_url(container.get_connection_url())
        _run_alembic("upgrade", "head", database_url=url)
        yield url


@pytest.fixture(scope="module")
def _wire_app_database(postgres_url):
    """Point the app's OWN DB engine (`repositories/base.get_engine`) at the
    migrated container for every test in the consuming module.

    Not autouse at this (conftest) level — spinning up a Postgres container
    for every test file in the suite (including ones that never touch the
    DB, like `test_auth.py`) would be wasteful. Each consuming module opts in
    with its own small `autouse=True` fixture that depends on this one (see
    `test_profile.py`/`test_fuel.py`).

    `get_settings()` is process-wide `@lru_cache`d (T1) and earlier test
    modules in the same pytest session never touch the DB layer, so its
    cached `database_url` is still `None` here — `cache_clear()` forces a
    fresh read of the `DATABASE_URL` env var this fixture sets, exactly like
    this file's own `FIREBASE_PROJECT_ID` ordering note, just scoped to the
    consuming module's lifetime instead of collection time.
    """
    os.environ["DATABASE_URL"] = postgres_url
    get_settings.cache_clear()
    yield
    asyncio.run(dispose_engine())
    del os.environ["DATABASE_URL"]
    get_settings.cache_clear()


# ---------------------------------------------------------------------------
# Real, reachable Redis (rule-of-two: promoted here once `test_account_
# deletion.py`'s Tier-2-throttle test became the SECOND consumer —
# `test_ratelimit.py` was the first and originally carried these fixtures
# locally). A REAL Redis is needed only when a test wants actual limiting to
# take effect; the fail-open tests elsewhere deliberately use an unreachable
# store instead.
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def real_redis_client():
    """A real, reachable Redis instance for the whole consuming module."""
    with RedisContainer("redis:7-alpine") as container:
        client = redis_asyncio.Redis(
            host=container.get_container_host_ip(),
            port=int(container.get_exposed_port(6379)),
            decode_responses=True,
        )
        yield client


@pytest.fixture
def _wire_real_redis_and_tight_tier2_limit(monkeypatch, real_redis_client):
    """Point the rate-limit facade at the real Redis instance and tighten
    Tier-2's limit to 1/window so a second call from the same principal trips
    a 429 within a single test. Not autouse at this (conftest) level — each
    consuming test opts in explicitly (a module-wide autouse would starve
    every OTHER Tier-2-gated write call the same test file makes for the
    same uid, since the bucket key is uid-only, not per-route)."""
    monkeypatch.setattr(ratelimit_module, "_redis_client", real_redis_client)
    monkeypatch.setattr(ratelimit_module, "_TIER2_LIMIT", 1)


@pytest.fixture(autouse=True)
def _reset_app_database_engine_after_every_test():
    """Dispose the app's process-wide DB engine after EVERY test in the whole
    suite (cheap no-op if the engine was never created this test — most
    modules never touch it).

    `client` is function-scoped (a fresh `TestClient`/ASGI-lifespan/anyio
    portal per test), but `repositories.base`'s engine is a process-wide
    singleton whose pooled asyncpg connections are bound to whichever event
    loop was running when they were opened. Left cached across tests, a
    connection opened under one test's now-torn-down portal loop gets
    checked out by the next test's brand-new loop and breaks with "Event
    loop is closed" — the same class of bug T3 already hit and fixed for the
    Redis client, reproduced here for the DB engine the first time a test
    actually touches it (T4). Disposing after every test forces a fresh
    engine (and pool) bound to the NEXT test's own loop.
    """
    yield
    asyncio.run(dispose_engine())
