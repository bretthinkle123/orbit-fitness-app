"""Integration tests for `POST /weight` and `GET /weight` (T7; AC12, AC14)
against a REAL testcontainers Postgres (migrated via the real `alembic`
CLI) and the REAL Firebase Auth emulator (Operator addendum #1 — no mocked
guard).
"""

from __future__ import annotations

import asyncio
import datetime

import pytest
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine

from tests.conftest import run_scalar_query

_TODAY = datetime.date.today()


async def _seed_minimal_weight_entries(
    database_url: str, owner_uid: str, count: int, *, days_ago: int = 1
) -> None:
    """Bulk-insert `count` minimal, valid `weight_entries` rows directly
    (bypassing the API/HTTP layer, and any per-call rate limiting) so a
    read-LIMIT-truncation test doesn't need `count` real round trips.
    Parameterized (never string-interpolated) per the rule-of-two seed-SQL
    convention (`test_fuel.py`'s `_seed_minimal_food_entries` is the sibling
    pattern for `food_entries`)."""
    engine = create_async_engine(database_url)
    day_key_date = _TODAY - datetime.timedelta(days=days_ago)
    try:
        async with engine.begin() as connection:
            for index in range(count):
                await connection.execute(
                    sa.text(
                        "INSERT INTO weight_entries (owner_uid, weight_kg, day_key, logged_at) "
                        "VALUES (:owner_uid, :weight_kg, :day_key, now())"
                    ),
                    {"owner_uid": owner_uid, "weight_kg": 70.0 + (index % 10) * 0.1, "day_key": day_key_date},
                )
    finally:
        await engine.dispose()


@pytest.fixture(scope="module", autouse=True)
def _use_migrated_database(_wire_app_database):
    """Opt this module into the shared Postgres-wiring fixture (`conftest.py`,
    rule-of-two)."""
    yield


def _auth_header(id_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {id_token}"}


def _iso_at(days_ago: int) -> str:
    """An aware UTC instant `days_ago` days in the past (or future, if
    negative) — for a client-provided `logged_at`."""
    return (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days_ago)).isoformat()


def _day_key(days_ago: int) -> str:
    return (_TODAY - datetime.timedelta(days=days_ago)).isoformat()


def _create_weight(client, headers: dict[str, str], weight_kg: float, days_ago: int = 0):
    return client.post(
        "/weight",
        headers=headers,
        json={"weight_kg": weight_kg, "day_key": _day_key(days_ago), "logged_at": _iso_at(days_ago)},
    )


# ---------------------------------------------------------------------------
# Unauthenticated access (AC2)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("method,path", [("POST", "/weight"), ("GET", "/weight")])
def test_weight_routes_deny_a_missing_token(client, method, path):
    response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


# ---------------------------------------------------------------------------
# POST /weight — canonical kg (AC12)
# ---------------------------------------------------------------------------


