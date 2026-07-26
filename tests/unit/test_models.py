"""Unit tests for `orbit.models` — the ORM schema itself, exercised directly
(the migration integration tests only exercise it indirectly, via a
subprocess `alembic` invocation that pytest-cov cannot instrument)."""

from orbit.models import (
    MEAL_GROUPS,
    MUSCLE_GROUPS,
    Base,
    Exercise,
    FoodEntry,
    MuscleBaseLevel,
    MuscleLevelTemplate,
    Profile,
    Program,
    QuickFood,
    SetEvent,
    WeightEntry,
)


def test_every_planned_table_is_registered_on_the_shared_metadata():
    """§Data's schema table names 9 tables (8 + the muscle-level-template
    reference table T2 adds) — all must share one `Base.metadata`."""
    assert set(Base.metadata.tables.keys()) == {
        "profiles",
        "muscle_base_levels",
        "muscle_level_templates",
        "quick_foods",
        "food_entries",
        "programs",
        "exercises",
        "set_events",
        "weight_entries",
    }


def test_muscle_groups_constant_has_exactly_thirteen_entries():
    """The Body screen renders 13 muscle groups (design_handoff figure-paths.md)."""
    assert len(MUSCLE_GROUPS) == 13
    assert len(set(MUSCLE_GROUPS)) == 13, "no duplicate muscle group names"


def test_meal_groups_constant_matches_the_four_design_meal_sections():
    assert set(MEAL_GROUPS) == {"breakfast", "lunch", "snacks", "dinner"}


def test_profile_model_declares_the_canonical_macro_target_defaults():
    """Plan §Data's "canonical macro decision": gram targets 2,350 kcal ·
    P185/C240/F72 — expressed as column defaults (applied by SQLAlchemy at
    flush time, so asserted via the column's declared default, not by reading
    an unflushed instance's attributes) rather than a hardcoded route value."""
    columns = Profile.__table__.columns
    assert columns["kcal_budget"].default.arg == 2350
    assert columns["protein_target_g"].default.arg == 185
    assert columns["carb_target_g"].default.arg == 240
    assert columns["fat_target_g"].default.arg == 72
    assert columns["score_base"].default.arg == 512


def test_owner_scoped_tables_all_carry_an_owner_uid_column():
    """Row-level ownership (CLAUDE.md): every per-user table's ORM model
    exposes `owner_uid`."""
    for model in (Profile, MuscleBaseLevel, FoodEntry, SetEvent, WeightEntry):
        assert "owner_uid" in model.__table__.columns

    # Global (no-owner) seed tables must NOT carry an owner_uid.
    for model in (QuickFood, Program, Exercise, MuscleLevelTemplate):
        assert "owner_uid" not in model.__table__.columns
