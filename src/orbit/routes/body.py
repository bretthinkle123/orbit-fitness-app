"""`/body` route — the 13 muscle base levels + trained-today flags (AC11).
Depends on `require_auth`; `owner_uid` always comes from the verified token."""

from __future__ import annotations

import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import require_auth
from ..models import MUSCLE_GROUPS
from ..repositories.base import get_sessionmaker
from ..repositories.body import get_muscle_levels, get_trained_muscle_groups_today
from ..schemas.body import BodyDayOut, BodyDayQuery, MuscleLevelOut

router = APIRouter(prefix="/body", tags=["body"])

_NOT_BOOTSTRAPPED_DETAIL = "Profile not found — call POST /me/bootstrap first"


@router.get("")
async def read_body_day(
    query: Annotated[BodyDayQuery, Query()], user: dict = Depends(require_auth)
) -> BodyDayOut:
    """13 muscle levels + trained-today flags, for the caller's own day
    (AC11)."""
    owner_uid = user["uid"]
    day = datetime.date.fromisoformat(query.day_key)

    async with get_sessionmaker()() as session:
        muscle_levels = await get_muscle_levels(session, owner_uid)
        if not muscle_levels:
            raise HTTPException(status_code=404, detail=_NOT_BOOTSTRAPPED_DETAIL)
        trained_today = await get_trained_muscle_groups_today(session, owner_uid, day)

    levels_by_group = {level.muscle_group: level for level in muscle_levels}
    return BodyDayOut(
        day_key=day,
        muscle_levels=[
            MuscleLevelOut(
                muscle_group=muscle_group,
                level=levels_by_group[muscle_group].level,
                trained_today=muscle_group in trained_today,
            )
            # MUSCLE_GROUPS is the design's own row order (chest, shoulders,
            # traps, ...) — displayed in that order, not an arbitrary DB sort.
            for muscle_group in MUSCLE_GROUPS
        ],
    )
