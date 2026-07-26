"""Validation + response contracts for `/train` (plan §Backend, §Validation
contracts, §Derived formulas): the seeded "Push Day" program + today's set
events + score + week strip (AC10), and the idempotent set-toggle request
shape both `POST` and `DELETE /train/sets` share.
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel, Field

from .common import ClientTimestamp, DayKey, StrictModel


class ProgramOut(BaseModel):
    """The single seeded workout program (AC9) — an explicit response
    allowlist."""

    id: int
    name: str
    focus: str
    est_minutes: int


class ExerciseOut(BaseModel):
    """One seeded exercise, with the caller's own done-set state for the
    requested day folded in (`done_set_indexes`) so the client never needs a
    second join."""

    id: int
    name: str
    sets: int
    reps: int
    weight: float
    muscle_tag: str
    done_set_indexes: list[int]

    @classmethod
    def from_domain(cls, exercise, done_set_indexes: list[int]) -> "ExerciseOut":
        return cls(
            id=exercise.id,
            name=exercise.name,
            sets=exercise.sets,
            reps=exercise.reps,
            weight=exercise.weight,
            muscle_tag=exercise.muscle_tag,
            done_set_indexes=sorted(done_set_indexes),
        )


class TrainDayQuery(StrictModel):
    """`GET /train`'s one required query param — `extra="forbid"` rejects
    any OTHER param 422."""

    day_key: DayKey


class TrainDayOut(BaseModel):
    """`GET /train?day_key=` response: program + exercises (with today's set
    state) + score + week strip (AC10).

    `day_key` is the client's own notion of "today" (plan §Data: day_key is
    the user's device-tz local date) — score, the set state, and "this
    week" are all computed relative to THIS day_key, not the server's own
    system clock date, consistent with the rest of the day-keyed domain
    model (a documented judgment call: the plan names "today's set events"
    without a second, server-clock-relative "today").
    """

    day_key: datetime.date
    program: ProgramOut
    exercises: list[ExerciseOut]
    score: int
    week_strip: list[bool] = Field(min_length=7, max_length=7)
    session_count: int
    weekly_delta: int


class SetIdentifier(StrictModel):
    """The four fields that identify one set — shared by `POST` and `DELETE
    /train/sets` (plan §Validation contracts: `exercise_id`/`set_index`/
    `day_key`)."""

    exercise_id: int
    set_index: int = Field(ge=0)  # the exercise-specific upper bound is checked dynamically, not here
    day_key: DayKey


class SetToggleCreate(SetIdentifier):
    """`POST /train/sets` request — identifies the set plus when it was
    done (backdating allowed, future rejected — AC15)."""

    done_at: ClientTimestamp


class SetEventOut(BaseModel):
    """A single set-event row — an explicit response allowlist (`owner_uid`
    never appears)."""

    exercise_id: int
    set_index: int
    day_key: datetime.date
    done_at: datetime.datetime

    @classmethod
    def from_domain(cls, set_event) -> "SetEventOut":
        return cls(
            exercise_id=set_event.exercise_id,
            set_index=set_event.set_index,
            day_key=set_event.day_key,
            done_at=set_event.done_at,
        )
