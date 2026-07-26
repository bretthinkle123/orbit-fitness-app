"""Two-tier rate limiting (`api-edge-conventions`), backed by a shared Redis
store — never in-process counters (those undercount silently once the app
scales past one instance behind a load balancer).

- **Tier-1** (pre-auth, IP + route-keyed) is global ASGI middleware. `/health`
  is exempt via a path check performed BEFORE any Redis touch (Operator
  addendum #2 — its no-external-deps contract extends to the limiter store).
- **Tier-2** (post-auth, uid-keyed) is a FastAPI dependency applied to
  individual write routes via `Depends(require_resource_throttle)`, so it
  resolves strictly after `require_auth` — the authenticated principal is
  guaranteed to exist at key time (the two-principals-one-IP correctness
  property this skill names).

**Fail-mode (Operator addendum #2):** both tiers fail OPEN (allow the
request) with a `warning` log when Redis is unreachable — fail-closed would
let a cache outage self-DoS the API.
"""

from __future__ import annotations

import time

import redis.asyncio as redis_asyncio
from fastapi import Depends, HTTPException, Request

from ..auth import require_auth
from ..config.settings import get_settings
from ..logging import get_logger
from .errors import build_error_response

# Checked FIRST in Tier-1's dispatch, before any Redis call — AC1's
# no-external-deps contract extends to the limiter store.
_THROTTLE_EXEMPT_PATHS = frozenset({"/health"})

_TIER1_LIMIT = 100
_TIER1_WINDOW_SECONDS = 60
_TIER2_LIMIT = 1000
_TIER2_WINDOW_SECONDS = 3600

_redis_client: redis_asyncio.Redis | None = None


def get_redis_client() -> redis_asyncio.Redis:
    """Return the process-wide async Redis client, creating it on first use."""
    global _redis_client
    if _redis_client is None:
        _redis_client = redis_asyncio.from_url(get_settings().redis_url, decode_responses=True)
    return _redis_client


def reset_redis_client_for_tests() -> None:
    """Test-only: drop the cached client so a test can point it at a
    different Redis instance (e.g. a fresh testcontainer) or force a
    connection failure. Never called from application code."""
    global _redis_client
    _redis_client = None


async def _increment_fixed_window(key: str, limit: int, window_seconds: int) -> tuple[bool, int]:
    """Fixed-window counter in Redis. Returns `(allowed, retry_after_seconds)`.

    Fails OPEN (`allowed=True`) with a `warning` log if Redis is unreachable
    — a cache outage must never become a self-inflicted denial of service
    (Operator addendum #2).
    """
    client = get_redis_client()
    now = time.time()
    bucket_key = f"{key}:{int(now // window_seconds)}"
    try:
        count = await client.incr(bucket_key)
        if count == 1:
            await client.expire(bucket_key, window_seconds)
    except Exception:
        get_logger().warning("rate limit store unavailable — failing open", key=key)
        return True, 0
    if count > limit:
        return False, window_seconds - int(now % window_seconds)
    return True, 0


class EdgeThrottleMiddleware:
    """TIER 1 — pre-auth, IP + route-keyed flood defense. Runs before any
    route dependency (including `require_auth`), so it must never key on
    identity (there isn't one yet) — see `require_resource_throttle` below
    for the post-auth tier.

A PURE ASGI middleware (`__call__(scope, receive, send)`), not a
    `BaseHTTPMiddleware` subclass: a plain ASGI callable awaits the inner app
    directly in the caller's task, one hop cheaper per request than
    `BaseHTTPMiddleware`'s call_next (which spawns a separate task via an
    anyio task group) — worth it here since this middleware runs on every
    single request. (An early version of this Redis-in-a-test-loop bug was
    traced to the test `TestClient` fixture being reused across a torn-down
    background event loop, not to `BaseHTTPMiddleware` itself — fixed in
    `tests/conftest.py`, not here; this class's ASGI-vs-BaseHTTPMiddleware
    choice is an independent efficiency decision.)

    Builds and SENDS the 429 envelope directly rather than raising
    `HTTPException`: this middleware sits above (outside) FastAPI's own
    exception-handling layer, so an exception raised here would bypass the
    registered error-envelope handlers entirely and surface as a generic,
    unmapped 500 — verified empirically, not assumed.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request = Request(scope, receive=receive)
        if request.url.path in _THROTTLE_EXEMPT_PATHS:
            await self.app(scope, receive, send)
            return

        client_ip = request.client.host if request.client else "unknown"
        key = f"edge:{client_ip}:{request.url.path}"
        allowed, retry_after = await _increment_fixed_window(key, _TIER1_LIMIT, _TIER1_WINDOW_SECONDS)
        if not allowed:
            get_logger().warning(
                "tier-1 rate limit exceeded", client_ip=client_ip, path=request.url.path
            )
            response = build_error_response(
                "rate_limited",
                "Too many requests.",
                request,
                429,
                headers={"Retry-After": str(retry_after)},
            )
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)


async def require_resource_throttle(request: Request, user: dict = Depends(require_auth)) -> None:
    """TIER 2 — post-auth, uid-keyed. A FastAPI dependency (not global
    middleware), so it only ever resolves after `require_auth`'s dependency
    has populated `user` — apply via `Depends(require_resource_throttle)` on
    write routes. Unlike Tier-1, raising `HTTPException` here is safe: a
    dependency's exception is resolved within FastAPI's own exception-handler
    dispatch, which our registered handlers do intercept.
    """
    owner_uid = user["uid"]
    key = f"resource:{owner_uid}"
    allowed, retry_after = await _increment_fixed_window(key, _TIER2_LIMIT, _TIER2_WINDOW_SECONDS)
    if not allowed:
        get_logger().warning(
            "tier-2 rate limit exceeded", operation=f"{request.method} {request.url.path}"
        )
        raise HTTPException(
            status_code=429, detail="Too many requests", headers={"Retry-After": str(retry_after)}
        )
