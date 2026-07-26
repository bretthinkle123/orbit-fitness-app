"""Auth facade (`auth-patterns`) — `require_auth` is the ONLY way a route
gets the caller's identity; `auth/firebase.py` is the only module that talks
to the Firebase Admin SDK. Row-level ownership downstream always derives
`owner_uid` from these verified claims, never from a request body.
"""

import time

import anyio.to_thread
from fastapi import Depends, HTTPException, Request

from .firebase import delete_firebase_user, revoke_refresh_tokens, verify_id_token

__all__ = [
    "require_auth",
    "require_fresh_reauth",
    "revoke_refresh_tokens",
    "delete_firebase_user",
]

_BEARER_PREFIX = "Bearer "

# ASVS 7.5.1 — a destructive operation (account deletion, T8) requires the
# token's `auth_time` to be recent, not just valid.
_FRESH_REAUTH_WINDOW_SECONDS = 5 * 60


def _extract_bearer_token(request: Request) -> str:
    """Pull the raw ID token out of the Authorization header, or 401."""
    header = request.headers.get("authorization", "")
    if not header.startswith(_BEARER_PREFIX):
        raise HTTPException(status_code=401, detail="Missing or malformed Authorization header")
    token = header[len(_BEARER_PREFIX) :].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing or malformed Authorization header")
    return token


async def require_auth(request: Request) -> dict:
    """Verify the bearer Firebase ID token and return its normalized claims.

    Stores the claims on `request.state.user` so downstream code (the Tier-2
    resource throttle, request logging) can read the principal without a
    second verification. Any verification failure — missing token, bad
    signature, expired, wrong audience/issuer, or revoked — is a 401; the
    caller never learns which (spoofing defense, ASVS 9.1.1/9.1.2/9.2.3).

    `verify_id_token` is a BLOCKING call — the Firebase Admin SDK is
    synchronous, and with `check_revoked=True` it makes a network round trip
    to Firebase on every call. Awaiting it directly on the event loop would
    serialize every concurrent request behind that I/O (this guard runs on
    every authenticated request), so it is dispatched to a worker thread.
    """
    token = _extract_bearer_token(request)
    try:
        claims = await anyio.to_thread.run_sync(verify_id_token, token)
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=401, detail="Invalid or expired auth token") from error
    request.state.user = claims
    return claims


def require_fresh_reauth(user: dict = Depends(require_auth)) -> dict:
    """Require the token's `auth_time` to be within the fresh-reauth window —
    gates a destructive operation (`DELETE /me`, T8) on top of `require_auth`.
    Built now so T8 only adds the route, not a new auth mechanism."""
    auth_time = user.get("auth_time")
    if auth_time is None or time.time() - auth_time > _FRESH_REAUTH_WINDOW_SECONDS:
        raise HTTPException(status_code=401, detail="Re-authentication required")
    return user
