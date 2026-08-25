"""Integration tests for `GET /train`, `POST /train/sets`, and `DELETE
/train/sets` (T6; AC10, AC14) against a REAL testcontainers Postgres
(migrated via the real `alembic` CLI) and the REAL Firebase Auth emulator
(Operator addendum #1 — no mocked guard).
"""

from __future__ import annotations

import asyncio
import datetime

import pytest
import requests
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from orbit.repositories.train import mark_set_done
from tests.conftest import run_row_query, run_scalar_query

def _most_recent_wednesday(today: datetime.date) -> datetime.date:
    """The Wednesday on or before `today`.

    These tests anchor to a mid-week day rather than to the real `today` so
    that `_YESTERDAY` is always in the SAME ISO week as `_TODAY`. With a bare
    `date.today()`, a Monday run put `_YESTERDAY` on the preceding Sunday —
    the previous week under the API's Monday-start bounds (`routes/train.py`
    `_week_bounds`) — and `test_mark_set_done_only_counts_the_requested_day`
    failed one day in seven. Pinning the weekday is safe because the API
    derives every week/day computation from the `day_key` the client sends,
    never from the server clock (`schemas/train.py`).
    """
    return today - datetime.timedelta(days=(today.weekday() - 2) % 7)


_TODAY = _most_recent_wednesday(datetime.date.today())
_YESTERDAY = _TODAY - datetime.timedelta(days=1)


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
    response = client.post("/me/bootstrap", headers=headers)
    assert response.status_code == 200


def _bench_press_exercise(postgres_url) -> dict:
    """The seeded "Barbell Bench Press" exercise (4 sets, muscle_tag=chest)
    — fetched from the live migrated DB rather than hardcoding its id, which
    is an autoincrement value not guaranteed stable across runs."""
    rows = asyncio.run(
        run_row_query(
            postgres_url,
            "SELECT id, sets, muscle_tag FROM exercises WHERE name = :name",
            name="Barbell Bench Press",
        )
    )
    row = rows[0]
    return {"id": row.id, "sets": row.sets, "muscle_tag": row.muscle_tag}


# ---------------------------------------------------------------------------
# Unauthenticated access (AC2)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "method,path",
    [
        ("GET", f"/train?day_key={_TODAY.isoformat()}"),
        ("POST", "/train/sets"),
        ("DELETE", "/train/sets"),
    ],
)
def test_train_routes_deny_a_missing_token(client, method, path):
    response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


# ---------------------------------------------------------------------------
# GET /train — program + exercises + score + week strip (AC10)
# ---------------------------------------------------------------------------


def test_get_train_day_returns_the_seeded_program_with_zero_score_initially(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)

    response = client.get(f"/train?day_key={_TODAY.isoformat()}", headers=headers)
    assert response.status_code == 200
    day = response.json()

    assert day["program"]["name"] == "Push Day"
    assert len(day["exercises"]) == 5
    assert {exercise["muscle_tag"] for exercise in day["exercises"]} == {"chest", "shoulders", "triceps"}
    assert all(exercise["done_set_indexes"] == [] for exercise in day["exercises"])
    assert day["score"] == 512
    assert day["week_strip"] == [False] * 7
    assert day["session_count"] == 0
    assert day["weekly_delta"] == 0


def test_get_train_day_404s_before_bootstrap(client, firebase_test_user):
    response = client.get(
        f"/train?day_key={_TODAY.isoformat()}", headers=_auth_header(firebase_test_user["id_token"])
    )
    assert response.status_code == 404


def test_get_train_day_rejects_an_undeclared_query_param(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    response = client.get(f"/train?day_key={_TODAY.isoformat()}&unexpected=1", headers=headers)
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# POST /train/sets — idempotent create (AC10)
# ---------------------------------------------------------------------------


def test_mark_set_done_is_idempotent_on_replay(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)
    body = {
        "exercise_id": exercise["id"],
        "set_index": 0,
        "day_key": _TODAY.isoformat(),
        "done_at": _now_iso(),
    }

    first_response = client.post("/train/sets", headers=headers, json=body)
    assert first_response.status_code == 200

    second_response = client.post("/train/sets", headers=headers, json=body)
    assert second_response.status_code == 200
    assert second_response.json() == first_response.json(), "a replay must return the SAME row"

    count = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM set_events WHERE owner_uid = :uid AND exercise_id = :exercise_id "
            "AND set_index = 0 AND day_key = :day_key",
            uid=firebase_test_user["uid"],
            exercise_id=exercise["id"],
            day_key=_TODAY,
        )
    )
    assert count == 1, "a replay must not create a second row"


