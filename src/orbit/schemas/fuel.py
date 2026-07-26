"""Validation + response contracts for `/catalog/quick-foods` and `/fuel`
(plan §Backend, §Validation contracts): create a day-keyed food entry from
either a seeded quick-food or explicit macros (never both), and the
grouped-by-meal day read with totals + targets + the static coach message
(AC6, AC7).
"""

from __future__ import annotations

import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from ..models import MEAL_GROUPS
from .common import ClientTimestamp, DayKey, StrictModel

_MealGroupLiteral = Literal[MEAL_GROUPS]

# Adaptive TDEE coaching is deferred (plan §Backend: "server returns a static
# default string this run"; docs/roadmap.md: adaptive diet coach) — this is
# the ONE literal this run ships, never computed.
STATIC_COACH_MESSAGE = "Mission Control: log consistently this week to unlock personalized adjustments."


class QuickFoodOut(BaseModel):
    """One row of the seeded quick-food catalog (`GET /catalog/quick-foods`,
    AC6) — an explicit response allowlist, not a raw ORM-row serialize."""

    id: int
    name: str
    kcal: int
    protein_g: float
    carb_g: float
    fat_g: float

    @classmethod
    def from_domain(cls, quick_food) -> "QuickFoodOut":
        return cls(
            id=quick_food.id,
            name=quick_food.name,
            kcal=quick_food.kcal,
            protein_g=quick_food.protein_g,
            carb_g=quick_food.carb_g,
            fat_g=quick_food.fat_g,
        )


class FoodEntryCreate(StrictModel):
    """`POST /fuel/entries` request — create from EITHER a seeded quick-food
    (`quick_food_id`) OR explicit macros (`name` + `kcal` + the three macro
    grams), never both and never neither (plan §Backend: "from
    `quick_food_id` **or** explicit macros")."""

    meal_group: _MealGroupLiteral
    day_key: DayKey
    logged_at: ClientTimestamp
    quick_food_id: int | None = None
    name: str | None = Field(default=None, min_length=1, max_length=120)
    kcal: int | None = Field(default=None, ge=0, le=10000)
    protein_g: float | None = Field(default=None, ge=0, le=2000)
    carb_g: float | None = Field(default=None, ge=0, le=2000)
    fat_g: float | None = Field(default=None, ge=0, le=2000)

    @model_validator(mode="after")
    def _exactly_one_source(self) -> "FoodEntryCreate":
        """Enforce the quick-food-XOR-explicit-macros contract at the schema
        boundary (schema-first validation, `code-standards`) rather than
        leaving it to be discovered downstream."""
        explicit_fields = (self.name, self.kcal, self.protein_g, self.carb_g, self.fat_g)
        has_every_explicit_field = all(field is not None for field in explicit_fields)
        has_any_explicit_field = any(field is not None for field in explicit_fields)
        has_quick_food = self.quick_food_id is not None

        if has_quick_food and has_any_explicit_field:
            raise ValueError("provide quick_food_id OR explicit macros, not both")
        if not has_quick_food and not has_every_explicit_field:
            raise ValueError(
                "provide either quick_food_id, or all of name/kcal/protein_g/carb_g/fat_g"
            )
        return self


class FoodEntryOut(BaseModel):
    """One logged food entry — an explicit response allowlist (`owner_uid`
    never appears)."""

    id: int
    name: str
    kcal: int
    protein_g: float
    carb_g: float
    fat_g: float
    meal_group: str
    logged_at: datetime.datetime
    day_key: datetime.date

    @classmethod
    def from_domain(cls, entry) -> "FoodEntryOut":
        return cls(
            id=entry.id,
            name=entry.name,
            kcal=entry.kcal,
            protein_g=entry.protein_g,
            carb_g=entry.carb_g,
            fat_g=entry.fat_g,
            meal_group=entry.meal_group,
            logged_at=entry.logged_at,
            day_key=entry.day_key,
        )


class FuelDayQuery(StrictModel):
    """`GET /fuel`'s one required query param — `extra="forbid"` rejects any
    OTHER param 422 (plan's validation-contract shape for this endpoint)."""

    day_key: DayKey


class MacroTotalsOut(BaseModel):
    """Sum of a day's logged entries across all meals (AC7's "totals")."""

    kcal: int
    protein_g: float
    carb_g: float
    fat_g: float


class MacroTargetsOut(BaseModel):
    """The caller's own profile targets, echoed alongside the day's totals so
    the client can render progress without a second round trip."""

    kcal_budget: int
    protein_target_g: int
    carb_target_g: int
    fat_target_g: int


class FuelDayOut(BaseModel):
    """`GET /fuel?day_key=` response: entries grouped by meal + totals +
    targets + the static coach message (AC7)."""

    day_key: datetime.date
    meals: dict[str, list[FoodEntryOut]]
    totals: MacroTotalsOut
    targets: MacroTargetsOut
    remaining_kcal: int
    coach_message: str = STATIC_COACH_MESSAGE
