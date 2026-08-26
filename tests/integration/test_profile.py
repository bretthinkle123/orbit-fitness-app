"""Integration tests for `POST /me/bootstrap` + `GET`/`PATCH /profile` (T4;
AC4, AC8, AC13, AC15) against a REAL testcontainers Postgres (migrated via
the real `alembic` CLI, matching `test_migrations.py`'s pattern) and the
REAL Firebase Auth emulator (Operator addendum #1 — no mocked guard).

`AC15` (client-provided-timestamp backdate/future semantics) is built and
unit-tested in `schemas/common.py` / `tests/unit/test_schemas_common.py`
(T3) — neither `/me/bootstrap` nor `/profile` carries a client timestamp
field, so there is no endpoint in this task to exercise it against; the
first concrete timestamp field lands with T5's `logged_at`. Not
re-duplicated here.
"""

from __future__ import annotations

import asyncio

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from orbit.repositories.profile import bootstrap_profile
from orbit.schemas.profile import compute_macro_split_percentages
from tests.conftest import run_async, run_row_query, run_scalar_query

# Local aliases so the rest of this file reads exactly as it did before these
# helpers were promoted to `conftest.py` (rule-of-two: `test_fuel.py` is now
# the second consumer).
_run = run_async
_scalar = run_scalar_query
_rows = run_row_query


@pytest.fixture(scope="module", autouse=True)
def _use_migrated_database(_wire_app_database):
    """Opt this module into the shared Postgres-wiring fixture (`conftest.py`)
    — not globally autouse, so modules that never touch the DB (e.g.
    `test_auth.py`) don't pay for a container they don't need."""
    yield


def _auth_header(id_token: str) -> dict[str, str]:
    """Build the `Authorization: Bearer <token>` header every protected
    route requires."""
    return {"Authorization": f"Bearer {id_token}"}


# ---------------------------------------------------------------------------
# Unauthenticated access (AC2) — reproduced here (not touching test_auth.py's
# shared list) since these two routes are new this task.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "method,path", [("POST", "/me/bootstrap"), ("GET", "/profile"), ("PATCH", "/profile")]
)
def test_profile_routes_deny_a_missing_token(client, method, path):
    response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


# ---------------------------------------------------------------------------
# Bootstrap idempotency + empty-start (AC4)
# ---------------------------------------------------------------------------


def test_bootstrap_is_idempotent_and_new_users_start_empty(client, firebase_test_user, postgres_url):
    """Bootstrapping twice yields exactly ONE profile row + 13 muscle-level
    rows (not 2x); every domain table (food/sets/weight) stays at zero rows
    for this uid, matching AC4's "new users start EMPTY"."""
    uid = firebase_test_user["uid"]
    headers = _auth_header(firebase_test_user["id_token"])

    template_rows = {
        row.muscle_group: row.level
        for row in _run(_rows(postgres_url, "SELECT muscle_group, level FROM muscle_level_templates"))
    }

    first_response = client.post("/me/bootstrap", headers=headers)
    assert first_response.status_code == 200
    first_body = first_response.json()
    assert first_body["kcal_budget"] == 2350
    assert first_body["protein_target_g"] == 185
    assert first_body["carb_target_g"] == 240
    assert first_body["fat_target_g"] == 72
    assert first_body["score_base"] == 512
    assert {level["muscle_group"]: level["level"] for level in first_body["muscle_levels"]} == template_rows
    assert len(first_body["muscle_levels"]) == 13

    second_response = client.post("/me/bootstrap", headers=headers)
    assert second_response.status_code == 200
    assert second_response.json() == first_body, "a replay must return the SAME profile, not create a second one"

    assert _run(_scalar(postgres_url, "SELECT count(*) FROM profiles WHERE owner_uid = :uid", uid=uid)) == 1
    assert (
        _run(_scalar(postgres_url, "SELECT count(*) FROM muscle_base_levels WHERE owner_uid = :uid", uid=uid))
        == 13
    )
    for table in ("food_entries", "set_events", "weight_entries"):
        assert _run(_scalar(postgres_url, f"SELECT count(*) FROM {table} WHERE owner_uid = :uid", uid=uid)) == 0


