"""Validation + response contracts for `/body` (plan §Backend, §Derived
formulas): the 13 seeded-then-copied muscle base levels + trained-today
flags derived from the day's set events (AC11).
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel

from .common import DayKey, StrictModel


class BodyDayQuery(StrictModel):
    """`GET /body`'s one required query param — `extra="forbid"` rejects
    any OTHER param 422."""

    day_key: DayKey


class MuscleLevelOut(BaseModel):
    """One muscle group's base level + whether it was trained on the
    requested day (plan §Derived formulas: "a muscle group glows iff a
    set_event exists today for an exercise whose `muscle_tag` maps to it")."""

    muscle_group: str
    level: int
    trained_today: bool


class BodyDayOut(BaseModel):
    """`GET /body?day_key=` response: all 13 muscle levels + trained-today
    flags (AC11)."""

    day_key: datetime.date
    muscle_levels: list[MuscleLevelOut]
