"""`/profile` routes — settings/targets/muscle-levels read + allowlisted
partial update (AC4, AC8, AC13). Every route depends on `require_auth`;
`owner_uid` always comes from the verified token, never the request (mass-
assignment defense, plan §Backend).
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import require_auth
from ..edge.ratelimit import require_resource_throttle
from ..repositories.base import get_sessionmaker
from ..repositories.profile import get_profile, update_profile
from ..schemas.common import EmptyQuery
from ..schemas.profile import ProfileOut, ProfileUpdate

router = APIRouter(prefix="/profile", tags=["profile"])

_NOT_BOOTSTRAPPED_DETAIL = "Profile not found — call POST /me/bootstrap first"


@router.get("")
async def read_profile(
    query: Annotated[EmptyQuery, Query()], user: dict = Depends(require_auth)
) -> ProfileOut:
    """Return the caller's own settings + targets + score_base + muscle base
    levels (AC4, AC13). `EmptyQuery`'s `extra="forbid"` rejects any
    undeclared query param 422 (plan's NO-PARAMS validation contract) rather
    than silently ignoring it. 404 if the account hasn't been bootstrapped
    yet — there is no default-profile fallback that could leak a shared
    template row to an unbootstrapped caller."""
    async with get_sessionmaker()() as session:
        result = await get_profile(session, user["uid"])
    if result is None:
        raise HTTPException(status_code=404, detail=_NOT_BOOTSTRAPPED_DETAIL)
    profile, muscle_levels = result
    return ProfileOut.from_domain(profile, muscle_levels)


@router.patch("", dependencies=[Depends(require_resource_throttle)])
async def patch_profile(body: ProfileUpdate, user: dict = Depends(require_auth)) -> ProfileOut:
    """Persist an ALLOWLISTED partial update (AC13); `ProfileUpdate`'s
    `extra="forbid"` already rejected any unknown/mass-assignment field with
    a 422 before this handler runs — `owner_uid` is never a field on that
    schema at all, so there is no path for a body to target another
    account's row."""
    changes = body.model_dump(exclude_unset=True)
    async with get_sessionmaker()() as session:
        async with session.begin():
            result = await update_profile(session, user["uid"], changes)
            if result is None:
                raise HTTPException(status_code=404, detail=_NOT_BOOTSTRAPPED_DETAIL)
            profile, muscle_levels = result
    return ProfileOut.from_domain(profile, muscle_levels)
