"""Integration tests for `DELETE /me` — the full account-erasure cascade
(T8; AC5, AC21) against a REAL testcontainers Postgres (migrated via the real
`alembic` CLI) and the REAL Firebase Auth emulator (Operator addendum #1 —
no mocked guard).
"""

from __future__ import annotations

import base64
import datetime
import json
import time
import uuid
from unittest.mock import AsyncMock

import pytest
import requests
import structlog
from sqlalchemy.ext.asyncio import AsyncSession
from structlog.testing import capture_logs

from orbit.crypto import hash_uid
from tests.conftest import run_async, run_row_query, run_scalar_query

_TODAY = datetime.date.today().isoformat()
_EMULATOR_API_KEY = "fake-api-key"  # the emulator ignores this value entirely; see conftest.py
_TEST_USER_PASSWORD = "Password123!"

# The five per-user tables `lifecycle.erase.erase_account_rows` must clear —
# deliberately NOT including `muscle_level_templates` (a global reference
# table, no `owner_uid` column, not part of the cascade).
_PER_USER_TABLES = ("food_entries", "set_events", "weight_entries", "muscle_base_levels", "profiles")

# capture_logs() disables ALL configured processors by default and applies
# only what is passed via `processors=` — reapply add_log_level so captured
# entries carry the `level` field (same pattern as test_edge.py/test_logging.py).
_LEVEL_TAGGING_PROCESSOR = [structlog.processors.add_log_level]

_run = run_async
_scalar = run_scalar_query
_rows = run_row_query


@pytest.fixture(scope="module", autouse=True)
def _use_migrated_database(_wire_app_database):
    """Opt this module into the shared Postgres-wiring fixture (`conftest.py`,
    rule-of-two)."""
    yield


