"""SQLAlchemy 2.0 ORM models — the schema for every table in plan.md §Data.

Every per-user table carries `owner_uid` (the Firebase UID) as its ownership
key (CLAUDE.md row-level ownership); no local PII beyond that opaque key
lives here. Every bound/enum constraint named in the plan's "Constraints"
paragraph is expressed as a real DB `CHECK`, not just app-level validation —
so a violation maps to a 4xx at the DB boundary, never a 500.
"""

import datetime

from sqlalchemy import CheckConstraint, Date, DateTime, Float, ForeignKey, Index, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# The 13 muscle groups the Body screen renders (design_handoff figure-paths.md /
# the prototype's `_D.muscles` array) — shared by `muscle_base_levels.muscle_group`
# and `exercises.muscle_tag` so the Body-derivation join (T6) compares like values.
MUSCLE_GROUPS = (
    "chest",
    "shoulders",
    "traps",
    "biceps",
    "forearms",
    "core",
    "quads",
    "calves",
    "lats",
    "triceps",
    "lower_back",
    "glutes",
    "hamstrings",
)

MEAL_GROUPS = ("breakfast", "lunch", "snacks", "dinner")
PALETTE_PRESETS = ("purple", "blue", "red", "green")
UNIT_SYSTEMS = ("metric", "imperial")
GENDERS = ("m", "w")


def _enum_check(column_name: str, allowed_values: tuple[str, ...]) -> CheckConstraint:
    """Build a `CHECK (column IN (...))` constraint — the DB-level enum guard
    named in plan.md's "Constraints" paragraph."""
    quoted = ", ".join(f"'{value}'" for value in allowed_values)
    return CheckConstraint(f"{column_name} IN ({quoted})", name=f"ck_{column_name}_enum")


class Base(DeclarativeBase):
    """Shared declarative base for every ORM model in the app."""


class Profile(Base):
    """One row per user: settings, targets, and the (display-only, deferred-
    computation) score/tier fields. Seeded with defaults by `POST
    /me/bootstrap` (T4), copying the template row `POST /me/bootstrap`
    resolves from the seed migration."""

    __tablename__ = "profiles"

    owner_uid: Mapped[str] = mapped_column(String(128), primary_key=True)
    kcal_budget: Mapped[int] = mapped_column(Integer, nullable=False, default=2350)
    protein_target_g: Mapped[int] = mapped_column(Integer, nullable=False, default=185)
    carb_target_g: Mapped[int] = mapped_column(Integer, nullable=False, default=240)
    fat_target_g: Mapped[int] = mapped_column(Integer, nullable=False, default=72)
    # 512 is the base strength score every user starts from (plan §Backend:
    # "score = profile.score_base(512) + count(today's set_events)").
    score_base: Mapped[int] = mapped_column(Integer, nullable=False, default=512)
    # Display-only defaults for a brand-new (zero-history) account — tier/
    # percentile computation is deferred (design-audit §3), so these are NOT
    # copied from the design's mid-progression demo copy ("Intermediate II" /
    # "Top 22% @ 183 lb"), which would misrepresent an account with no sets logged.
    tier_label: Mapped[str] = mapped_column(String(64), nullable=False, default="Beginner")
    percentile_label: Mapped[str] = mapped_column(String(64), nullable=False, default="Top 100%")
    next_tier_pct: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    palette_preset: Mapped[str] = mapped_column(String(16), nullable=False, default="purple")
    units: Mapped[str] = mapped_column(String(16), nullable=False, default="imperial")
    gender: Mapped[str] = mapped_column(String(4), nullable=False, default="m")
    planet_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Nullable: no burned-kcal source exists yet (wearables integration is a
    # named future run); the API displays 0 when NULL.
    burned_kcal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    burn_rate: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint("kcal_budget BETWEEN 500 AND 10000", name="ck_profiles_kcal_budget_range"),
        CheckConstraint("protein_target_g BETWEEN 0 AND 1000", name="ck_profiles_protein_target_g_range"),
        CheckConstraint("carb_target_g BETWEEN 0 AND 1000", name="ck_profiles_carb_target_g_range"),
        CheckConstraint("fat_target_g BETWEEN 0 AND 1000", name="ck_profiles_fat_target_g_range"),
        CheckConstraint("next_tier_pct BETWEEN 0 AND 100", name="ck_profiles_next_tier_pct_range"),
        CheckConstraint("planet_index BETWEEN 0 AND 5", name="ck_profiles_planet_index_range"),
        _enum_check("palette_preset", PALETTE_PRESETS),
        _enum_check("units", UNIT_SYSTEMS),
        _enum_check("gender", GENDERS),
    )


class MuscleBaseLevel(Base):
    """The 13-row-per-user muscle-level table the Body screen reads; seeded
    from the template row-set (T2 seed migration) and copied per-user at
    bootstrap (T4)."""

    __tablename__ = "muscle_base_levels"

    owner_uid: Mapped[str] = mapped_column(String(128), primary_key=True)
    muscle_group: Mapped[str] = mapped_column(String(32), primary_key=True)
    level: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (
        CheckConstraint("level BETWEEN 1 AND 6", name="ck_muscle_base_levels_level_range"),
        _enum_check("muscle_group", MUSCLE_GROUPS),
    )


