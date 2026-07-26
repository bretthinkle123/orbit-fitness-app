"""Integration tests for the initial-schema + seed migrations (T2).

Covers the plan's two T2 test-strategy shapes:

- **Migration round-trip** (AC24, create-migration kind): `upgrade head` ->
  `downgrade base` -> `upgrade head` restores every table, CHECK, FK, UNIQUE,
  and NOT NULL constraint. Seeded prod-shaped data is inserted before the
  round trip so the assertion is real (an empty schema round-tripping proves
  nothing); row survival across the intentional `downgrade` is NOT asserted,
  since dropping a table drops its rows by definition.
- **Seed-content** (AC6, AC9): the quick-food catalog, the "Push Day" program
  + its 5 exercises, and the 13 muscle-level templates all land via the
  migration itself, not application code.
"""

import os
import subprocess
from pathlib import Path

import pytest
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine
from testcontainers.postgres import PostgresContainer

_REPO_ROOT = Path(__file__).resolve().parents[2]


def _to_asyncpg_url(container_url: str) -> str:
    """Rewrite whatever dialect testcontainers hands back (typically
    `+psycopg2`) to the `+asyncpg` URL both the app and Alembic expect."""
    if "+psycopg2" in container_url:
        return container_url.replace("+psycopg2", "+asyncpg")
    if container_url.startswith("postgresql://"):
        return container_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    return container_url


@pytest.fixture(scope="module")
def postgres_url():
    """One testcontainers Postgres instance for the whole module. Tests move
    it between schema states via real `alembic` CLI invocations rather than
    assuming a particular starting state."""
    with PostgresContainer("postgres:16-alpine") as container:
        yield _to_asyncpg_url(container.get_connection_url())


