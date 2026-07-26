"""`/train` routes — the Push Day program, today's set state, score, and
week strip (AC10), plus the idempotent set-toggle endpoints. Every route
depends on `require_auth`; `owner_uid` always comes from the verified token,
never the request (mass-assignment defense, plan §Backend).
"""

from __future__ import annotations

import datetime
from typing import Annotated, Sequence

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import require_auth
from ..edge.ratelimit import require_resource_throttle
from ..models import SetEvent
from ..repositories.base import get_sessionmaker
from ..repositories.profile import get_profile
from ..repositories.train import (
    ExerciseNotFoundError,
    SetIndexOutOfBoundsError,
    get_day_set_events,
    get_program_with_exercises,
    get_week_set_events,
    mark_set_done,
    unmark_set,
)
from ..schemas.train import (
    ExerciseOut,
    ProgramOut,
    SetEventOut,
    SetIdentifier,
    SetToggleCreate,
    TrainDayOut,
    TrainDayQuery,
)

router = APIRouter(prefix="/train", tags=["train"])

_PROFILE_NOT_BOOTSTRAPPED_DETAIL = "Profile not found — call POST /me/bootstrap first"


def _week_bounds(day: datetime.date) -> tuple[datetime.date, datetime.date]:
    """The Monday..Sunday range containing `day` (ISO week — a documented
    default; plan names "this week" without pinning a start-of-week day)."""
    week_start = day - datetime.timedelta(days=day.weekday())
    week_end = week_start + datetime.timedelta(days=6)
    return week_start, week_end


def _build_train_day_response(
    day: datetime.date,
    program,
    exercises: Sequence,
    today_events: Sequence[SetEvent],
    week_events: Sequence[SetEvent],
    score_base: int,
) -> TrainDayOut:
    """Shape the program+exercises+score+week-strip response — pure
    post-processing over already-fetched rows, kept separate from the route
    so the route itself stays one level of abstraction (orchestration only).
    """
    done_indexes_by_exercise: dict[int, list[int]] = {exercise.id: [] for exercise in exercises}
    for event in today_events:
        done_indexes_by_exercise.setdefault(event.exercise_id, []).append(event.set_index)

    week_start, _week_end = _week_bounds(day)
    trained_day_keys = {event.day_key for event in week_events}
    week_strip = [(week_start + datetime.timedelta(days=offset)) in trained_day_keys for offset in range(7)]

    return TrainDayOut(
        day_key=day,
        program=ProgramOut(id=program.id, name=program.name, focus=program.focus, est_minutes=program.est_minutes),
        exercises=[
            ExerciseOut.from_domain(exercise, done_indexes_by_exercise[exercise.id]) for exercise in exercises
        ],
        # plan §Derived formulas: "score = profile.score_base(512) + count(today's set_events)".
        score=score_base + len(today_events),
        week_strip=week_strip,
        session_count=sum(week_strip),
        # plan §Derived formulas: "weekly delta = this-week done-set count (real, bounded)".
        weekly_delta=len(week_events),
    )


@router.get("")
async def read_train_day(
    query: Annotated[TrainDayQuery, Query()], user: dict = Depends(require_auth)
) -> TrainDayOut:
    """Program + exercises + today's set state + score + week strip (AC10),
    for the caller's own day (day-scoped + hard LIMIT, AC14)."""
    owner_uid = user["uid"]
    day = datetime.date.fromisoformat(query.day_key)
    week_start, week_end = _week_bounds(day)

    async with get_sessionmaker()() as session:
        profile_result = await get_profile(session, owner_uid)
        if profile_result is None:
            raise HTTPException(status_code=404, detail=_PROFILE_NOT_BOOTSTRAPPED_DETAIL)
        profile, _muscle_levels = profile_result

        program, exercises = await get_program_with_exercises(session)
        today_events = await get_day_set_events(session, owner_uid, day)
        week_events = await get_week_set_events(session, owner_uid, week_start, week_end)

    return _build_train_day_response(day, program, exercises, today_events, week_events, profile.score_base)


@router.post("/sets", status_code=200, dependencies=[Depends(require_resource_throttle)])
async def create_set_event(body: SetToggleCreate, user: dict = Depends(require_auth)) -> SetEventOut:
    """Mark a set done — idempotent on the UNIQUE key (AC10): a replay
    returns the SAME 200 with the existing row, never a second row nor a
    409/500."""
    day = datetime.date.fromisoformat(body.day_key)
    async with get_sessionmaker()() as session:
        async with session.begin():
            try:
                set_event, _created = await mark_set_done(
                    session, user["uid"], body.exercise_id, body.set_index, day, body.done_at
                )
            except ExerciseNotFoundError as error:
                raise HTTPException(status_code=404, detail="exercise_id does not exist") from error
            except SetIndexOutOfBoundsError as error:
                raise HTTPException(status_code=422, detail=str(error)) from error
    return SetEventOut.from_domain(set_event)


@router.delete("/sets", status_code=204, dependencies=[Depends(require_resource_throttle)])
async def delete_set_event(body: SetIdentifier, user: dict = Depends(require_auth)) -> None:
    """Unmark a set, scoped by (uid, exercise, set, day); idempotent — no
    error if the set wasn't marked done."""
    day = datetime.date.fromisoformat(body.day_key)
    async with get_sessionmaker()() as session:
        async with session.begin():
            try:
                await unmark_set(session, user["uid"], body.exercise_id, body.set_index, day)
            except ExerciseNotFoundError as error:
                raise HTTPException(status_code=404, detail="exercise_id does not exist") from error
            except SetIndexOutOfBoundsError as error:
                raise HTTPException(status_code=422, detail=str(error)) from error
