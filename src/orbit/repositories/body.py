"""Owner-scoped repository for the Body (muscle-level) aggregate — plan.md
§Data: "every query is owner-scoped and bounded in one place."
"""

from __future__ import annotations

import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import Exercise, MuscleBaseLevel, SetEvent


async def get_muscle_levels(session: AsyncSession, owner_uid: str) -> list[MuscleBaseLevel]:
    """The caller's own 13 muscle-base-level rows (empty if the account
    hasn't been bootstrapped yet — 404 at the route)."""
    result = await session.execute(
        select(MuscleBaseLevel).where(MuscleBaseLevel.owner_uid == owner_uid)
    )
    return list(result.scalars().all())


async def get_trained_muscle_groups_today(
    session: AsyncSession, owner_uid: str, day_key: datetime.date
) -> set[str]:
    """The distinct `muscle_tag`s trained on the requested day (plan §Derived
    formulas: "a muscle group glows iff a set_event exists today for an
    exercise whose `muscle_tag` maps to it") — a set_event -> exercise join,
    scoped to the caller's own rows and the one requested day."""
    result = await session.execute(
        select(Exercise.muscle_tag)
        .distinct()
        .join(SetEvent, SetEvent.exercise_id == Exercise.id)
        .where(SetEvent.owner_uid == owner_uid, SetEvent.day_key == day_key)
    )
    return set(result.scalars().all())
