"""Liveness probe route.

`GET /health` touches no DB/Firebase/Redis so it stays 200 even when every
downstream dependency is unavailable — the smoke check depends on this
(CLAUDE.md, AC1). It is exempt from rate limiting (the Tier-1 edge throttle
checks the path before touching Redis, once that middleware lands in T3).
"""

from fastapi import APIRouter

router = APIRouter()


@router.get("/health", tags=["health"])
async def health() -> dict[str, str]:
    """Return a static 200 payload — no external dependency is consulted."""
    return {"status": "ok"}