async def _bootstrap_concurrently_twice(database_url: str, owner_uid: str) -> list[bool]:
    """Run `bootstrap_profile` twice, genuinely concurrently (via
    `asyncio.gather`, two independent sessions/connections), for the SAME
    `owner_uid` against the SAME live Postgres — the interleaving this
    exercises happens at the real network-await points of each INSERT/SELECT,
    a true race at the database, not a sequential replay."""
    engine = create_async_engine(database_url)
    sessionmaker = async_sessionmaker(bind=engine, expire_on_commit=False)

    async def _one_bootstrap_call() -> bool:
        async with sessionmaker() as session, session.begin():
            _profile, _levels, created = await bootstrap_profile(session, owner_uid)
            return created

    try:
        return await asyncio.gather(_one_bootstrap_call(), _one_bootstrap_call())
    finally:
        await engine.dispose()


def test_bootstrap_concurrent_calls_create_exactly_one_profile(firebase_test_user, postgres_url):
    """Genuine concurrency (not just sequential replay): two `bootstrap_profile`
    calls for the SAME uid, racing on two independent connections, must still
    land exactly one profile row + 13 levels — the `INSERT ... ON CONFLICT DO
    NOTHING ... RETURNING` upsert is atomic by construction, so there is no
    check-then-insert window for two racing calls to both "win" the create."""
    uid = firebase_test_user["uid"]

    created_flags = _run(_bootstrap_concurrently_twice(postgres_url, uid))
    assert sorted(created_flags) == [False, True], "exactly one of the two racing calls must be the creator"

    assert _run(_scalar(postgres_url, "SELECT count(*) FROM profiles WHERE owner_uid = :uid", uid=uid)) == 1
    assert (
        _run(_scalar(postgres_url, "SELECT count(*) FROM muscle_base_levels WHERE owner_uid = :uid", uid=uid))
        == 13
    )


def test_bootstrap_atomic_rollback_on_fault_injected_mid_insert_failure(
    client, firebase_test_user, postgres_url, monkeypatch
):
    """T2-5 / ASVS 2.3.3: a fault injected partway through the multi-insert
    (a monkeypatched `AsyncSession.execute` that raises on its 5th call —
    landing mid-way through the 13-row muscle-level insert loop, well after
    the profile row's own insert) must roll the WHOLE transaction back — no
    partial profile, no partial muscle-level rows."""
    original_execute = AsyncSession.execute
    call_count = {"n": 0}

    async def _flaky_execute(self, *args, **kwargs):
        call_count["n"] += 1
        if call_count["n"] == 5:
            raise RuntimeError("fault-injected failure mid-insert (T2-5 / ASVS 2.3.3 test)")
        return await original_execute(self, *args, **kwargs)

    monkeypatch.setattr(AsyncSession, "execute", _flaky_execute)

    uid = firebase_test_user["uid"]
    response = client.post("/me/bootstrap", headers=_auth_header(firebase_test_user["id_token"]))

    # The generic error-envelope facade (edge/errors.py) catches the raised
    # RuntimeError and returns a safe, detail-free 500 — never a partial 200.
    assert response.status_code == 500
    assert "RuntimeError" not in response.text
    assert "fault-injected" not in response.text

    # These queries use a bare `AsyncConnection`, never `AsyncSession`, so
    # they are unaffected by the monkeypatch above and see the real DB state.
    assert _run(_scalar(postgres_url, "SELECT count(*) FROM profiles WHERE owner_uid = :uid", uid=uid)) == 0
    assert (
        _run(_scalar(postgres_url, "SELECT count(*) FROM muscle_base_levels WHERE owner_uid = :uid", uid=uid))
        == 0
    )


# ---------------------------------------------------------------------------
# GET /profile (AC4, AC13, AC16)
# ---------------------------------------------------------------------------


def test_get_profile_404s_before_bootstrap(client, firebase_test_user):
    """No default-profile fallback exists — an unbootstrapped account reads
    404, never a shared template row."""
    response = client.get("/profile", headers=_auth_header(firebase_test_user["id_token"]))
    assert response.status_code == 404


