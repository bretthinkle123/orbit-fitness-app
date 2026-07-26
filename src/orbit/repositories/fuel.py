"""Owner-scoped repository for the fuel (food-logging) aggregate — plan.md
§Data: "every query is owner-scoped and bounded in one place." The
quick-food catalog is the one exception (global, no owner) per plan §Data.
"""

from __future__ import annotations

import datetime
import hashlib

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import FoodEntry, QuickFood
from ..schemas.fuel import FoodEntryCreate

# plan.md §Data: "<= 200 rows / (uid, day_key), hard LIMIT on read" — enforced
# on BOTH the write (this module's `create_food_entry`) and the read (defense
# in depth, AC14: "no unbounded SELECT" even though the write-side cap makes
# a read ever seeing more than 200 rows for one day impossible in practice).
_MAX_ENTRIES_PER_DAY = 200


class QuickFoodNotFoundError(Exception):
    """Raised when `quick_food_id` doesn't reference a real catalog row (404
    at the route)."""


class DayEntryLimitExceededError(Exception):
    """Raised when a (owner_uid, day_key) is already at the <=200 bound
    (422 at the route)."""


async def list_quick_foods(session: AsyncSession) -> list[QuickFood]:
    """The seeded quick-food catalog (AC6) — global data, no owner scoping."""
    result = await session.execute(select(QuickFood).order_by(QuickFood.name))
    return list(result.scalars().all())


def _day_lock_key(owner_uid: str, day_key: datetime.date) -> int:
    """A deterministic 64-bit key for `pg_advisory_xact_lock`, scoping the
    <=200-per-day check to exactly one (owner_uid, day_key) at a time.

    A plain SELECT-count-then-INSERT would leave a genuine check-then-act
    race open under concurrent requests (ASVS 15.4 — the same class of bug
    the correctness checklist calls out: a stale count admitting more rows
    than the declared cap). The lock is scoped to the caller's own
    transaction and releases automatically at commit/rollback.
    """
    digest = hashlib.sha256(f"{owner_uid}:{day_key.isoformat()}".encode()).digest()
    return int.from_bytes(digest[:8], "big", signed=True)


async def _resolve_macros_from_quick_food(
    session: AsyncSession, quick_food_id: int
) -> tuple[str, int, float, float, float]:
    """Look up the seeded catalog row a creation request references, copying
    its macros at logging time (the persisted entry is a snapshot, not a live
    FK — plan §Data: `food_entries` carries no `quick_food_id` column)."""
    quick_food = await session.get(QuickFood, quick_food_id)
    if quick_food is None:
        raise QuickFoodNotFoundError(f"quick_food_id {quick_food_id} does not exist")
    return quick_food.name, quick_food.kcal, quick_food.protein_g, quick_food.carb_g, quick_food.fat_g


async def _reject_if_day_is_already_at_the_entry_cap(
    session: AsyncSession, owner_uid: str, day_key: datetime.date
) -> None:
    """Serialize concurrent creates for this exact (owner_uid, day_key) via
    an advisory lock, then count-and-reject — the lock closes the race the
    count alone would leave open (see `_day_lock_key`)."""
    await session.execute(text("SELECT pg_advisory_xact_lock(:lock_key)"), {"lock_key": _day_lock_key(owner_uid, day_key)})
    existing_count = await session.scalar(
        select(func.count())
        .select_from(FoodEntry)
        .where(FoodEntry.owner_uid == owner_uid, FoodEntry.day_key == day_key)
    )
    if existing_count >= _MAX_ENTRIES_PER_DAY:
        raise DayEntryLimitExceededError(f"owner {owner_uid} already has {existing_count} entries on {day_key}")


async def create_food_entry(session: AsyncSession, owner_uid: str, payload: FoodEntryCreate) -> FoodEntry:
    """Create a day-keyed food entry from either the seeded catalog or
    explicit macros (AC7); duplicates allowed; bounded to <=200/(uid,day_key)
    (AC7, AC14). Runs inside the caller's already-open transaction."""
    day_key = datetime.date.fromisoformat(payload.day_key)
    await _reject_if_day_is_already_at_the_entry_cap(session, owner_uid, day_key)

    if payload.quick_food_id is not None:
        name, kcal, protein_g, carb_g, fat_g = await _resolve_macros_from_quick_food(
            session, payload.quick_food_id
        )
    else:
        name, kcal, protein_g, carb_g, fat_g = (
            payload.name,
            payload.kcal,
            payload.protein_g,
            payload.carb_g,
            payload.fat_g,
        )

    entry = FoodEntry(
        owner_uid=owner_uid,
        name=name,
        kcal=kcal,
        protein_g=protein_g,
        carb_g=carb_g,
        fat_g=fat_g,
        meal_group=payload.meal_group,
        logged_at=payload.logged_at,
        day_key=day_key,
    )
    session.add(entry)
    await session.flush()
    return entry


async def get_fuel_day_entries(
    session: AsyncSession, owner_uid: str, day_key: datetime.date
) -> list[FoodEntry]:
    """The caller's own entries for one day, chronological, hard-bounded at
    the same 200-row cap the write side enforces (AC14 defense in depth —
    "no unbounded SELECT" holds even if the cap above were ever bypassed)."""
    result = await session.execute(
        select(FoodEntry)
        .where(FoodEntry.owner_uid == owner_uid, FoodEntry.day_key == day_key)
        .order_by(FoodEntry.logged_at)
        .limit(_MAX_ENTRIES_PER_DAY)
    )
    return list(result.scalars().all())
