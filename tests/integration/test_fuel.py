"""Integration tests for `GET /catalog/quick-foods`, `POST /fuel/entries`,
and `GET /fuel` (T5; AC6, AC7, AC14, AC15's first live exercise) against a
REAL testcontainers Postgres (migrated via the real `alembic` CLI) and the
REAL Firebase Auth emulator (Operator addendum #1 — no mocked guard).
"""

from __future__ import annotations

import asyncio
import datetime

import pytest
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine

from orbit.schemas.fuel import STATIC_COACH_MESSAGE
from tests.conftest import run_scalar_query

_TODAY = datetime.date.today().isoformat()
_YESTERDAY = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()


@pytest.fixture(scope="module", autouse=True)
def _use_migrated_database(_wire_app_database):
    """Opt this module into the shared Postgres-wiring fixture (`conftest.py`,
    rule-of-two — `test_profile.py` was the first consumer)."""
    yield


def _auth_header(id_token: str) -> dict[str, str]:
    """Build the `Authorization: Bearer <token>` header every protected
    route requires."""
    return {"Authorization": f"Bearer {id_token}"}


def _explicit_macro_body(*, day_key: str, logged_at: str, meal_group: str = "breakfast", **overrides) -> dict:
    """A valid `POST /fuel/entries` body via the explicit-macros path."""
    body = {
        "meal_group": meal_group,
        "day_key": day_key,
        "logged_at": logged_at,
        "name": "Test Meal",
        "kcal": 500,
        "protein_g": 30.0,
        "carb_g": 40.0,
        "fat_g": 15.0,
    }
    body.update(overrides)
    return body


def _now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


async def _seed_minimal_food_entries(database_url: str, owner_uid: str, day_key: str, count: int) -> None:
    """Bulk-insert `count` minimal, valid `food_entries` rows directly
    (bypassing the API/HTTP layer) so the 200-cap test doesn't need 200 real
    round trips — the values themselves are fixed constants, never
    interpolated into the SQL string, so this stays a parameterized insert."""
    engine = create_async_engine(database_url)
    day_key_date = datetime.date.fromisoformat(day_key)  # asyncpg needs a real `date`, not an ISO string
    try:
        async with engine.begin() as connection:
            for index in range(count):
                await connection.execute(
                    sa.text(
                        "INSERT INTO food_entries (owner_uid, name, kcal, protein_g, carb_g, fat_g, "
                        "meal_group, logged_at, day_key) VALUES "
                        "(:owner_uid, :name, 100, 5, 10, 2, 'snacks', now(), :day_key)"
                    ),
                    {"owner_uid": owner_uid, "name": f"Seed {index}", "day_key": day_key_date},
                )
    finally:
        await engine.dispose()


# ---------------------------------------------------------------------------
# Unauthenticated access (AC2)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "method,path",
    [
        ("GET", "/catalog/quick-foods"),
        ("POST", "/fuel/entries"),
        ("GET", f"/fuel?day_key={_TODAY}"),
    ],
)
def test_fuel_routes_deny_a_missing_token(client, method, path):
    response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


# ---------------------------------------------------------------------------
# GET /catalog/quick-foods (AC6)
# ---------------------------------------------------------------------------


def test_quick_food_catalog_returns_the_seeded_rows_with_macros(client, firebase_test_user):
    response = client.get("/catalog/quick-foods", headers=_auth_header(firebase_test_user["id_token"]))
    assert response.status_code == 200
    catalog = response.json()
    names = {item["name"] for item in catalog}
    assert names == {"Salmon & Rice Bowl", "Whey Shake", "Chicken Stir-fry"}
    for item in catalog:
        assert item["kcal"] > 0
        assert item["protein_g"] >= 0
        assert item["carb_g"] >= 0
        assert item["fat_g"] >= 0


def test_quick_food_catalog_rejects_an_undeclared_query_param(client, firebase_test_user):
    response = client.get(
        "/catalog/quick-foods?unexpected=1", headers=_auth_header(firebase_test_user["id_token"])
    )
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# POST /fuel/entries — create (AC7, AC15's first live exercise)
# ---------------------------------------------------------------------------