def test_get_profile_rejects_an_undeclared_query_param(client, firebase_test_user):
    """`GET /profile` is a NO-PARAMS endpoint (plan §Validation contracts) —
    an undeclared param is a 422, never silently ignored."""
    headers = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers)
    response = client.get("/profile?unexpected=1", headers=headers)
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# PATCH /profile — allowlisted round-trip, mass-assignment defense (AC13)
# ---------------------------------------------------------------------------


def test_patch_profile_round_trips_every_allowlisted_field(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers)

    patch_response = client.patch(
        "/profile",
        headers=headers,
        json={
            "palette_preset": "blue",
            "units": "metric",
            "gender": "w",
            "planet_index": 3,
            "kcal_budget": 2000,
            "protein_target_g": 150,
            "carb_target_g": 200,
            "fat_target_g": 60,
        },
    )
    assert patch_response.status_code == 200
    patched = patch_response.json()
    assert patched["palette_preset"] == "blue"
    assert patched["units"] == "metric"
    assert patched["gender"] == "w"
    assert patched["planet_index"] == 3
    assert patched["kcal_budget"] == 2000
    assert patched["protein_target_g"] == 150
    assert patched["carb_target_g"] == 200
    assert patched["fat_target_g"] == 60

    read_response = client.get("/profile", headers=headers)
    assert read_response.status_code == 200
    assert read_response.json() == patched, "a subsequent GET must reflect the PATCH"


def test_patch_profile_partial_update_leaves_other_fields_untouched(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    bootstrapped = client.post("/me/bootstrap", headers=headers).json()

    response = client.patch("/profile", headers=headers, json={"palette_preset": "green"})
    assert response.status_code == 200
    body = response.json()
    assert body["palette_preset"] == "green"
    assert body["units"] == bootstrapped["units"]
    assert body["kcal_budget"] == bootstrapped["kcal_budget"]
    assert body["protein_target_g"] == bootstrapped["protein_target_g"]


@pytest.mark.parametrize(
    "bad_body",
    [
        {"score_base": 9999},  # a real column, but not on the writable allowlist
        {"owner_uid": "someone-elses-uid"},  # the mass-assignment defense this task exists for
        {"tier_label": "Legend"},  # display-only, deliberately not writable
        {"totally_unknown_field": True},
    ],
)
def test_patch_profile_rejects_mass_assignment_of_a_non_allowlisted_field(client, firebase_test_user, bad_body):
    headers = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers)
    response = client.patch("/profile", headers=headers, json=bad_body)
    assert response.status_code == 422


def test_patch_profile_404s_before_bootstrap(client, firebase_test_user):
    response = client.patch(
        "/profile", headers=_auth_header(firebase_test_user["id_token"]), json={"palette_preset": "red"}
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Cross-owner IDOR (AC3)
# ---------------------------------------------------------------------------


def test_profile_is_never_visible_across_owners(client, firebase_test_user, firebase_second_user):
    """A patches their own profile; B (a distinct principal) must see only
    their own defaults, never A's changes — there is no request parameter on
    either route that names a target account, so the only way this could
    leak is a repository bug scoping by something other than the verified
    token's own uid."""
    headers_a = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers_a)
    client.patch("/profile", headers=headers_a, json={"palette_preset": "green", "planet_index": 5})

    headers_b = _auth_header(firebase_second_user()["id_token"])

    profile_b = client.post("/me/bootstrap", headers=headers_b).json()
    assert profile_b["palette_preset"] == "purple", "B must get their OWN default, never A's 'green'"
    assert profile_b["planet_index"] == 0

    read_b = client.get("/profile", headers=headers_b)
    assert read_b.json()["palette_preset"] == "purple"


# ---------------------------------------------------------------------------
# Canonical grams + derived-% (AC8) — pure-function unit test
# ---------------------------------------------------------------------------


def test_compute_macro_split_percentages_matches_the_plans_worked_example():
    protein_pct, carb_pct, fat_pct = compute_macro_split_percentages(
        kcal_budget=2350, protein_g=185, carb_g=240, fat_g=72
    )
    assert (protein_pct, carb_pct, fat_pct) == (31, 41, 28)
