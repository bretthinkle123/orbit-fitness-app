"""Seed data — the quick-food catalog, the "Push Day" program + its 5
exercises, and the template muscle base levels `POST /me/bootstrap` (T4)
copies into a new user's own rows. A dedicated Alembic DATA migration per
plan.md §Data ("via a dedicated Alembic data migration, not app code") — no
seed value is hardcoded in application/route code.

Every row here traces to the design source (`design/design_handoff_orbit_swiftui/
Orbit Fitness.dc.html`'s `_D` state object): the 3 Fuel quick-add chips, the 5
Push Day exercises + their muscle tags, and the 13 muscle levels shown on the
Body screen. Profile defaults (kcal/macro targets, tier/percentile labels,
etc.) are declared as column defaults on `orbit.models.Profile` instead of a
seeded template row, since a single-row-per-user table has no repeatable
seed-and-copy shape the way the 13-row muscle levels do.

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-24 16:10:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0002"
down_revision: Union[str, Sequence[str], None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Design source: Orbit Fitness.dc.html `_D.quick` (the Fuel screen's 3 quick-add chips).
_QUICK_FOODS = [
    {"name": "Salmon & Rice Bowl", "kcal": 612, "protein_g": 42, "carb_g": 58, "fat_g": 21},
    {"name": "Whey Shake", "kcal": 178, "protein_g": 32, "carb_g": 8, "fat_g": 3},
    {"name": "Chicken Stir-fry", "kcal": 524, "protein_g": 41, "carb_g": 48, "fat_g": 16},
]

# Design source: Orbit Fitness.dc.html `_D.ex` (the Train screen's 5 seeded exercises)
# plus the "5 exercises · ~52 min · Chest focus" Home CTA copy.
_PUSH_DAY_PROGRAM_ID = 1
_PUSH_DAY_PROGRAM = {"id": _PUSH_DAY_PROGRAM_ID, "name": "Push Day", "focus": "Chest", "est_minutes": 52}
_PUSH_DAY_EXERCISES = [
    {
        "program_id": _PUSH_DAY_PROGRAM_ID,
        "order_index": 0,
        "name": "Barbell Bench Press",
        "sets": 4,
        "reps": 8,
        "weight": 185,
        "muscle_tag": "chest",
    },
    {
        "program_id": _PUSH_DAY_PROGRAM_ID,
        "order_index": 1,
        "name": "Incline DB Press",
        "sets": 3,
        "reps": 10,
        "weight": 60,
        "muscle_tag": "chest",
    },
    {
        "program_id": _PUSH_DAY_PROGRAM_ID,
        "order_index": 2,
        "name": "Seated Overhead Press",
        "sets": 3,
        "reps": 10,
        "weight": 95,
        "muscle_tag": "shoulders",
    },
    {
        "program_id": _PUSH_DAY_PROGRAM_ID,
        "order_index": 3,
        "name": "Cable Fly",
        "sets": 3,
        "reps": 12,
        "weight": 42.5,
        "muscle_tag": "chest",
    },
    {
        "program_id": _PUSH_DAY_PROGRAM_ID,
        "order_index": 4,
        "name": "Triceps Pushdown",
        "sets": 3,
        "reps": 12,
        "weight": 57.5,
        "muscle_tag": "triceps",
    },
]

# Design source: Orbit Fitness.dc.html `_D.muscles` (the Body screen's 13 rows).
_MUSCLE_LEVEL_TEMPLATES = [
    {"muscle_group": "chest", "level": 4},
    {"muscle_group": "shoulders", "level": 3},
    {"muscle_group": "traps", "level": 3},
    {"muscle_group": "biceps", "level": 3},
    {"muscle_group": "forearms", "level": 2},
    {"muscle_group": "core", "level": 3},
    {"muscle_group": "quads", "level": 2},
    {"muscle_group": "calves", "level": 1},
    {"muscle_group": "lats", "level": 4},
    {"muscle_group": "triceps", "level": 3},
    {"muscle_group": "lower_back", "level": 3},
    {"muscle_group": "glutes", "level": 2},
    {"muscle_group": "hamstrings", "level": 2},
]

# Lightweight Core table shadows — a data migration binds by column name only,
# never by importing the live ORM model (which could drift from the schema
# this migration actually targets as future migrations evolve the models).
_quick_foods_table = sa.table(
    "quick_foods",
    sa.column("name", sa.String),
    sa.column("kcal", sa.Integer),
    sa.column("protein_g", sa.Float),
    sa.column("carb_g", sa.Float),
    sa.column("fat_g", sa.Float),
)
_programs_table = sa.table(
    "programs",
    sa.column("id", sa.Integer),
    sa.column("name", sa.String),
    sa.column("focus", sa.String),
    sa.column("est_minutes", sa.Integer),
)
_exercises_table = sa.table(
    "exercises",
    sa.column("program_id", sa.Integer),
    sa.column("order_index", sa.Integer),
    sa.column("name", sa.String),
    sa.column("sets", sa.Integer),
    sa.column("reps", sa.Integer),
    sa.column("weight", sa.Float),
    sa.column("muscle_tag", sa.String),
)
_muscle_level_templates_table = sa.table(
    "muscle_level_templates",
    sa.column("muscle_group", sa.String),
    sa.column("level", sa.Integer),
)


def upgrade() -> None:
    """Insert the quick-food catalog, the Push Day program + exercises, and
    the muscle-level templates."""
    op.bulk_insert(_quick_foods_table, _QUICK_FOODS)
    op.bulk_insert(_programs_table, [_PUSH_DAY_PROGRAM])
    op.bulk_insert(_exercises_table, _PUSH_DAY_EXERCISES)
    op.bulk_insert(_muscle_level_templates_table, _MUSCLE_LEVEL_TEMPLATES)


def downgrade() -> None:
    """Remove exactly the rows this migration inserted, identified by their
    seeded values (not a blanket table wipe, in case other rows land in these
    global tables before a downgrade runs)."""
    quick_food_names = [row["name"] for row in _QUICK_FOODS]
    op.execute(_quick_foods_table.delete().where(_quick_foods_table.c.name.in_(quick_food_names)))

    exercise_names = [row["name"] for row in _PUSH_DAY_EXERCISES]
    op.execute(_exercises_table.delete().where(_exercises_table.c.name.in_(exercise_names)))
    op.execute(_programs_table.delete().where(_programs_table.c.name == _PUSH_DAY_PROGRAM["name"]))

    muscle_groups = [row["muscle_group"] for row in _MUSCLE_LEVEL_TEMPLATES]
    op.execute(
        _muscle_level_templates_table.delete().where(
            _muscle_level_templates_table.c.muscle_group.in_(muscle_groups)
        )
    )
