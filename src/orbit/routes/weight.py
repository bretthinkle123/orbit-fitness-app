"""`/weight` routes — canonical-kg weight logging + the fixed 30-day window
read (AC12). Every route depends on `require_auth`; `owner_uid` always comes
from the verified token, never the request (mass-assignment defense).
"""

from __future__ import annotations

import datetime
from typing import Annotated, Sequence

from fastapi import APIRouter, Depends, Query

from ..auth import require_auth
from ..edge.ratelimit import require_resource_throttle
from ..models import WeightEntry
from ..repositories.base import get_sessionmaker
from ..repositories.weight import create_weight_entry, get_window_entries
from ..schemas.common import EmptyQuery
from ..schemas.weight import WeightEntryCreate, WeightEntryOut, WeightWindowOut

router = APIRouter(prefix="/weight", tags=["weight"])

# The weekly-delta baseline: the most recent entry at or before this many
# days prior to the latest entry (plan §Backend: "30-day window entries +
# latest + weekly delta" — a documented judgment call, since the plan
# doesn't pin the exact baseline-selection rule for irregular weigh-ins).
_WEEKLY_DELTA_LOOKBACK_DAYS = 7


@router.post("", status_code=201, dependencies=[Depends(require_resource_throttle)])
async def create_weight(body: WeightEntryCreate, user: dict = Depends(require_auth)) -> WeightEntryOut:
    """Create a weight entry, canonical kg (AC12); a future-dated
    `logged_at` is already rejected 422 by `ClientTimestamp` before this
    handler ever runs."""
    day = datetime.date.fromisoformat(body.day_key)
    async with get_sessionmaker()() as session:
        async with session.begin():
            entry = await create_weight_entry(session, user["uid"], body.weight_kg, day, body.logged_at)
    return WeightEntryOut.from_domain(entry)


@router.get("")
async def read_weight_window(
    query: Annotated[EmptyQuery, Query()], user: dict = Depends(require_auth)
) -> WeightWindowOut:
    """Fixed 30-day window + latest + weekly delta (AC12). NO PARAMS —
    `EmptyQuery`'s `extra="forbid"` rejects even `?day_key=` 422 (the F4-01
    escape shape the audit flagged: this window is server-computed from the
    server's own clock, never client-selectable)."""
    today = datetime.date.today()
    async with get_sessionmaker()() as session:
        entries = await get_window_entries(session, user["uid"], today)

    return _build_weight_window_response(entries)


def _build_weight_window_response(entries: Sequence[WeightEntry]) -> WeightWindowOut:
    """Shape the window + latest + weekly-delta response — pure
    post-processing over already-fetched rows, kept separate from the route
    so the route itself stays one level of abstraction (orchestration only).
    """
    if not entries:
        return WeightWindowOut(entries=[], latest=None, weekly_delta_kg=None)

    latest = entries[-1]  # chronological ascending -> the last row is the most recent
    baseline = _find_weekly_baseline(entries, latest)
    weekly_delta_kg = round(latest.weight_kg - baseline.weight_kg, 1) if baseline else None

    return WeightWindowOut(
        entries=[WeightEntryOut.from_domain(entry) for entry in entries],
        latest=WeightEntryOut.from_domain(latest),
        weekly_delta_kg=weekly_delta_kg,
    )


def _find_weekly_baseline(
    entries_chronological: Sequence[WeightEntry], latest: WeightEntry
) -> WeightEntry | None:
    """The most recent entry at or before `_WEEKLY_DELTA_LOOKBACK_DAYS`
    prior to `latest` — `None` if the window doesn't yet span a week of
    history (an honest "not enough data" rather than a fabricated zero)."""
    cutoff = latest.day_key - datetime.timedelta(days=_WEEKLY_DELTA_LOOKBACK_DAYS)
    candidates = [entry for entry in entries_chronological if entry.day_key <= cutoff]
    return candidates[-1] if candidates else None
