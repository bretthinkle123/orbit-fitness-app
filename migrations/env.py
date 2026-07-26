"""Alembic environment — runs migrations against the async engine's URL,
resolved through the same `repositories/base.py` facade the app itself uses
(never a second, ad-hoc DB-URL resolution path).
"""

import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

from orbit.models import Base
from orbit.repositories.base import resolve_database_url

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Every model's table metadata — the source `alembic revision --autogenerate`
# diffs against, and what the create-migration below builds from directly.
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Emit migration SQL against a URL only, no live DB connection needed."""
    context.configure(
        url=resolve_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def _run_migrations_sync(connection: Connection) -> None:
    """Configure Alembic against a live (synchronous-interface) connection
    and run the migration script — invoked via `AsyncConnection.run_sync`."""
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    """Build the async engine (same DSN-resolution facade as the app) and
    bridge to Alembic's synchronous migration runner via `run_sync`."""
    connectable = async_engine_from_config(
        {"sqlalchemy.url": resolve_database_url()},
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(_run_migrations_sync)

    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