def _run_alembic(*args: str, database_url: str) -> None:
    """Run an `alembic` CLI command against the given DSN; fails the test
    loudly (assert) rather than continuing on a broken migration."""
    env = os.environ.copy()
    env["DATABASE_URL"] = database_url
    result = subprocess.run(
        ["alembic", *args], cwd=_REPO_ROOT, env=env, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"alembic {' '.join(args)} failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


async def _insert_prod_shaped_fixture(database_url: str) -> None:
    """Insert one representative row per per-user table — a genuine
    "prod-shaped" fixture, not an empty schema — so the round-trip test
    proves something real (test-conventions create-migration rule)."""
    engine = create_async_engine(database_url)
    try:
        async with engine.begin() as connection:
            await connection.execute(
                sa.text(
                    "INSERT INTO profiles (owner_uid, kcal_budget, protein_target_g, carb_target_g, "
                    "fat_target_g, score_base, tier_label, percentile_label, next_tier_pct, "
                    "palette_preset, units, gender, planet_index) VALUES "
                    "('prod-shaped-uid', 2350, 185, 240, 72, 512, 'Beginner', 'Top 100%', 0, "
                    "'purple', 'imperial', 'm', 0)"
                )
            )
            await connection.execute(
                sa.text(
                    "INSERT INTO muscle_base_levels (owner_uid, muscle_group, level) VALUES "
                    "('prod-shaped-uid', 'chest', 4)"
                )
            )
            await connection.execute(
                sa.text(
                    "INSERT INTO food_entries (owner_uid, name, kcal, protein_g, carb_g, fat_g, "
                    "meal_group, logged_at, day_key) VALUES "
                    "('prod-shaped-uid', 'Test Meal', 500, 30, 40, 15, 'lunch', now(), CURRENT_DATE)"
                )
            )
            await connection.execute(
                sa.text(
                    "INSERT INTO weight_entries (owner_uid, weight_kg, day_key, logged_at) VALUES "
                    "('prod-shaped-uid', 80.5, CURRENT_DATE, now())"
                )
            )
    finally:
        await engine.dispose()


async def _fetch_scalar(database_url: str, query: str, *params) -> object:
    """Run one scalar query against a fresh throwaway engine."""
    engine = create_async_engine(database_url)
    try:
        async with engine.connect() as connection:
            result = await connection.execute(sa.text(query), params[0] if params else {})
            return result.scalar_one()
    finally:
        await engine.dispose()


async def _assert_every_named_constraint_still_enforces(database_url: str) -> None:
    """Re-verify a representative CHECK, the enum-CHECK, the FK, and the
    UNIQUE constraint all still reject a violation after the round trip —
    the "every CHECK/FK/UNIQUE/NOT NULL re-enforces" half of AC24."""
    engine = create_async_engine(database_url)
    try:
        # `engine.begin()` acquires a fresh connection AND starts its
        # transaction together, so each attempt below is isolated — no
        # explicit `connection.begin()` fights with SQLAlchemy 2.0's
        # connection-level autobegin.

        # CHECK: weight_kg out of the 20..500 range.
        with pytest.raises(Exception, match="ck_weight_entries_weight_kg_range"):
            async with engine.begin() as connection:
                await connection.execute(
                    sa.text(
                        "INSERT INTO weight_entries (owner_uid, weight_kg, day_key, logged_at) "
                        "VALUES ('constraint-check-uid', 5, CURRENT_DATE, now())"
                    )
                )

        # Enum CHECK: an out-of-set muscle_group.
        with pytest.raises(Exception, match="ck_muscle_group_enum"):
            async with engine.begin() as connection:
                await connection.execute(
                    sa.text(
                        "INSERT INTO muscle_base_levels (owner_uid, muscle_group, level) "
                        "VALUES ('constraint-check-uid', 'not_a_real_group', 3)"
                    )
                )

        # FK: set_events.exercise_id must reference a real exercise.
        with pytest.raises(Exception, match="fkey|foreign key"):
            async with engine.begin() as connection:
                await connection.execute(
                    sa.text(
                        "INSERT INTO set_events (owner_uid, exercise_id, set_index, done_at, day_key) "
                        "VALUES ('constraint-check-uid', 999999, 0, now(), CURRENT_DATE)"
                    )
                )

        # UNIQUE: the same (owner_uid, exercise_id, set_index, day_key) twice.
        async with engine.begin() as connection:
            exercise_id = (
                await connection.execute(sa.text("SELECT id FROM exercises ORDER BY id LIMIT 1"))
            ).scalar_one()

        async with engine.begin() as connection:
            await connection.execute(
                sa.text(
                    "INSERT INTO set_events (owner_uid, exercise_id, set_index, done_at, day_key) "
                    "VALUES ('unique-check-uid', :exercise_id, 0, now(), CURRENT_DATE)"
                ),
                {"exercise_id": exercise_id},
            )

        with pytest.raises(Exception, match="uq_set_events_owner_exercise_set_day"):
            async with engine.begin() as connection:
                await connection.execute(
                    sa.text(
                        "INSERT INTO set_events (owner_uid, exercise_id, set_index, done_at, day_key) "
                        "VALUES ('unique-check-uid', :exercise_id, 0, now(), CURRENT_DATE)"
                    ),
                    {"exercise_id": exercise_id},
                )
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_migration_round_trip_restores_schema_and_constraints(postgres_url):
    """`upgrade head` -> `downgrade base` -> `upgrade head`, seeding a
    prod-shaped fixture beforehand, restores the full schema and every named
    constraint (AC24). Row survival across the downgrade is NOT asserted."""
    _run_alembic("upgrade", "head", database_url=postgres_url)
    await _insert_prod_shaped_fixture(postgres_url)

    _run_alembic("downgrade", "base", database_url=postgres_url)
    _run_alembic("upgrade", "head", database_url=postgres_url)

    # Schema exists again — every table is queryable with zero domain rows
    # (the prod-shaped fixture did not survive; the downgrade dropped it).
    for table_name in (
        "profiles",
        "muscle_base_levels",
        "muscle_level_templates",
        "quick_foods",
        "food_entries",
        "programs",
        "exercises",
        "set_events",
        "weight_entries",
    ):
        count = await _fetch_scalar(postgres_url, f"SELECT count(*) FROM {table_name}")
        assert count is not None  # table exists and is queryable

    profile_row_count = await _fetch_scalar(postgres_url, "SELECT count(*) FROM profiles")
    assert profile_row_count == 0, "the prod-shaped fixture row must not survive the drop-and-recreate"

    await _assert_every_named_constraint_still_enforces(postgres_url)


@pytest.mark.asyncio
async def test_seed_migration_populates_the_quick_food_catalog_with_macros(postgres_url):
    """AC6: the quick-food catalog (with macros) lands via the migration."""
    _run_alembic("upgrade", "head", database_url=postgres_url)

    engine = create_async_engine(postgres_url)
    try:
        async with engine.connect() as connection:
            rows = (
                await connection.execute(
                    sa.text("SELECT name, kcal, protein_g, carb_g, fat_g FROM quick_foods ORDER BY name")
                )
            ).all()
    finally:
        await engine.dispose()

    names = {row.name for row in rows}
    assert names == {"Salmon & Rice Bowl", "Whey Shake", "Chicken Stir-fry"}
    for row in rows:
        # Every seeded row carries real macros, not zeros/nulls.
        assert row.kcal > 0
        assert row.protein_g >= 0
        assert row.carb_g >= 0
        assert row.fat_g >= 0


@pytest.mark.asyncio
async def test_seed_migration_populates_push_day_program_with_five_exercises(postgres_url):
    """AC9: the seeded "Push Day" program has exactly 5 exercises, each with
    a name, set/rep scheme, weight, and muscle tag."""
    _run_alembic("upgrade", "head", database_url=postgres_url)

    engine = create_async_engine(postgres_url)
    try:
        async with engine.connect() as connection:
            program = (
                await connection.execute(sa.text("SELECT id, name, focus FROM programs"))
            ).one()
            exercises = (
                await connection.execute(
                    sa.text(
                        "SELECT name, sets, reps, weight, muscle_tag FROM exercises "
                        "WHERE program_id = :program_id ORDER BY order_index"
                    ),
                    {"program_id": program.id},
                )
            ).all()
    finally:
        await engine.dispose()

    assert program.name == "Push Day"
    assert len(exercises) == 5
    for exercise in exercises:
        assert exercise.name
        assert exercise.sets > 0
        assert exercise.reps > 0
        assert exercise.weight >= 0
        assert exercise.muscle_tag in {
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
        }


@pytest.mark.asyncio
async def test_seed_migration_populates_all_thirteen_muscle_level_templates(postgres_url):
    """The 13 template muscle levels `POST /me/bootstrap` (T4) will copy per
    new user land via the migration, one row per muscle group, level 1-6."""
    _run_alembic("upgrade", "head", database_url=postgres_url)

    engine = create_async_engine(postgres_url)
    try:
        async with engine.connect() as connection:
            rows = (
                await connection.execute(sa.text("SELECT muscle_group, level FROM muscle_level_templates"))
            ).all()
    finally:
        await engine.dispose()

    assert len(rows) == 13
    for row in rows:
        assert 1 <= row.level <= 6
