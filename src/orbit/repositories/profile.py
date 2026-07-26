"""Owner-scoped repository for the profile aggregate (the `profiles` row +
its 13-row `muscle_base_levels` set) — plan.md §Data: "every query is
owner-scoped and bounded in one place." Every function here takes the
caller's own `owner_uid` (always sourced from the verified token by the
route, never a request param) and there is no code path that accepts a
different principal's id — the row-level-ownership invariant is structural,
not an added filter.
"""

from __future__ import annotations

from typing import Sequence

from sqlalchemy import insert, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import MuscleBaseLevel, MuscleLevelTemplate, Profile


async def _fetch_muscle_levels(session: AsyncSession, owner_uid: str) -> list[MuscleBaseLevel]:
    """The caller's 13 muscle-base-level rows, ordered for a stable response."""
    result = await session.execute(
        select(MuscleBaseLevel)
        .where(MuscleBaseLevel.owner_uid == owner_uid)
        .order_by(MuscleBaseLevel.muscle_group)
    )
    return list(result.scalars().all())


async def get_profile(
    session: AsyncSession, owner_uid: str
) -> tuple[Profile, Sequence[MuscleBaseLevel]] | None:
    """Fetch the caller's own profile + muscle levels, or `None` if the
    account hasn't been bootstrapped yet (AC4/AC13)."""
    profile = await session.get(Profile, owner_uid)
    if profile is None:
        return None
    levels = await _fetch_muscle_levels(session, owner_uid)
    return profile, levels


async def bootstrap_profile(
    session: AsyncSession, owner_uid: str
) -> tuple[Profile, Sequence[MuscleBaseLevel], bool]:
    """Idempotent create-if-absent: a profile row (seeded with its column
    defaults) + 13 muscle-base-level rows copied from the global template
    table (AC4). Runs inside the caller's already-open transaction (the
    route wraps this in `async with session.begin()`) so the whole
    multi-insert is atomic (ASVS 2.3.3 / T2-5) — a failure partway through
    (the fault-injection test) rolls every insert this call made back,
    never a partial profile.

    The profile insert is a single `INSERT ... ON CONFLICT (owner_uid) DO
    NOTHING ... RETURNING` statement — atomic by construction, not a
    separate check-then-insert — so two concurrent bootstrap calls for the
    same uid can never both "win" the create race; only the call that
    actually inserts the profile row goes on to seed the muscle levels. A
    call that finds the profile already present (either a genuine replay, or
    the losing side of a race) returns the existing profile + levels
    untouched: no new rows, matching AC4's "new users start EMPTY" and
    idempotency requirements simultaneously.

    Returns `(profile, muscle_levels, created)`; `created` distinguishes the
    two paths for tests (unused by the route, which returns the same shape
    either way).
    """
    insert_profile = (
        pg_insert(Profile)
        .values(owner_uid=owner_uid)
        .on_conflict_do_nothing(index_elements=["owner_uid"])
        .returning(Profile.owner_uid)
    )
    inserted_row = (await session.execute(insert_profile)).first()

    if inserted_row is None:
        existing_profile = await session.get(Profile, owner_uid)
        existing_levels = await _fetch_muscle_levels(session, owner_uid)
        return existing_profile, existing_levels, False

    templates = (await session.execute(select(MuscleLevelTemplate))).scalars().all()
    for template in templates:
        # One INSERT per template row (not a single bulk statement) so a
        # fault-injection test can raise after the Nth call and prove the
        # WHOLE multi-insert — profile row included — rolls back together
        # (plan §Test strategy: "monkeypatched insert raising after the
        # N-th insert").
        await session.execute(
            insert(MuscleBaseLevel).values(
                owner_uid=owner_uid, muscle_group=template.muscle_group, level=template.level
            )
        )

    new_profile = await session.get(Profile, owner_uid)
    new_levels = await _fetch_muscle_levels(session, owner_uid)
    return new_profile, new_levels, True


async def update_profile(
    session: AsyncSession, owner_uid: str, changes: dict
) -> tuple[Profile, Sequence[MuscleBaseLevel]] | None:
    """Apply an ALLOWLISTED partial update to the caller's own profile row.

    `changes` is always the route's `ProfileUpdate.model_dump(exclude_unset=True)`
    — itself built from an explicit writable-field allowlist (ASVS 15.3.3) —
    never a raw request body spread onto the model. Returns `None` if the
    account hasn't been bootstrapped yet (404 at the route)."""
    profile = await session.get(Profile, owner_uid)
    if profile is None:
        return None
    for field_name, value in changes.items():
        setattr(profile, field_name, value)
    await session.flush()
    levels = await _fetch_muscle_levels(session, owner_uid)
    return profile, levels
