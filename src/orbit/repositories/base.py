"""Database engine + session facade — the one place the app builds its
Postgres connection (`repositories/` is the repository-facade seam per
plan.md §Data: "every query is owner-scoped and bounded in one place").

`resolve_database_url()` prefers a local override (dev/test — e.g. a
testcontainers URL) and otherwise fetches the connection string from Secrets
Manager through the secrets facade (`config/secrets.py`) — never a second
SDK caller. The engine's `async_creator` re-runs that resolution on every new
physical connection (not just once at process start), so a rotated
Secrets-Manager credential is adopted the next time the pool opens or
recycles a connection, bounded by the secrets facade's own TTL cache —
the concrete "rotation-aware" mechanism plan.md §Runtime-secrets requires.
"""

import anyio.to_thread
import asyncpg
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from ..config.secrets import get_secret
from ..config.settings import get_settings

# How often a pooled connection is discarded and reopened — the ceiling on
# how long a rotated credential can take to be adopted (on top of the
# secrets facade's own cache TTL).
_POOL_RECYCLE_SECONDS = 1800

_engine: AsyncEngine | None = None


def resolve_database_url() -> str:
    """Resolve the Postgres connection string for this process.

    Local/dev/test: `settings.database_url` (e.g. a testcontainers DSN).
    Deploy: the named secret from Secrets Manager, via the secrets facade.
    """
    settings = get_settings()
    if settings.database_url:
        return settings.database_url
    return get_secret(settings.database_url_secret_name)


async def _open_connection() -> asyncpg.Connection:
    """Open one physical asyncpg connection, resolving the DSN fresh each
    time (the rotation-adoption mechanism described in the module docstring).

    The resolution runs in a worker thread: on a secrets-cache miss it reaches
    Secrets Manager through the secrets facade's SYNCHRONOUS AWS SDK client,
    which would otherwise block the event loop for the length of that round
    trip every time the pool opens or recycles a connection.
    """
    url = await anyio.to_thread.run_sync(resolve_database_url)
    # asyncpg's DSN parser doesn't know the SQLAlchemy "+asyncpg" dialect
    # suffix — strip it before handing the DSN to the driver directly.
    dsn = url.replace("postgresql+asyncpg://", "postgresql://", 1)
    return await asyncpg.connect(dsn=dsn)


def get_engine() -> AsyncEngine:
    """Return the process-wide async engine, creating it on first use."""
    global _engine
    if _engine is None:
        _engine = create_async_engine(
            "postgresql+asyncpg://",
            async_creator=_open_connection,
            pool_pre_ping=True,
            pool_recycle=_POOL_RECYCLE_SECONDS,
        )
    return _engine


def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    """Return an `async_sessionmaker` bound to the process-wide engine."""
    return async_sessionmaker(bind=get_engine(), expire_on_commit=False)


async def dispose_engine() -> None:
    """Dispose the process-wide engine and its connection pool (test
    teardown / graceful shutdown)."""
    global _engine
    if _engine is not None:
        await _engine.dispose()
        _engine = None
