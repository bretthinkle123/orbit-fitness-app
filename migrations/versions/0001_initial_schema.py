"""Initial schema — every table, CHECK/FK/UNIQUE constraint, enum-CHECK, and
composite (owner_uid, day_key) index from plan.md §Data. A create-migration
(AC24): the round-trip criterion is schema + constraint reversibility, not
row-survival across `downgrade()` (which drops the tables).

Revision ID: 0001
Revises:
Create Date: 2026-07-24 15:58:05.443268
"""

from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0001"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create every table with its full constraint set (generated from
    `orbit.models` via `alembic revision --autogenerate` against a live
    Postgres instance, then hand-reviewed for the exact schema in plan.md)."""
    op.create_table('food_entries',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('owner_uid', sa.String(length=128), nullable=False),
    sa.Column('name', sa.String(length=120), nullable=False),
    sa.Column('kcal', sa.Integer(), nullable=False),
    sa.Column('protein_g', sa.Float(), nullable=False),
    sa.Column('carb_g', sa.Float(), nullable=False),
    sa.Column('fat_g', sa.Float(), nullable=False),
    sa.Column('meal_group', sa.String(length=16), nullable=False),
    sa.Column('logged_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('day_key', sa.Date(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("meal_group IN ('breakfast', 'lunch', 'snacks', 'dinner')", name='ck_meal_group_enum'),
    sa.CheckConstraint('carb_g BETWEEN 0 AND 2000', name='ck_food_entries_carb_g_range'),
    sa.CheckConstraint('fat_g BETWEEN 0 AND 2000', name='ck_food_entries_fat_g_range'),
    sa.CheckConstraint('kcal BETWEEN 0 AND 10000', name='ck_food_entries_kcal_range'),
    sa.CheckConstraint('protein_g BETWEEN 0 AND 2000', name='ck_food_entries_protein_g_range'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_food_entries_owner_uid_day_key', 'food_entries', ['owner_uid', 'day_key'], unique=False)
    op.create_table('muscle_base_levels',
    sa.Column('owner_uid', sa.String(length=128), nullable=False),
    sa.Column('muscle_group', sa.String(length=32), nullable=False),
    sa.Column('level', sa.Integer(), nullable=False),
    sa.CheckConstraint("muscle_group IN ('chest', 'shoulders', 'traps', 'biceps', 'forearms', 'core', 'quads', 'calves', 'lats', 'triceps', 'lower_back', 'glutes', 'hamstrings')", name='ck_muscle_group_enum'),
    sa.CheckConstraint('level BETWEEN 1 AND 6', name='ck_muscle_base_levels_level_range'),
    sa.PrimaryKeyConstraint('owner_uid', 'muscle_group')
    )
    op.create_table('muscle_level_templates',
    sa.Column('muscle_group', sa.String(length=32), nullable=False),
    sa.Column('level', sa.Integer(), nullable=False),
    sa.CheckConstraint("muscle_group IN ('chest', 'shoulders', 'traps', 'biceps', 'forearms', 'core', 'quads', 'calves', 'lats', 'triceps', 'lower_back', 'glutes', 'hamstrings')", name='ck_muscle_group_enum'),
    sa.CheckConstraint('level BETWEEN 1 AND 6', name='ck_muscle_level_templates_level_range'),
    sa.PrimaryKeyConstraint('muscle_group')
    )
    op.create_table('profiles',
    sa.Column('owner_uid', sa.String(length=128), nullable=False),
    sa.Column('kcal_budget', sa.Integer(), nullable=False),
    sa.Column('protein_target_g', sa.Integer(), nullable=False),
    sa.Column('carb_target_g', sa.Integer(), nullable=False),
    sa.Column('fat_target_g', sa.Integer(), nullable=False),
    sa.Column('score_base', sa.Integer(), nullable=False),
    sa.Column('tier_label', sa.String(length=64), nullable=False),
    sa.Column('percentile_label', sa.String(length=64), nullable=False),
    sa.Column('next_tier_pct', sa.Integer(), nullable=False),
    sa.Column('palette_preset', sa.String(length=16), nullable=False),
    sa.Column('units', sa.String(length=16), nullable=False),
    sa.Column('gender', sa.String(length=4), nullable=False),
    sa.Column('planet_index', sa.Integer(), nullable=False),
    sa.Column('burned_kcal', sa.Integer(), nullable=True),
    sa.Column('burn_rate', sa.Float(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("gender IN ('m', 'w')", name='ck_gender_enum'),
    sa.CheckConstraint("palette_preset IN ('purple', 'blue', 'red', 'green')", name='ck_palette_preset_enum'),
    sa.CheckConstraint("units IN ('metric', 'imperial')", name='ck_units_enum'),
    sa.CheckConstraint('carb_target_g BETWEEN 0 AND 1000', name='ck_profiles_carb_target_g_range'),
    sa.CheckConstraint('fat_target_g BETWEEN 0 AND 1000', name='ck_profiles_fat_target_g_range'),
    sa.CheckConstraint('kcal_budget BETWEEN 500 AND 10000', name='ck_profiles_kcal_budget_range'),
    sa.CheckConstraint('next_tier_pct BETWEEN 0 AND 100', name='ck_profiles_next_tier_pct_range'),
    sa.CheckConstraint('planet_index BETWEEN 0 AND 5', name='ck_profiles_planet_index_range'),
    sa.CheckConstraint('protein_target_g BETWEEN 0 AND 1000', name='ck_profiles_protein_target_g_range'),
    sa.PrimaryKeyConstraint('owner_uid')
    )
    op.create_table('programs',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('name', sa.String(length=80), nullable=False),
    sa.Column('focus', sa.String(length=80), nullable=False),
    sa.Column('est_minutes', sa.Integer(), nullable=False),
    sa.CheckConstraint('est_minutes > 0', name='ck_programs_est_minutes_positive'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('quick_foods',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('name', sa.String(length=120), nullable=False),
    sa.Column('kcal', sa.Integer(), nullable=False),
    sa.Column('protein_g', sa.Float(), nullable=False),
    sa.Column('carb_g', sa.Float(), nullable=False),
    sa.Column('fat_g', sa.Float(), nullable=False),
    sa.CheckConstraint('carb_g BETWEEN 0 AND 2000', name='ck_quick_foods_carb_g_range'),
    sa.CheckConstraint('fat_g BETWEEN 0 AND 2000', name='ck_quick_foods_fat_g_range'),
    sa.CheckConstraint('kcal BETWEEN 0 AND 10000', name='ck_quick_foods_kcal_range'),
    sa.CheckConstraint('protein_g BETWEEN 0 AND 2000', name='ck_quick_foods_protein_g_range'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('weight_entries',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('owner_uid', sa.String(length=128), nullable=False),
    sa.Column('weight_kg', sa.Float(), nullable=False),
    sa.Column('day_key', sa.Date(), nullable=False),
    sa.Column('logged_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('weight_kg BETWEEN 20 AND 500', name='ck_weight_entries_weight_kg_range'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_weight_entries_owner_uid_day_key', 'weight_entries', ['owner_uid', 'day_key'], unique=False)
    op.create_table('exercises',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('program_id', sa.Integer(), nullable=False),
    sa.Column('order_index', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=120), nullable=False),
    sa.Column('sets', sa.Integer(), nullable=False),
    sa.Column('reps', sa.Integer(), nullable=False),
    sa.Column('weight', sa.Float(), nullable=False),
    sa.Column('muscle_tag', sa.String(length=32), nullable=False),
    sa.CheckConstraint("muscle_tag IN ('chest', 'shoulders', 'traps', 'biceps', 'forearms', 'core', 'quads', 'calves', 'lats', 'triceps', 'lower_back', 'glutes', 'hamstrings')", name='ck_muscle_tag_enum'),
    sa.CheckConstraint('order_index >= 0', name='ck_exercises_order_index_non_negative'),
    sa.CheckConstraint('reps > 0', name='ck_exercises_reps_positive'),
    sa.CheckConstraint('sets > 0', name='ck_exercises_sets_positive'),
    sa.CheckConstraint('weight >= 0', name='ck_exercises_weight_non_negative'),
    sa.ForeignKeyConstraint(['program_id'], ['programs.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('set_events',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('owner_uid', sa.String(length=128), nullable=False),
    sa.Column('exercise_id', sa.Integer(), nullable=False),
    sa.Column('set_index', sa.Integer(), nullable=False),
    sa.Column('done_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('day_key', sa.Date(), nullable=False),
    sa.CheckConstraint('set_index >= 0', name='ck_set_events_set_index_non_negative'),
    sa.ForeignKeyConstraint(['exercise_id'], ['exercises.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('owner_uid', 'exercise_id', 'set_index', 'day_key', name='uq_set_events_owner_exercise_set_day')
    )
    op.create_index('ix_set_events_owner_uid_day_key', 'set_events', ['owner_uid', 'day_key'], unique=False)


def downgrade() -> None:
    """Drop every table (FK-child tables first) — schema/constraint
    reversibility only; row survival across a downgrade is undefined by
    definition (dropping a table drops its rows)."""
    op.drop_index('ix_set_events_owner_uid_day_key', table_name='set_events')
    op.drop_table('set_events')
    op.drop_table('exercises')
    op.drop_index('ix_weight_entries_owner_uid_day_key', table_name='weight_entries')
    op.drop_table('weight_entries')
    op.drop_table('quick_foods')
    op.drop_table('programs')
    op.drop_table('profiles')
    op.drop_table('muscle_level_templates')
    op.drop_table('muscle_base_levels')
    op.drop_index('ix_food_entries_owner_uid_day_key', table_name='food_entries')
    op.drop_table('food_entries')
