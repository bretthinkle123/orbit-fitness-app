"""Integration tests for `GET /body` (T6; AC11, AC14) against a REAL
testcontainers Postgres (migrated via the real `alembic` CLI) and the REAL
Firebase Auth emulator (Operator addendum #1 — no mocked guard).
"""

from __future__ import annotations

import asyncio
import datetime

import pytest
import requests

from tests.conftest import run_row_query

_TODAY = datetime.date.today()
_YESTERDAY = _TODAY - datetime.timedelta(days=1)

# Push Day's own seeded muscle tags (migrations/versions/0002...): 3 chest
# exercises, 1 shoulders, 1 triceps (plan §Derived formulas: "Push Day ->
# Chest/Shoulders/Triceps").
_PUSH_DAY_MUSCLE_GROUPS = {"chest", "shoulders", "triceps"}


@pytest.fixture(scope="module", autouse=True)
def _use_migrated_database(_wire_app_database):
    """Opt this module into the shared Postgres-wiring fixture (`conftest.py`,
    rule-of-two)."""
    yield


def _auth_header(id_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {id_token}"}


def _now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _bootstrap(client, headers: dict[str, str]) -> None:
    assert client.post("/me/bootstrap", headers=headers).status_code == 200


def _exercise_id_for(postgres_url, name: str) -> int:
    rows = asyncio.run(run_row_query(postgres_url, "SELECT id FROM exercises WHERE name = :name", name=name))
    return rows[0].id


def _mark_set(client, headers: dict[str, str], exercise_id: int, day_key: datetime.date) -> None:
    response = client.post(
        "/train/sets",
        headers=headers,
        json={"exercise_id": exercise_id, "set_index": 0, "day_key": day_key.isoformat(), "done_at": _now_iso()},
    )
    assert response.status_code == 200


def test_body_route_denies_a_missing_token(client):
    response = client.get(f"/body?day_key={_TODAY.isoformat()}")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


def test_get_body_day_returns_all_13_levels_with_no_trained_today_flags(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)

    template_levels = {
        row.muscle_group: row.level
        for row in asyncio.run(run_row_query(postgres_url, "SELECT muscle_group, level FROM muscle_level_templates"))
    }

    response = client.get(f"/body?day_key={_TODAY.isoformat()}", headers=headers)
    assert response.status_code == 200
    body = response.json()

    assert len(body["muscle_levels"]) == 13
    for row in body["muscle_levels"]:
        assert row["level"] == template_levels[row["muscle_group"]]
        assert row["trained_today"] is False
    # Displayed in the design's own row order (models.MUSCLE_GROUPS), not an
    # arbitrary DB sort.
    assert [row["muscle_group"] for row in body["muscle_levels"]][:3] == ["chest", "shoulders", "traps"]


def test_get_body_day_404s_before_bootstrap(client, firebase_test_user):
    response = client.get(f"/body?day_key={_TODAY.isoformat()}", headers=_auth_header(firebase_test_user["id_token"]))
    assert response.status_code == 404


def test_get_body_day_rejects_an_undeclared_query_param(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    response = client.get(f"/body?day_key={_TODAY.isoformat()}&unexpected=1", headers=headers)
    assert response.status_code == 422


def test_trained_today_glows_only_the_muscle_actually_trained(client, firebase_test_user, postgres_url):
    """A single set on a chest exercise (Barbell Bench Press) must glow
    Chest ONLY, not Shoulders/Triceps too, even though all three ride the
    same "Push Day" program — the derivation is per set_event's exercise
    `muscle_tag`, not "any set logged on the program"."""
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    bench_press_id = _exercise_id_for(postgres_url, "Barbell Bench Press")
    _mark_set(client, headers, bench_press_id, _TODAY)

    body = client.get(f"/body?day_key={_TODAY.isoformat()}", headers=headers).json()
    trained = {row["muscle_group"] for row in body["muscle_levels"] if row["trained_today"]}
    assert trained == {"chest"}


def test_trained_today_covers_all_three_push_day_groups_when_each_is_trained(
    client, firebase_test_user, postgres_url
):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    for exercise_name in ("Barbell Bench Press", "Seated Overhead Press", "Triceps Pushdown"):
        _mark_set(client, headers, _exercise_id_for(postgres_url, exercise_name), _TODAY)

    body = client.get(f"/body?day_key={_TODAY.isoformat()}", headers=headers).json()
    trained = {row["muscle_group"] for row in body["muscle_levels"] if row["trained_today"]}
    assert trained == _PUSH_DAY_MUSCLE_GROUPS


def test_trained_today_is_day_scoped(client, firebase_test_user, postgres_url):
    """AC14: a set logged for yesterday must not glow today's Body view, but
    DOES glow yesterday's own view."""
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    bench_press_id = _exercise_id_for(postgres_url, "Barbell Bench Press")
    _mark_set(client, headers, bench_press_id, _YESTERDAY)

    today_body = client.get(f"/body?day_key={_TODAY.isoformat()}", headers=headers).json()
    assert all(row["trained_today"] is False for row in today_body["muscle_levels"])

    yesterday_body = client.get(f"/body?day_key={_YESTERDAY.isoformat()}", headers=headers).json()
    trained_yesterday = {row["muscle_group"] for row in yesterday_body["muscle_levels"] if row["trained_today"]}
    assert trained_yesterday == {"chest"}


def test_body_trained_today_never_crosses_owners(client, firebase_test_user, firebase_emulator, postgres_url):
    """A trains chest; B (a distinct, bootstrapped principal) must see their
    OWN untrained Body view, never A's glow."""
    headers_a = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers_a)
    _mark_set(client, headers_a, _exercise_id_for(postgres_url, "Barbell Bench Press"), _TODAY)

    signup_b = requests.post(
        f"http://{firebase_emulator}/identitytoolkit.googleapis.com/v1/accounts:signUp",
        params={"key": "fake-api-key"},
        json={"email": "body-idor-b@example.com", "password": "Password123!", "returnSecureToken": True},
        timeout=5,
    )
    signup_b.raise_for_status()
    headers_b = _auth_header(signup_b.json()["idToken"])
    _bootstrap(client, headers_b)

    body_b = client.get(f"/body?day_key={_TODAY.isoformat()}", headers=headers_b).json()
    assert all(row["trained_today"] is False for row in body_b["muscle_levels"])
