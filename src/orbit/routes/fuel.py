"""`/catalog/quick-foods` + `/fuel` routes — day-keyed food logging (AC6,
AC7, AC14). Every route depends on `require_auth`; `owner_uid` always comes
from the verified token, never the request (mass-assignment defense, plan
§Backend).
"""

from __future__ import annotations

import datetime
from typing import Annotated, Sequence

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import require_auth
from ..edge.ratelimit import require_resource_throttle
from ..models import FoodEntry, MEAL_GROUPS, Profile
from ..repositories.base import get_sessionmaker
from ..repositories.fuel import (
    DayEntryLimitExceededError,
    QuickFoodNotFoundError,
    create_food_entry,
    get_fuel_day_entries,
    list_quick_foods,
)
from ..repositories.profile import get_profile
from ..schemas.common import EmptyQuery
from ..schemas.fuel import (
    STATIC_COACH_MESSAGE,
    FoodEntryCreate,
    FoodEntryOut,
    FuelDayOut,
    FuelDayQuery,
    MacroTargetsOut,
    MacroTotalsOut,
    QuickFoodOut,
)

router = APIRouter(tags=["fuel"])

_PROFILE_NOT_BOOTSTRAPPED_DETAIL = "Profile not found — call POST /me/bootstrap first"


@router.get("/catalog/quick-foods")
async def read_quick_food_catalog(
    query: Annotated[EmptyQuery, Query()], user: dict = Depends(require_auth)
) -> list[QuickFoodOut]:
    """The seeded quick-food catalog + macros (AC6) — global, no owner
    scoping; `EmptyQuery`'s `extra="forbid"` rejects any query param 422."""
    async with get_sessionmaker()() as session:
        catalog = await list_quick_foods(session)
    return [QuickFoodOut.from_domain(quick_food) for quick_food in catalog]


@router.post("/fuel/entries", status_code=201, dependencies=[Depends(require_resource_throttle)])
async def create_fuel_entry(body: FoodEntryCreate, user: dict = Depends(require_auth)) -> FoodEntryOut:
    """Create a day-keyed food entry from EITHER a seeded quick-food or
    explicit macros (AC7); duplicates allowed; bounded to <=200/(uid,day)."""
    async with get_sessionmaker()() as session:
        async with session.begin():
            try:
                entry = await create_food_entry(session, user["uid"], body)
            except QuickFoodNotFoundError as error:
                raise HTTPException(status_code=404, detail="quick_food_id does not exist") from error
            except DayEntryLimitExceededError as error:
                raise HTTPException(
                    status_code=422, detail="This day already has the maximum of 200 logged entries"
                ) from error
    return FoodEntryOut.from_domain(entry)


@router.get("/fuel")
async def read_fuel_day(
    query: Annotated[FuelDayQuery, Query()], user: dict = Depends(require_auth)
) -> FuelDayOut:
    """Entries grouped by meal + totals + targets + the static coach message
    (AC7), for the caller's own day (day-scoped + hard LIMIT, AC14)."""
    owner_uid = user["uid"]
    day = datetime.date.fromisoformat(query.day_key)

    async with get_sessionmaker()() as session:
        profile_result = await get_profile(session, owner_uid)
        if profile_result is None:
            raise HTTPException(status_code=404, detail=_PROFILE_NOT_BOOTSTRAPPED_DETAIL)
        profile, _muscle_levels = profile_result
        entries = await get_fuel_day_entries(session, owner_uid, day)

    return _build_fuel_day_response(day, entries, profile)


def _build_fuel_day_response(day: datetime.date, entries: Sequence[FoodEntry], profile: Profile) -> FuelDayOut:
    """Shape the grouped-by-meal response — pure post-processing over
    already-fetched rows (no DB access), kept separate from the route so the
    route itself stays one level of abstraction (orchestration only)."""
    meals: dict[str, list[FoodEntryOut]] = {meal_group: [] for meal_group in MEAL_GROUPS}
    total_kcal = 0
    total_protein_g = total_carb_g = total_fat_g = 0.0
    for entry in entries:
        meals[entry.meal_group].append(FoodEntryOut.from_domain(entry))
        total_kcal += entry.kcal
        total_protein_g += entry.protein_g
        total_carb_g += entry.carb_g
        total_fat_g += entry.fat_g

    targets = MacroTargetsOut(
        kcal_budget=profile.kcal_budget,
        protein_target_g=profile.protein_target_g,
        carb_target_g=profile.carb_target_g,
        fat_target_g=profile.fat_target_g,
    )
    # plan §Backend: "remaining = budget - eaten + burned(default 0)".
    remaining_kcal = profile.kcal_budget - total_kcal + (profile.burned_kcal or 0)

    return FuelDayOut(
        day_key=day,
        meals=meals,
        totals=MacroTotalsOut(
            kcal=total_kcal, protein_g=total_protein_g, carb_g=total_carb_g, fat_g=total_fat_g
        ),
        targets=targets,
        remaining_kcal=remaining_kcal,
        coach_message=STATIC_COACH_MESSAGE,
    )
