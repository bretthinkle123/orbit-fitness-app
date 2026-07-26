"""Owner-scoped repository for the weight-tracking aggregate — plan.md
§Data: "every query is owner-scoped and bounded in one place."
"""

from __future__ import annotations

import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import WeightEntry

# plan §Data / CLAUDE.md: "weights 30-day window" — the window itself is the
# declared bound; still paired with an explicit hard LIMIT (AC14: "day-/
# window-scoped AND hard LIMIT... no unbounded SELECT"), a generous safety
# cap since multiple weigh-ins/day are legitimate (no UNIQUE constraint on
# this table, unlike `set_events`).
_WINDOW_DAYS = 30
_MAX_ENTRIES_IN_WINDOW = 200


async def create_weight_entry(
    session: AsyncSession,
    owner_uid: str,
    weight_kg: float,
    day_key: datetime.date,
    logged_at: datetime.datetime,
) -> WeightEntry:
    """Create a weight entry (canonical kg); duplicates allowed (no UNIQUE
    constraint on this table — multiple weigh-ins per day are legitimate)."""
    entry = WeightEntry(owner_uid=owner_uid, weight_kg=weight_kg, day_key=day_key, logged_at=logged_at)
    session.add(entry)
    await session.flush()
    return entry


async def get_window_entries(
    session: AsyncSession, owner_uid: str, today: datetime.date
) -> list[WeightEntry]:
    """The caller's own entries in the fixed 30-day window ending today
    (AC12, AC14) — day-scoped + hard LIMIT, chronological (oldest first) so
    the response is ready for direct sparkline consumption with no client-
    side re-sort."""
    window_start = today - datetime.timedelta(days=_WINDOW_DAYS - 1)
    result = await session.execute(
        select(WeightEntry)
        .where(
            WeightEntry.owner_uid == owner_uid,
            WeightEntry.day_key >= window_start,
            WeightEntry.day_key <= today,
        )
        .order_by(WeightEntry.day_key, WeightEntry.logged_at)
        .limit(_MAX_ENTRIES_IN_WINDOW)
    )
    return list(result.scalars().all())