def test_mark_set_done_updates_score_and_week_strip(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)

    for set_index in (0, 1):
        response = client.post(
            "/train/sets",
            headers=headers,
            json={
                "exercise_id": exercise["id"],
                "set_index": set_index,
                "day_key": _TODAY.isoformat(),
                "done_at": _now_iso(),
            },
        )
        assert response.status_code == 200

    day = client.get(f"/train?day_key={_TODAY.isoformat()}", headers=headers).json()
    assert day["score"] == 512 + 2
    assert day["weekly_delta"] == 2
    assert day["session_count"] == 1
    today_index = _TODAY.weekday()
    assert day["week_strip"][today_index] is True
    assert sum(day["week_strip"]) == 1

    marked_exercise = next(e for e in day["exercises"] if e["id"] == exercise["id"])
    assert marked_exercise["done_set_indexes"] == [0, 1]


def test_mark_set_done_only_counts_the_requested_day(client, firebase_test_user, postgres_url):
    """Day-scoping (AC14): a set logged for yesterday must not inflate
    today's score or set state."""
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)

    response = client.post(
        "/train/sets",
        headers=headers,
        json={
            "exercise_id": exercise["id"],
            "set_index": 0,
            "day_key": _YESTERDAY.isoformat(),
            "done_at": (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).isoformat(),
        },
    )
    assert response.status_code == 200

    today = client.get(f"/train?day_key={_TODAY.isoformat()}", headers=headers).json()
    assert today["score"] == 512
    assert all(exercise_out["done_set_indexes"] == [] for exercise_out in today["exercises"])
    # Yesterday's set still counts toward THIS week's strip/delta, though.
    assert today["weekly_delta"] == 1
    assert today["week_strip"][_YESTERDAY.weekday()] is True


def test_mark_set_done_rejects_an_out_of_bounds_set_index(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)  # 4 sets -> valid indexes 0..3

    response = client.post(
        "/train/sets",
        headers=headers,
        json={
            "exercise_id": exercise["id"],
            "set_index": exercise["sets"],  # one past the last valid index
            "day_key": _TODAY.isoformat(),
            "done_at": _now_iso(),
        },
    )
    assert response.status_code == 422


def test_mark_set_done_rejects_an_unknown_exercise_id(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    response = client.post(
        "/train/sets",
        headers=headers,
        json={"exercise_id": 999999, "set_index": 0, "day_key": _TODAY.isoformat(), "done_at": _now_iso()},
    )
    assert response.status_code == 404


def test_mark_set_done_concurrent_identical_requests_create_exactly_one_row(
    firebase_test_user, postgres_url
):
    """Genuine concurrency (not a sequential replay): two calls racing
    `mark_set_done` for the SAME (owner_uid, exercise_id, set_index, day_key)
    on two independent sessions/connections must still land exactly one row
    — the loser gets the existing row back (`created=False`), never an
    error (the same `asyncio.gather` shape as T4's bootstrap race test)."""
    exercise = _bench_press_exercise(postgres_url)
    owner_uid = firebase_test_user["uid"]
    engine = create_async_engine(postgres_url)
    sessionmaker = async_sessionmaker(bind=engine, expire_on_commit=False)

    async def _one_mark_call() -> bool:
        async with sessionmaker() as session, session.begin():
            _set_event, created = await mark_set_done(
                session, owner_uid, exercise["id"], 2, _TODAY, datetime.datetime.now(datetime.timezone.utc)
            )
            return created

    async def _race_twice() -> list[bool]:
        try:
            return await asyncio.gather(_one_mark_call(), _one_mark_call())
        finally:
            await engine.dispose()

    created_flags = asyncio.run(_race_twice())
    assert sorted(created_flags) == [False, True], "exactly one of the two racing calls must be the creator"

    count = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM set_events WHERE owner_uid = :uid AND exercise_id = :exercise_id "
            "AND set_index = 2 AND day_key = :day_key",
            uid=owner_uid,
            exercise_id=exercise["id"],
            day_key=_TODAY,
        )
    )
    assert count == 1


# ---------------------------------------------------------------------------
# DELETE /train/sets — unmark (AC10)
# ---------------------------------------------------------------------------


