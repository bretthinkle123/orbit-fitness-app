"""Validation + response contracts for `/profile` (plan §Backend, §Validation
contracts) and the derived macro-split-percentage math `GET /profile` and
`POST /me/bootstrap` both serialize (AC8).

`ProfileUpdate` is the ALLOWLIST for `PATCH /profile` (ASVS 15.3.3 — mass
assignment defense): only the fields named in plan.md's API table
(`palette_preset`, `units`, `gender`, `planet_index`, `kcal_budget`, and the
three macro target grams) are writable; every other field on the `profiles`
row (including `owner_uid`) is unreachable from this schema, so there is no
way for a request body to touch it. `ProfileOut` is the response ALLOWLIST
(ASVS 15.3.1 — minimal response fields): it is built field-by-field from the
ORM row via `from_domain`, never `model_validate(profile)` on the whole row,
so `owner_uid` (and any future internal-only column) can never leak.
"""

from __future__ import annotations

from typing import Literal, Sequence

from pydantic import BaseModel, Field

from ..models import GENDERS, PALETTE_PRESETS, UNIT_SYSTEMS, MuscleBaseLevel, Profile
from .common import StrictModel

# Built from the same tuples `models.py`'s DB-level enum CHECKs use (T2's
# design note: "reusable by T4+'s Pydantic schemas") — one source of truth
# for the allowed values, never a second hand-copied list to drift out of sync.
_PaletteLiteral = Literal[PALETTE_PRESETS]
_UnitsLiteral = Literal[UNIT_SYSTEMS]
_GenderLiteral = Literal[GENDERS]

# 4 kcal/g for protein and carbs, 9 kcal/g for fat — the standard Atwater
# factors the design-spec's derived-% math is defined against (plan §Data:
# "gram targets are canonical ... the split row displays the derived %").
_PROTEIN_KCAL_PER_GRAM = 4
_CARB_KCAL_PER_GRAM = 4
_FAT_KCAL_PER_GRAM = 9


def compute_macro_split_percentages(
    kcal_budget: int, protein_g: int, carb_g: int, fat_g: int
) -> tuple[int, int, int]:
    """Derive the display-only protein/carb/fat percentage split from the
    canonical gram targets (plan §Data: percentages are DERIVED, never
    stored — the design's stale "40/35/25" copy is a prototype defect).

    2,350 kcal budget · P185/C240/F72 g -> (31, 41, 28), matching the plan's
    worked example almost exactly (rounding each independently, so the three
    percentages need not sum to precisely 100).
    """
    if kcal_budget <= 0:
        return (0, 0, 0)
    protein_pct = round(protein_g * _PROTEIN_KCAL_PER_GRAM / kcal_budget * 100)
    carb_pct = round(carb_g * _CARB_KCAL_PER_GRAM / kcal_budget * 100)
    fat_pct = round(fat_g * _FAT_KCAL_PER_GRAM / kcal_budget * 100)
    return protein_pct, carb_pct, fat_pct


class MuscleLevelOut(BaseModel):
    """One muscle group's base level (1-6) — part of `GET /profile`'s
    response (plan §Backend: "settings + targets + score_base + muscle base
    levels")."""

    muscle_group: str
    level: int


class ProfileOut(BaseModel):
    """`GET /profile` / `POST /me/bootstrap` / `PATCH /profile` response
    shape — an explicit field allowlist (ASVS 15.3.1), never a raw ORM-row
    serialize."""

    kcal_budget: int
    protein_target_g: int
    carb_target_g: int
    fat_target_g: int
    protein_pct: int
    carb_pct: int
    fat_pct: int
    score_base: int
    tier_label: str
    percentile_label: str
    next_tier_pct: int
    palette_preset: str
    units: str
    gender: str
    planet_index: int
    burned_kcal: int
    muscle_levels: list[MuscleLevelOut]

    @classmethod
    def from_domain(cls, profile: Profile, muscle_levels: Sequence[MuscleBaseLevel]) -> "ProfileOut":
        """Build the response from the ORM row + muscle-level rows,
        computing the derived macro-split percentages (AC8) rather than
        trusting any stored/stale value."""
        protein_pct, carb_pct, fat_pct = compute_macro_split_percentages(
            profile.kcal_budget, profile.protein_target_g, profile.carb_target_g, profile.fat_target_g
        )
        return cls(
            kcal_budget=profile.kcal_budget,
            protein_target_g=profile.protein_target_g,
            carb_target_g=profile.carb_target_g,
            fat_target_g=profile.fat_target_g,
            protein_pct=protein_pct,
            carb_pct=carb_pct,
            fat_pct=fat_pct,
            score_base=profile.score_base,
            tier_label=profile.tier_label,
            percentile_label=profile.percentile_label,
            next_tier_pct=profile.next_tier_pct,
            palette_preset=profile.palette_preset,
            units=profile.units,
            gender=profile.gender,
            planet_index=profile.planet_index,
            # No burn-rate source exists yet (plan §Backend: "burned_kcal
            # optional -> 0 display") — never surface a bare NULL to the client.
            burned_kcal=profile.burned_kcal or 0,
            muscle_levels=[
                MuscleLevelOut(muscle_group=level.muscle_group, level=level.level) for level in muscle_levels
            ],
        )


class ProfileUpdate(StrictModel):
    """`PATCH /profile` request — the writable-field ALLOWLIST (plan §Backend
    API table). Every field is optional (partial update, `exclude_unset` at
    the route); `StrictModel`'s `extra="forbid"` rejects any other field —
    including `owner_uid` — with a 422 rather than silently ignoring it, so a
    mass-assignment attempt is loud, not just inert."""

    palette_preset: _PaletteLiteral | None = None
    units: _UnitsLiteral | None = None
    gender: _GenderLiteral | None = None
    planet_index: int | None = Field(default=None, ge=0, le=5)
    kcal_budget: int | None = Field(default=None, ge=500, le=10000)
    protein_target_g: int | None = Field(default=None, ge=0, le=1000)
    carb_target_g: int | None = Field(default=None, ge=0, le=1000)
    fat_target_g: int | None = Field(default=None, ge=0, le=1000)
