"""Owner-scoped repository for the Push Day training aggregate — plan.md
§Data: "every query is owner-scoped and bounded in one place." The program
and its exercises are global seed data (no owner); `set_events` are per-user.
"""

from __future__ import annotations

import datetime

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import Exercise, Program, SetEvent

# plan.md §Data / AC14: every collection query bounded, day-scoped + hard
# LIMIT — Push Day's own cardinality (16 sets total) never approaches this,
# but the bound is a structural invariant, not a business rule tuned to
# today's seed data (a future program with more sets/exercises stays safe).
_MAX_SET_EVENTS_PER_DAY = 200


class ExerciseNotFoundError(Exception):
    """Raised when `exercise_id` doesn't reference a real seeded exercise
    (404 at the route)."""


class SetIndexOutOfBoundsError(Exception):
    """Raised when `set_index` is outside `[0, exercise.sets)` for the
    referenced exercise (422 at the route)."""


async def get_program_with_exercises(session: AsyncSession) -> tuple[Program, list[Exercise]]:
    """The single seeded "Push Day" program + its exercises, in display
    order — global data, no owner scoping."""
    program = (await session.execute(select(Program).limit(1))).scalars().first()
    exercises = list(
        (
            await session.execute(
                select(Exercise).where(Exercise.program_id == program.id).order_by(Exercise.order_index)
            )
        )
        .scalars()
        .all()
    )
    return program, exercises


async def get_day_set_events(
    session: AsyncSession, owner_uid: str, day_key: datetime.date
) -> list[SetEvent]:
    """The caller's own set events for one day (AC14: day-scoped + hard
    LIMIT)."""
    result = await session.execute(
        select(SetEvent)
        .where(SetEvent.owner_uid == owner_uid, SetEvent.day_key == day_key)
        .order_by(SetEvent.exercise_id, SetEvent.set_index)
        .limit(_MAX_SET_EVENTS_PER_DAY)
    )
    return list(result.scalars().all())


async def get_week_set_events(
    session: AsyncSession, owner_uid: str, week_start: datetime.date, week_end: datetime.date
) -> list[SetEvent]:
    """All the caller's set events within one ISO week (Mon..Sun, inclusive)
    — small by construction (one seeded program), used to derive both the
    week strip and the weekly delta from a single round trip."""
    result = await session.execute(
        select(SetEvent).where(
            SetEvent.owner_uid == owner_uid,
            SetEvent.day_key >= week_start,
            SetEvent.day_key <= week_end,
        )
    )
    return list(result.scalars().all())


async def _get_exercise_or_raise(session: AsyncSession, exercise_id: int) -> Exercise:
    """Fetch a seeded exercise by id, or raise `ExerciseNotFoundError`."""
    exercise = await session.get(Exercise, exercise_id)
    if exercise is None:
        raise ExerciseNotFoundError(f"exercise_id {exercise_id} does not exist")
    return exercise


def _validate_set_index_in_bounds(set_index: int, exercise: Exercise) -> None:
    """`0 <= set_index < exercise.sets` (plan §Validation contracts) — this
    bound is per-exercise data, so it can't be a static Pydantic `Field`
    constraint; it's checked here once the exercise row is in hand."""
    if not (0 <= set_index < exercise.sets):
        raise SetIndexOutOfBoundsError(
            f"set_index {set_index} is out of bounds for exercise {exercise.id} ({exercise.sets} sets)"
        )


async def mark_set_done(
    session: AsyncSession,
    owner_uid: str,
    exercise_id: int,
    set_index: int,
    day_key: datetime.date,
    done_at: datetime.datetime,
) -> tuple[SetEvent, bool]:
    """Mark one set done — idempotent on `UNIQUE(owner_uid, exercise_id,
    set_index, day_key)` (AC10): a replay returns the EXISTING row, never a
    second insert. The `INSERT ... ON CONFLICT DO NOTHING ... RETURNING`
    statement is atomic by construction (mirrors T4's profile-bootstrap
    upsert) — two concurrent identical requests can never both "win"; the
    loser simply re-reads the row the winner created (ASVS 15.4 — no
    separate check-then-insert window to race on).

    Returns `(set_event, created)`.
    """
    exercise = await _get_exercise_or_raise(session, exercise_id)
    _validate_set_index_in_bounds(set_index, exercise)

    insert_statement = (
        pg_insert(SetEvent)
        .values(
            owner_uid=owner_uid,
            exercise_id=exercise_id,
            set_index=set_index,
            day_key=day_key,
            done_at=done_at,
        )
        .on_conflict_do_nothing(index_elements=["owner_uid", "exercise_id", "set_index", "day_key"])
        .returning(SetEvent.id)
    )
    inserted_row = (await session.execute(insert_statement)).first()

    if inserted_row is None:
        existing = (
            await session.execute(
                select(SetEvent).where(
                    SetEvent.owner_uid == owner_uid,
                    SetEvent.exercise_id == exercise_id,
                    SetEvent.set_index == set_index,
                    SetEvent.day_key == day_key,
                )
            )
        ).scalars().one()
        return existing, False

    created = (
        await session.execute(select(SetEvent).where(SetEvent.id == inserted_row.id))
    ).scalars().one()
    return created, True


async def unmark_set(
    session: AsyncSession, owner_uid: str, exercise_id: int, set_index: int, day_key: datetime.date
) -> None:
    """Unmark a set (`DELETE /train/sets`) — idempotent (deleting an absent
    row is a no-op); still validates `exercise_id`/`set_index` for a
    coherent 404/422 on a malformed identifier, matching `mark_set_done`."""
    exercise = await _get_exercise_or_raise(session, exercise_id)
    _validate_set_index_in_bounds(set_index, exercise)

    await session.execute(
        delete(SetEvent).where(
            SetEvent.owner_uid == owner_uid,
            SetEvent.exercise_id == exercise_id,
            SetEvent.set_index == set_index,
            SetEvent.day_key == day_key,
        )
    )