def test_delete_set_event_drops_the_score(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)

    for set_index in (0, 1):
        client.post(
            "/train/sets",
            headers=headers,
            json={
                "exercise_id": exercise["id"],
                "set_index": set_index,
                "day_key": _TODAY.isoformat(),
                "done_at": _now_iso(),
            },
        )
    assert client.get(f"/train?day_key={_TODAY.isoformat()}", headers=headers).json()["score"] == 514

    delete_response = client.request(
        "DELETE",
        "/train/sets",
        headers=headers,
        json={"exercise_id": exercise["id"], "set_index": 0, "day_key": _TODAY.isoformat()},
    )
    assert delete_response.status_code == 204

    day_after_delete = client.get(f"/train?day_key={_TODAY.isoformat()}", headers=headers).json()
    assert day_after_delete["score"] == 513
    marked_exercise = next(e for e in day_after_delete["exercises"] if e["id"] == exercise["id"])
    assert marked_exercise["done_set_indexes"] == [1]


def test_delete_set_event_is_idempotent_on_an_already_unmarked_set(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)

    response = client.request(
        "DELETE",
        "/train/sets",
        headers=headers,
        json={"exercise_id": exercise["id"], "set_index": 3, "day_key": _TODAY.isoformat()},
    )
    assert response.status_code == 204


def test_delete_set_event_rejects_an_out_of_bounds_set_index(client, firebase_test_user, postgres_url):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    exercise = _bench_press_exercise(postgres_url)  # 4 sets -> valid indexes 0..3

    response = client.request(
        "DELETE",
        "/train/sets",
        headers=headers,
        json={"exercise_id": exercise["id"], "set_index": exercise["sets"], "day_key": _TODAY.isoformat()},
    )
    assert response.status_code == 422


def test_delete_set_event_rejects_an_unknown_exercise_id(client, firebase_test_user):
    headers = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers)
    response = client.request(
        "DELETE",
        "/train/sets",
        headers=headers,
        json={"exercise_id": 999999, "set_index": 0, "day_key": _TODAY.isoformat()},
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Cross-owner IDOR (AC3)
# ---------------------------------------------------------------------------


def test_cross_owner_cannot_unmark_anothers_set_and_day_view_stays_empty(
    client, firebase_test_user, firebase_emulator, postgres_url
):
    """A marks a set; B (a distinct, bootstrapped principal) cannot unmark
    A's row (B's identical-looking DELETE only ever scopes to B's OWN,
    nonexistent row) and B's own day view never reflects A's set."""
    headers_a = _auth_header(firebase_test_user["id_token"])
    _bootstrap(client, headers_a)
    exercise = _bench_press_exercise(postgres_url)

    mark_response = client.post(
        "/train/sets",
        headers=headers_a,
        json={
            "exercise_id": exercise["id"],
            "set_index": 0,
            "day_key": _TODAY.isoformat(),
            "done_at": _now_iso(),
        },
    )
    assert mark_response.status_code == 200

    signup_b = requests.post(
        f"http://{firebase_emulator}/identitytoolkit.googleapis.com/v1/accounts:signUp",
        params={"key": "fake-api-key"},
        json={"email": "train-idor-b@example.com", "password": "Password123!", "returnSecureToken": True},
        timeout=5,
    )
    signup_b.raise_for_status()
    headers_b = _auth_header(signup_b.json()["idToken"])
    _bootstrap(client, headers_b)

    delete_as_b = client.request(
        "DELETE",
        "/train/sets",
        headers=headers_b,
        json={"exercise_id": exercise["id"], "set_index": 0, "day_key": _TODAY.isoformat()},
    )
    assert delete_as_b.status_code == 204  # idempotent no-op for B's own (absent) row

    day_b = client.get(f"/train?day_key={_TODAY.isoformat()}", headers=headers_b).json()
    assert day_b["score"] == 512
    assert all(exercise_out["done_set_indexes"] == [] for exercise_out in day_b["exercises"])

    count_for_a = asyncio.run(
        run_scalar_query(
            postgres_url,
            "SELECT count(*) FROM set_events WHERE owner_uid = :uid AND exercise_id = :exercise_id "
            "AND set_index = 0 AND day_key = :day_key",
            uid=firebase_test_user["uid"],
            exercise_id=exercise["id"],
            day_key=_TODAY,
        )
    )
    assert count_for_a == 1, "B's delete attempt must not have touched A's row"