def test_create_weight_entry_round_trips_canonical_kg(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    response = _create_weight(client, headers, 82.3)
    assert response.status_code == 201
    entry = response.json()
    assert entry["weight_kg"] == 82.3
    assert "id" in entry

    window = client.get("/weight", headers=headers).json()
    assert window["latest"]["weight_kg"] == 82.3
    assert any(item["weight_kg"] == 82.3 for item in window["entries"])


@pytest.mark.parametrize("weight_kg", [19.9, 500.1])
def test_create_weight_entry_rejects_out_of_bounds_weight(client, firebase_test_user, weight_kg):
    """`weight_kg` bounds mirror the `weight_entries` DB CHECK (20..500)
    exactly — the schema is the only thing a live request can ever hit; the
    DB constraint itself is defense-in-depth, already covered by T2's
    migration-level constraint test and T3's `classify_integrity_error`
    unit tests (no live-API path bypasses the schema to reach it)."""
    headers = _auth_header(firebase_test_user["id_token"])
    response = _create_weight(client, headers, weight_kg)
    assert response.status_code == 422


def test_create_weight_entry_rejects_a_future_timestamp(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    response = _create_weight(client, headers, 80.0, days_ago=-1)  # tomorrow, well past the 5-min skew
    assert response.status_code == 422


def test_create_weight_entry_accepts_a_backdated_timestamp(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    response = _create_weight(client, headers, 80.0, days_ago=3)
    assert response.status_code == 201


# ---------------------------------------------------------------------------
# GET /weight — fixed 30-day window, NO PARAMS (AC12, AC14, AC16's F4-01 shape)
# ---------------------------------------------------------------------------


def test_get_weight_window_excludes_an_entry_31_days_old(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    assert _create_weight(client, headers, 90.0, days_ago=31).status_code == 201
    assert _create_weight(client, headers, 80.0, days_ago=2).status_code == 201

    window = client.get("/weight", headers=headers).json()
    weights_in_window = {item["weight_kg"] for item in window["entries"]}
    assert 80.0 in weights_in_window
    assert 90.0 not in weights_in_window, "an entry 31 days old must be excluded from the 30-day window"

    # The row still exists (this is a read-side scope, not a data-loss bug) —
    # confirmed directly against the DB, the same pattern T6 used for its
    # cross-owner checks.
    count = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM weight_entries WHERE owner_uid = :uid AND weight_kg = 90.0",
            uid=firebase_test_user["uid"],
        )
    )
    assert count == 1


def test_get_weight_window_read_limit_truncates_even_without_a_write_side_cap(
    client, firebase_test_user, postgres_url
):
    """AC14 backstop test: unlike `food_entries`/`set_events`, `POST /weight`
    has NO per-day/per-window write-side cap at all — the 200-row hard LIMIT
    on `GET /weight`'s query (`repositories/weight.py`) is the ONLY control
    bounding this read, not a backstop behind a write cap. Seed 205 rows
    directly (well within the 30-day window) and assert the response still
    truncates to exactly 200 entries, never 205 and never an unbounded
    result set / 500."""
    uid = firebase_test_user["uid"]
    asyncio.run(_seed_minimal_weight_entries(postgres_url, uid, 205, days_ago=1))

    headers = _auth_header(firebase_test_user["id_token"])
    response = client.get("/weight", headers=headers)
    assert response.status_code == 200
    window = response.json()

    assert len(window["entries"]) == 200, (
        "the read-side LIMIT must truncate to 200 even though 205 rows exist "
        "in the 30-day window — there is no write-side cap to rely on here"
    )

    raw_count = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM weight_entries WHERE owner_uid = :uid",
            uid=uid,
        )
    )
    assert raw_count == 205


def test_get_weight_rejects_a_day_key_query_param(client, firebase_test_user):
    """The exact F4-01 escape shape the audit flagged: `GET /weight` takes a
    FIXED server-computed window and NO params at all — `?day_key=` must
    422, never silently pass through."""
    headers = _auth_header(firebase_test_user["id_token"])
    response = client.get(f"/weight?day_key={_TODAY.isoformat()}", headers=headers)
    assert response.status_code == 422


def test_get_weight_rejects_any_other_undeclared_query_param(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    response = client.get("/weight?unexpected=1", headers=headers)
    assert response.status_code == 422


def test_get_weight_window_is_empty_for_a_brand_new_account(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    window = client.get("/weight", headers=headers).json()
    assert window == {"entries": [], "latest": None, "weekly_delta_kg": None}


def test_weekly_delta_math_with_a_hand_computed_fixture(client, firebase_test_user):
    """latest (day -2, 78.0 kg) minus the most recent entry at/before 7 days
    prior to it (day -10, 80.0 kg) -> -2.0 kg."""
    headers = _auth_header(firebase_test_user["id_token"])
    assert _create_weight(client, headers, 80.0, days_ago=10).status_code == 201
    assert _create_weight(client, headers, 78.0, days_ago=2).status_code == 201

    window = client.get("/weight", headers=headers).json()
    assert window["latest"]["weight_kg"] == 78.0
    assert window["weekly_delta_kg"] == -2.0


def test_weekly_delta_is_null_without_a_weeks_history(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    assert _create_weight(client, headers, 75.0, days_ago=1).status_code == 201

    window = client.get("/weight", headers=headers).json()
    assert window["weekly_delta_kg"] is None


# ---------------------------------------------------------------------------
# Cross-owner isolation (AC3)
# ---------------------------------------------------------------------------


def test_weight_window_never_crosses_owners(client, firebase_test_user, firebase_second_user, postgres_url):
    headers_a = _auth_header(firebase_test_user["id_token"])
    assert _create_weight(client, headers_a, 91.4).status_code == 201

    headers_b = _auth_header(firebase_second_user()["id_token"])

    window_b = client.get("/weight", headers=headers_b).json()
    assert window_b == {"entries": [], "latest": None, "weekly_delta_kg": None}

    count_for_a = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM weight_entries WHERE owner_uid = :uid AND weight_kg = 91.4",
            uid=firebase_test_user["uid"],
        )
    )
    assert count_for_a == 1, "B's read must not have touched A's row"