class MuscleLevelTemplate(Base):
    """Global (no owner) reference row-set: the 13 design-default muscle
    levels the seed migration populates and `POST /me/bootstrap` (T4) copies
    into a new user's own `muscle_base_levels` rows. Kept as its own table —
    rather than a sentinel `owner_uid` inside `muscle_base_levels` — so a
    per-user, owner-scoped table never contains a row that doesn't belong to
    a real Firebase principal (row-level-ownership invariant, CLAUDE.md)."""

    __tablename__ = "muscle_level_templates"

    muscle_group: Mapped[str] = mapped_column(String(32), primary_key=True)
    level: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (
        CheckConstraint("level BETWEEN 1 AND 6", name="ck_muscle_level_templates_level_range"),
        _enum_check("muscle_group", MUSCLE_GROUPS),
    )


class QuickFood(Base):
    """The global (no owner) seeded quick-add food catalog."""

    __tablename__ = "quick_foods"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    kcal: Mapped[int] = mapped_column(Integer, nullable=False)
    protein_g: Mapped[float] = mapped_column(Float, nullable=False)
    carb_g: Mapped[float] = mapped_column(Float, nullable=False)
    fat_g: Mapped[float] = mapped_column(Float, nullable=False)

    __table_args__ = (
        CheckConstraint("kcal BETWEEN 0 AND 10000", name="ck_quick_foods_kcal_range"),
        CheckConstraint("protein_g BETWEEN 0 AND 2000", name="ck_quick_foods_protein_g_range"),
        CheckConstraint("carb_g BETWEEN 0 AND 2000", name="ck_quick_foods_carb_g_range"),
        CheckConstraint("fat_g BETWEEN 0 AND 2000", name="ck_quick_foods_fat_g_range"),
    )


class FoodEntry(Base):
    """A day-keyed, owner-scoped logged food entry (duplicates allowed;
    bounded to <=200 rows per (owner_uid, day_key) at the repository layer,
    T5)."""

    __tablename__ = "food_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_uid: Mapped[str] = mapped_column(String(128), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    kcal: Mapped[int] = mapped_column(Integer, nullable=False)
    protein_g: Mapped[float] = mapped_column(Float, nullable=False)
    carb_g: Mapped[float] = mapped_column(Float, nullable=False)
    fat_g: Mapped[float] = mapped_column(Float, nullable=False)
    meal_group: Mapped[str] = mapped_column(String(16), nullable=False)
    logged_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    day_key: Mapped[datetime.date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint("kcal BETWEEN 0 AND 10000", name="ck_food_entries_kcal_range"),
        CheckConstraint("protein_g BETWEEN 0 AND 2000", name="ck_food_entries_protein_g_range"),
        CheckConstraint("carb_g BETWEEN 0 AND 2000", name="ck_food_entries_carb_g_range"),
        CheckConstraint("fat_g BETWEEN 0 AND 2000", name="ck_food_entries_fat_g_range"),
        _enum_check("meal_group", MEAL_GROUPS),
        # Every bounded read is (owner_uid, day_key)-scoped (plan §Data DDIA
        # note) — this index keeps that scan an index range scan, not a table scan.
        Index("ix_food_entries_owner_uid_day_key", "owner_uid", "day_key"),
    )


class Program(Base):
    """A global (no owner) seeded workout program — one seeded row, "Push Day"."""

    __tablename__ = "programs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    focus: Mapped[str] = mapped_column(String(80), nullable=False)
    est_minutes: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (CheckConstraint("est_minutes > 0", name="ck_programs_est_minutes_positive"),)


class Exercise(Base):
    """A global (no owner) seeded exercise belonging to a program."""

    __tablename__ = "exercises"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    program_id: Mapped[int] = mapped_column(ForeignKey("programs.id"), nullable=False)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    sets: Mapped[int] = mapped_column(Integer, nullable=False)
    reps: Mapped[int] = mapped_column(Integer, nullable=False)
    weight: Mapped[float] = mapped_column(Float, nullable=False)
    muscle_tag: Mapped[str] = mapped_column(String(32), nullable=False)

    __table_args__ = (
        CheckConstraint("order_index >= 0", name="ck_exercises_order_index_non_negative"),
        CheckConstraint("sets > 0", name="ck_exercises_sets_positive"),
        CheckConstraint("reps > 0", name="ck_exercises_reps_positive"),
        CheckConstraint("weight >= 0", name="ck_exercises_weight_non_negative"),
        _enum_check("muscle_tag", MUSCLE_GROUPS),
    )


class SetEvent(Base):
    """A single completed set, toggled on/off by `POST`/`DELETE
    /train/sets` (T6). The UNIQUE constraint makes the toggle idempotent on
    replay (AC10)."""

    __tablename__ = "set_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_uid: Mapped[str] = mapped_column(String(128), nullable=False)
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id"), nullable=False)
    set_index: Mapped[int] = mapped_column(Integer, nullable=False)
    done_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    day_key: Mapped[datetime.date] = mapped_column(Date, nullable=False)

    __table_args__ = (
        CheckConstraint("set_index >= 0", name="ck_set_events_set_index_non_negative"),
        UniqueConstraint(
            "owner_uid", "exercise_id", "set_index", "day_key", name="uq_set_events_owner_exercise_set_day"
        ),
        Index("ix_set_events_owner_uid_day_key", "owner_uid", "day_key"),
    )


class WeightEntry(Base):
    """A canonical-kg weight entry; reads are a fixed 30-day window (T7)."""

    __tablename__ = "weight_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_uid: Mapped[str] = mapped_column(String(128), nullable=False)
    weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    day_key: Mapped[datetime.date] = mapped_column(Date, nullable=False)
    logged_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint("weight_kg BETWEEN 20 AND 500", name="ck_weight_entries_weight_kg_range"),
        Index("ix_weight_entries_owner_uid_day_key", "owner_uid", "day_key"),
    )