def test_create_fuel_entry_from_a_quick_food(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    catalog = client.get("/catalog/quick-foods", headers=headers).json()
    quick_food = catalog[0]

    response = client.post(
        "/fuel/entries",
        headers=headers,
        json={
            "meal_group": "lunch",
            "day_key": _TODAY,
            "logged_at": _now_iso(),
            "quick_food_id": quick_food["id"],
        },
    )
    assert response.status_code == 201
    entry = response.json()
    assert entry["name"] == quick_food["name"]
    assert entry["kcal"] == quick_food["kcal"]
    assert entry["protein_g"] == quick_food["protein_g"]
    assert entry["carb_g"] == quick_food["carb_g"]
    assert entry["fat_g"] == quick_food["fat_g"]
    assert entry["meal_group"] == "lunch"
    assert "id" in entry


def test_create_fuel_entry_from_explicit_macros(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    body = _explicit_macro_body(day_key=_TODAY, logged_at=_now_iso(), meal_group="dinner")

    response = client.post("/fuel/entries", headers=headers, json=body)
    assert response.status_code == 201
    entry = response.json()
    assert entry["name"] == "Test Meal"
    assert entry["kcal"] == 500
    assert entry["protein_g"] == 30.0
    assert entry["carb_g"] == 40.0
    assert entry["fat_g"] == 15.0
    assert entry["meal_group"] == "dinner"


def test_create_fuel_entry_backdated_timestamp_is_accepted(client, firebase_test_user):
    """AC15's first live exercise: backdating is explicitly allowed."""
    headers = _auth_header(firebase_test_user["id_token"])
    backdated = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=3)).isoformat()
    body = _explicit_macro_body(day_key=_YESTERDAY, logged_at=backdated)

    response = client.post("/fuel/entries", headers=headers, json=body)
    assert response.status_code == 201


def test_create_fuel_entry_future_timestamp_is_rejected(client, firebase_test_user):
    """AC15's first live exercise: a client-provided timestamp more than the
    skew ahead of server time is a 422, never silently accepted."""
    headers = _auth_header(firebase_test_user["id_token"])
    ten_minutes_from_now = (
        datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)
    ).isoformat()
    body = _explicit_macro_body(day_key=_TODAY, logged_at=ten_minutes_from_now)

    response = client.post("/fuel/entries", headers=headers, json=body)
    assert response.status_code == 422


def test_create_fuel_entry_rejects_both_quick_food_id_and_explicit_macros(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    body = _explicit_macro_body(day_key=_TODAY, logged_at=_now_iso(), quick_food_id=1)

    response = client.post("/fuel/entries", headers=headers, json=body)
    assert response.status_code == 422


def test_create_fuel_entry_rejects_neither_source(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    response = client.post(
        "/fuel/entries",
        headers=headers,
        json={"meal_group": "breakfast", "day_key": _TODAY, "logged_at": _now_iso()},
    )
    assert response.status_code == 422


def test_create_fuel_entry_rejects_an_unknown_quick_food_id(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    response = client.post(
        "/fuel/entries",
        headers=headers,
        json={
            "meal_group": "breakfast",
            "day_key": _TODAY,
            "logged_at": _now_iso(),
            "quick_food_id": 999999,
        },
    )
    assert response.status_code == 404


def test_day_entry_cap_rejects_the_201st_entry(client, firebase_test_user, postgres_url):
    """AC7/AC14: a day already at the 200-row cap rejects one more with a
    4xx, never a 500 — and the row count stays at 200, not 201."""
    uid = firebase_test_user["uid"]
    day_key = _TODAY
    asyncio.run(_seed_minimal_food_entries(postgres_url, uid, day_key, 200))

    headers = _auth_header(firebase_test_user["id_token"])
    body = _explicit_macro_body(day_key=day_key, logged_at=_now_iso())
    response = client.post("/fuel/entries", headers=headers, json=body)
    assert response.status_code == 422

    count = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM food_entries WHERE owner_uid = :uid AND day_key = :day_key",
            uid=uid,
            day_key=datetime.date.fromisoformat(day_key),
        )
    )
    assert count == 200, "the 201st create must not have persisted"


def test_get_fuel_day_read_limit_truncates_even_if_the_write_cap_is_bypassed(
    client, firebase_test_user, postgres_url
):
    """AC14 backstop test: `get_fuel_day_entries`'s own hard `LIMIT` (defense
    in depth, `repositories/fuel.py`) must truncate the read to 200 rows even
    when the write-side 200/day cap is bypassed entirely — i.e. this proves
    the read-side LIMIT is a REAL, independent backstop, not merely
    unreachable code that happens to pass because the primary (write) cap
    already prevents more than 200 rows from ever existing. Seeds 205 rows
    directly via SQL (the write cap is never consulted for a raw INSERT),
    then asserts `GET /fuel` returns exactly 200 total across meal groups —
    never 205, and never a 500 from an unbounded result set."""
    uid = firebase_test_user["uid"]
    day_key = _TODAY
    asyncio.run(_seed_minimal_food_entries(postgres_url, uid, day_key, 205))

    headers = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers)
    response = client.get(f"/fuel?day_key={day_key}", headers=headers)
    assert response.status_code == 200
    day = response.json()

    total_returned = sum(len(entries) for entries in day["meals"].values())
    assert total_returned == 200, (
        "the read-side LIMIT must truncate to 200 even though 205 rows exist "
        "in the table — this is the backstop, independent of the write cap"
    )

    # Sanity: the raw table really does hold 205 rows (the backstop is doing
    # real work here, not merely reflecting a table that already has <=200).
    raw_count = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM food_entries WHERE owner_uid = :uid AND day_key = :day_key",
            uid=uid,
            day_key=datetime.date.fromisoformat(day_key),
        )
    )
    assert raw_count == 205


