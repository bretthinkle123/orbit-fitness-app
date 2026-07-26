"""Account-erasure facade (`data-lifecycle-conventions` + plan.md §Data
lifecycle) — the ONE place that knows every per-user table the hard-delete
cascade must clear on account deletion. `routes/me.py`'s `DELETE /me` is the
only caller; a future domain table joins the cascade by adding one line
here, never by scattering an ad-hoc delete into a route or repository.

`muscle_level_templates` is a GLOBAL reference table (no `owner_uid` column
at all — it seeds every new account's `muscle_base_levels` rows, T4) and is
deliberately excluded from this cascade: it is not per-user data, so there is
nothing of the caller's to erase from it.
"""

from __future__ import annotations

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import FoodEntry, MuscleBaseLevel, Profile, SetEvent, WeightEntry

# Deletion order matches plan.md §Data-lifecycle's stated cascade list
# verbatim. No foreign key enforces this order (`owner_uid` is a plain string
# column, not an FK, on every one of these tables) — the order is preserved
# only so the atomic-rollback fault-injection test's "raises after the N-th
# of the five table deletes" language maps unambiguously onto this list.
_CASCADE_MODELS = (FoodEntry, SetEvent, WeightEntry, MuscleBaseLevel, Profile)


async def erase_account_rows(session: AsyncSession, owner_uid: str) -> dict[str, int]:
    """Hard-delete every per-user row for `owner_uid` across all five
    per-account domain tables, inside the caller's already-open transaction
    (`routes/me.py` wraps this in `async with session.begin()`) so the whole
    cascade is atomic — a failure partway through (the fault-injection test)
    rolls every delete this call already made back too, never a
    partially-erased account (ASVS 2.3.3 / T2-5).

    Idempotent by construction: deleting rows that no longer exist (a retry
    after a prior call already cleared them — the post-commit Firebase-
    failure retry path in `routes/me.py`) matches zero rows and is a harmless
    no-op, never an error.

    Returns the per-table deleted-row counts, used only as diagnostic detail
    for the caller's audit event — never a row's actual values.
    """
    deleted_counts: dict[str, int] = {}
    for model in _CASCADE_MODELS:
        result = await session.execute(delete(model).where(model.owner_uid == owner_uid))
        deleted_counts[model.__tablename__] = result.rowcount
    return deleted_counts