def _auth_header(id_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {id_token}"}


def _now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _forge_token_with_claim_overrides(id_token: str, overrides: dict) -> str:
    """Rebuild an emulator-issued (unsigned, `alg: none`) token with modified
    claims — the emulator never checks a signature, so this reliably
    produces a token with an otherwise-impossible claim shape (mirrors
    `tests/integration/test_auth.py`'s forging helper, used here for a stale
    `auth_time` rather than an expired/wrong-audience claim)."""
    header_segment, payload_segment, _signature_segment = id_token.split(".")

    def _pad(segment: str) -> str:
        return segment + "=" * (-len(segment) % 4)

    def _b64url_json(payload: dict) -> str:
        raw = json.dumps(payload).encode()
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    header = json.loads(base64.urlsafe_b64decode(_pad(header_segment)))
    payload = json.loads(base64.urlsafe_b64decode(_pad(payload_segment)))
    payload.update(overrides)
    return f"{_b64url_json(header)}.{_b64url_json(payload)}."


def _sign_up(firebase_emulator: str, email: str) -> dict:
    """Sign up a second, independent Firebase principal (a distinct uid) —
    the cross-owner isolation half of the erasure-cascade test."""
    response = requests.post(
        f"http://{firebase_emulator}/identitytoolkit.googleapis.com/v1/accounts:signUp",
        params={"key": _EMULATOR_API_KEY},
        json={"email": email, "password": _TEST_USER_PASSWORD, "returnSecureToken": True},
        timeout=5,
    )
    response.raise_for_status()
    data = response.json()
    return {"uid": data["localId"], "id_token": data["idToken"]}


def _bench_press_exercise_id(postgres_url: str) -> int:
    """The seeded "Barbell Bench Press" exercise id, fetched from the live
    migrated DB rather than hardcoding an autoincrement value (mirrors
    `test_train.py`'s `_bench_press_exercise` helper)."""
    rows = _run(_rows(postgres_url, "SELECT id FROM exercises WHERE name = :name", name="Barbell Bench Press"))
    return rows[0].id


def _seed_full_domain_for_uid(client, headers: dict[str, str], postgres_url: str) -> None:
    """Populate at least one row in EVERY per-user table the erasure cascade
    must clear: a profile + 13 muscle-base-level rows (bootstrap), one food
    entry, one set event, and one weight entry."""
    assert client.post("/me/bootstrap", headers=headers).status_code == 200

    fuel_body = {
        "meal_group": "breakfast",
        "day_key": _TODAY,
        "logged_at": _now_iso(),
        "name": "Seed Meal",
        "kcal": 400,
        "protein_g": 20.0,
        "carb_g": 30.0,
        "fat_g": 10.0,
    }
    assert client.post("/fuel/entries", headers=headers, json=fuel_body).status_code == 201

    set_body = {
        "exercise_id": _bench_press_exercise_id(postgres_url),
        "set_index": 0,
        "day_key": _TODAY,
        "done_at": _now_iso(),
    }
    assert client.post("/train/sets", headers=headers, json=set_body).status_code == 200

    weight_body = {"weight_kg": 80.0, "day_key": _TODAY, "logged_at": _now_iso()}
    assert client.post("/weight", headers=headers, json=weight_body).status_code == 201


def _table_counts_for_uid(postgres_url: str, uid: str) -> dict[str, int]:
    """Direct, ORM-independent row counts per table for `uid` — the
    ground-truth the erasure-cascade assertions are built on."""
    return {
        table: _run(_scalar(postgres_url, f"SELECT count(*) FROM {table} WHERE owner_uid = :uid", uid=uid))
        for table in _PER_USER_TABLES
    }


# ---------------------------------------------------------------------------
# Unauthenticated access (AC2)
# ---------------------------------------------------------------------------


def test_delete_account_denies_a_missing_token(client):
    response = client.request("DELETE", "/me")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


# ---------------------------------------------------------------------------
# Fresh re-auth required (AC5, ASVS 7.5.1)
# ---------------------------------------------------------------------------


def test_delete_account_requires_fresh_reauth_and_deletes_nothing_when_stale(
    client, firebase_test_user, postgres_url
):
    """A token whose `auth_time` is stale (> 5 min) must be rejected 401 —
    and, critically, nothing is deleted: the fresh-reauth guard runs before
    any erasure logic at all."""
    headers = _auth_header(firebase_test_user["id_token"])
    uid = firebase_test_user["uid"]
    assert client.post("/me/bootstrap", headers=headers).status_code == 200

    stale_token = _forge_token_with_claim_overrides(
        firebase_test_user["id_token"], {"auth_time": int(time.time()) - 600}
    )
    response = client.request("DELETE", "/me", headers=_auth_header(stale_token))
    assert response.status_code == 401

    assert _run(_scalar(postgres_url, "SELECT count(*) FROM profiles WHERE owner_uid = :uid", uid=uid)) == 1


# ---------------------------------------------------------------------------
# Erasure cascade + cross-owner isolation + audit event (AC5, AC21)
# ---------------------------------------------------------------------------


def test_delete_account_erases_the_full_cascade_leaves_the_other_owner_untouched_and_audits(
    client, firebase_test_user, firebase_emulator, postgres_url
):
    """Seed every declared per-user store for uid A AND a second uid B, then
    delete A's account and assert: every one of A's rows is gone from every
    table (raw DB counts — not just an API-level read), B's rows in every
    table are completely untouched, the Firebase identity is genuinely gone
    (A's still-unexpired token stops verifying), and an `account.delete`
    audit event was emitted carrying the hashed uid + outcome, never the
    raw uid."""
    headers_a = _auth_header(firebase_test_user["id_token"])
    uid_a = firebase_test_user["uid"]
    _seed_full_domain_for_uid(client, headers_a, postgres_url)

    user_b = _sign_up(firebase_emulator, f"account-delete-b-{uuid.uuid4().hex}@example.com")
    headers_b = _auth_header(user_b["id_token"])
    uid_b = user_b["uid"]
    _seed_full_domain_for_uid(client, headers_b, postgres_url)

    counts_b_before = _table_counts_for_uid(postgres_url, uid_b)
    assert all(count > 0 for count in counts_b_before.values()), counts_b_before

    with capture_logs(processors=_LEVEL_TAGGING_PROCESSOR) as captured:
        response = client.request("DELETE", "/me", headers=headers_a)
    assert response.status_code == 204

    counts_a_after = _table_counts_for_uid(postgres_url, uid_a)
    assert all(count == 0 for count in counts_a_after.values()), counts_a_after

    counts_b_after = _table_counts_for_uid(postgres_url, uid_b)
    assert counts_b_after == counts_b_before, "B's rows must be completely untouched by A's deletion"

    # The Firebase identity is genuinely gone, not just the DB rows: A's own
    # still-unexpired token no longer verifies against the emulator.
    reuse_response = client.post("/me/signout", headers=headers_a)
    assert reuse_response.status_code == 401

    audit_events = [entry for entry in captured if entry.get("event") == "account.delete"]
    assert len(audit_events) == 1
    audit_event = audit_events[0]
    assert audit_event["outcome"] == "success"
    assert audit_event["user_id"] == hash_uid(uid_a)
    assert uid_a not in str(audit_event), "the raw uid must never appear in the audit event"


# ---------------------------------------------------------------------------
# Atomic rollback (T2-5 / ASVS 2.3.3)
# ---------------------------------------------------------------------------


def test_delete_account_atomic_rollback_on_fault_injected_mid_cascade_failure(
    client, firebase_test_user, postgres_url, monkeypatch
):
    """A fault injected partway through the five-table cascade (a
    monkeypatched `AsyncSession.execute` that raises on its 3rd call — after
    `food_entries` and `set_events` have already been deleted within the
    transaction, before `weight_entries`) must roll the WHOLE cascade back —
    no table shows a partial delete."""
    headers = _auth_header(firebase_test_user["id_token"])
    uid = firebase_test_user["uid"]
    _seed_full_domain_for_uid(client, headers, postgres_url)

    before = _table_counts_for_uid(postgres_url, uid)
    assert all(count > 0 for count in before.values()), "the seed helper must populate every table"

    original_execute = AsyncSession.execute
    call_count = {"n": 0}

    async def _flaky_execute(self, *args, **kwargs):
        call_count["n"] += 1
        if call_count["n"] == 3:
            raise RuntimeError("fault-injected failure mid-cascade (T2-5 / ASVS 2.3.3 test)")
        return await original_execute(self, *args, **kwargs)

    monkeypatch.setattr(AsyncSession, "execute", _flaky_execute)

    response = client.request("DELETE", "/me", headers=headers)

    # The generic error-envelope facade (edge/errors.py) catches the raised
    # RuntimeError and returns a safe, detail-free 500 — never a partial 204.
    assert response.status_code == 500
    assert "RuntimeError" not in response.text
    assert "fault-injected" not in response.text

    # These queries use a bare Core connection, never `AsyncSession`, so they
    # are unaffected by the monkeypatch above and see the real DB state.
    after = _table_counts_for_uid(postgres_url, uid)
    assert after == before, "a partial cascade failure must roll back EVERY table, not just the ones after the fault"


# ---------------------------------------------------------------------------
# Post-commit Firebase-failure branch (Operator addendum #3)
# ---------------------------------------------------------------------------


def test_delete_account_post_commit_firebase_failure_returns_502_and_is_retry_safe(
    client, firebase_test_user, postgres_url, monkeypatch
):
    """The DB cascade transaction commits FIRST; if the subsequent Firebase
    identity delete then fails, the client sees a generic 502 (never the raw
    exception detail) and the DB rows are already gone. The endpoint is
    retry-safe: a second call re-attempts only the identity delete (the
    cascade delete is idempotent — a retry matches zero rows, a harmless
    no-op)."""
    headers = _auth_header(firebase_test_user["id_token"])
    uid = firebase_test_user["uid"]
    assert client.post("/me/bootstrap", headers=headers).status_code == 200

    call_count = {"n": 0}

    def _flaky_delete_firebase_user(_target_uid):
        call_count["n"] += 1
        if call_count["n"] == 1:
            raise RuntimeError("simulated Firebase outage — must never reach the client")

    monkeypatch.setattr("orbit.routes.me.delete_firebase_user", _flaky_delete_firebase_user)

    first_response = client.request("DELETE", "/me", headers=headers)
    assert first_response.status_code == 502
    assert "simulated Firebase outage" not in first_response.text
    assert "RuntimeError" not in first_response.text
    body = first_response.json()
    assert body["error"]["message"] == "Account data was erased, but identity deletion failed. Please retry."

    # The DB cascade already committed — the account's data is gone even
    # though the identity delete failed afterward.
    assert _run(_scalar(postgres_url, "SELECT count(*) FROM profiles WHERE owner_uid = :uid", uid=uid)) == 0

    second_response = client.request("DELETE", "/me", headers=headers)
    assert second_response.status_code == 204, "a retry must succeed once the identity delete stops failing"
    assert call_count["n"] == 2, "the retry must re-attempt the identity delete exactly once more"


# ---------------------------------------------------------------------------
# Tier-2 throttle (plan's explicit write-route list)
# ---------------------------------------------------------------------------


def test_delete_account_is_tier2_throttled(
    client, firebase_test_user, monkeypatch, _wire_real_redis_and_tight_tier2_limit
):
    """`DELETE /me` is in plan.md's explicit Tier-2 (uid-keyed) write-route
    list — verify the dependency actually applies. The destructive erase
    logic itself is stubbed out here so the account/token stay valid across
    both calls, isolating pure throttle behavior (the real cascade + retry
    semantics are covered by the dedicated tests above). Not a module-wide
    fixture: this file's other tests make several Tier-2-gated calls (fuel/
    train/weight) per uid via `_seed_full_domain_for_uid`, and Tier-2's
    bucket key is uid-only, not per-route — a shared tightened limit would
    starve them."""
    monkeypatch.setattr("orbit.routes.me.erase_account_rows", AsyncMock(return_value={}))
    monkeypatch.setattr("orbit.routes.me.delete_firebase_user", lambda uid: None)

    headers = _auth_header(firebase_test_user["id_token"])
    first_response = client.request("DELETE", "/me", headers=headers)
    assert first_response.status_code == 204

    second_response = client.request("DELETE", "/me", headers=headers)
    assert second_response.status_code == 429
    assert second_response.json()["error"]["code"] == "rate_limited"
