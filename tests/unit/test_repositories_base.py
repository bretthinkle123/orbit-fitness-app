"""Unit tests for the database engine/session facade (`repositories/base.py`):
DSN resolution (local override vs. the secrets facade) and engine caching."""

import pytest

from orbit.repositories import base as repositories_base


class _FakeSettings:
    """Stands in for `Settings` so these tests don't depend on real env vars."""

    def __init__(self, database_url=None, database_url_secret_name="orbit/database-url"):
        self.database_url = database_url
        self.database_url_secret_name = database_url_secret_name


@pytest.fixture(autouse=True)
def _reset_cached_engine():
    """Every test starts and ends with no cached engine, so `get_engine()`
    caching behavior in one test can't leak into another."""
    repositories_base._engine = None
    yield
    repositories_base._engine = None


def test_resolve_database_url_prefers_the_local_override(monkeypatch):
    """A configured `database_url` (dev/test) is used as-is, never routed
    through the secrets facade."""
    monkeypatch.setattr(
        repositories_base,
        "get_settings",
        lambda: _FakeSettings(database_url="postgresql+asyncpg://local/test"),
    )

    def _fail_if_called(name):
        raise AssertionError("get_secret must not be called when a local override is set")

    monkeypatch.setattr(repositories_base, "get_secret", _fail_if_called)

    assert repositories_base.resolve_database_url() == "postgresql+asyncpg://local/test"


def test_resolve_database_url_falls_back_to_the_secrets_facade(monkeypatch):
    """With no local override, the DSN is fetched from Secrets Manager by
    name, through the one secrets facade — never a second SDK caller."""
    monkeypatch.setattr(
        repositories_base,
        "get_settings",
        lambda: _FakeSettings(database_url=None, database_url_secret_name="orbit/database-url"),
    )
    calls = []

    def _fake_get_secret(name):
        calls.append(name)
        return "postgresql+asyncpg://prod/from-secret"

    monkeypatch.setattr(repositories_base, "get_secret", _fake_get_secret)

    assert repositories_base.resolve_database_url() == "postgresql+asyncpg://prod/from-secret"
    assert calls == ["orbit/database-url"]


def test_get_engine_returns_the_same_cached_instance_on_repeated_calls(monkeypatch):
    """One engine per process — `get_engine()` doesn't rebuild on every call."""
    monkeypatch.setattr(
        repositories_base,
        "get_settings",
        lambda: _FakeSettings(database_url="postgresql+asyncpg://unused/for-this-test"),
    )

    first = repositories_base.get_engine()
    second = repositories_base.get_engine()

    assert first is second


@pytest.mark.asyncio
async def test_dispose_engine_clears_the_cache_so_the_next_call_builds_fresh(monkeypatch):
    """After `dispose_engine()`, `get_engine()` must construct and cache a
    new engine rather than returning the disposed one."""
    monkeypatch.setattr(
        repositories_base,
        "get_settings",
        lambda: _FakeSettings(database_url="postgresql+asyncpg://unused/for-this-test"),
    )

    first = repositories_base.get_engine()
    await repositories_base.dispose_engine()
    second = repositories_base.get_engine()

    assert first is not second