# ---------------------------------------------------------------------------
# GET /fuel — grouped read + totals + targets + coach message (AC7, AC14)
# ---------------------------------------------------------------------------


def test_get_fuel_day_groups_entries_by_meal_with_totals_and_targets(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    day_key = _TODAY
    client.post("/me/bootstrap", headers=headers)

    breakfast_body = _explicit_macro_body(
        day_key=day_key, logged_at=_now_iso(), meal_group="breakfast",
        name="Oats", kcal=300, protein_g=10.0, carb_g=50.0, fat_g=5.0,
    )
    lunch_body = _explicit_macro_body(
        day_key=day_key, logged_at=_now_iso(), meal_group="lunch",
        name="Salad", kcal=400, protein_g=20.0, carb_g=30.0, fat_g=10.0,
    )
    assert client.post("/fuel/entries", headers=headers, json=breakfast_body).status_code == 201
    assert client.post("/fuel/entries", headers=headers, json=lunch_body).status_code == 201

    response = client.get(f"/fuel?day_key={day_key}", headers=headers)
    assert response.status_code == 200
    day = response.json()

    assert set(day["meals"].keys()) == {"breakfast", "lunch", "snacks", "dinner"}
    assert len(day["meals"]["breakfast"]) == 1
    assert day["meals"]["breakfast"][0]["name"] == "Oats"
    assert len(day["meals"]["lunch"]) == 1
    assert day["meals"]["snacks"] == []
    assert day["meals"]["dinner"] == []

    assert day["totals"]["kcal"] == 700
    assert day["totals"]["protein_g"] == 30.0
    assert day["totals"]["carb_g"] == 80.0
    assert day["totals"]["fat_g"] == 15.0

    assert day["targets"]["kcal_budget"] == 2350
    assert day["targets"]["protein_target_g"] == 185
    assert day["remaining_kcal"] == 2350 - 700
    assert day["coach_message"] == STATIC_COACH_MESSAGE


def test_get_fuel_day_404s_before_bootstrap(client, firebase_test_user):
    response = client.get(f"/fuel?day_key={_TODAY}", headers=_auth_header(firebase_test_user["id_token"]))
    assert response.status_code == 404


def test_get_fuel_day_requires_day_key(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers)
    response = client.get("/fuel", headers=headers)
    assert response.status_code == 422


def test_get_fuel_day_rejects_an_undeclared_query_param(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    client.post("/me/bootstrap", headers=headers)
    response = client.get(f"/fuel?day_key={_TODAY}&unexpected=1", headers=headers)
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# Cross-owner isolation (AC3)
# ---------------------------------------------------------------------------


def test_fuel_entries_never_cross_owners(client, firebase_test_user, firebase_second_user):
    """A logs food for today; B (a distinct principal, also bootstrapped)
    reads an empty day — A's entries never appear in B's grouped read or
    totals."""
    headers_a = _auth_header(firebase_test_user["id_token"])
    day_key = _TODAY
    client.post(
        "/fuel/entries",
        headers=headers_a,
        json=_explicit_macro_body(day_key=day_key, logged_at=_now_iso()),
    )

    headers_b = _auth_header(firebase_second_user()["id_token"])
    client.post("/me/bootstrap", headers=headers_b)

    response_b = client.get(f"/fuel?day_key={day_key}", headers=headers_b)
    assert response_b.status_code == 200
    day_b = response_b.json()
    assert day_b["totals"]["kcal"] == 0
    assert all(entries == [] for entries in day_b["meals"].values())
