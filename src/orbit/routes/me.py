"""`/me` account-lifecycle routes — every route depends on `require_auth`;
`owner_uid` is always derived from the verified token, never the request
body (mass-assignment defense).

`POST /me/bootstrap` is not in plan.md's explicit Tier-2 (uid-keyed) write-
route list (unlike `PATCH /profile`, `POST /me/signout`, `DELETE /me`), so it
carries no `require_resource_throttle` dependency — matching T3's original
shell, which likewise only wired `require_auth` here.
"""

import anyio.to_thread
from fastapi import APIRouter, Depends, HTTPException

from ..auth import delete_firebase_user, require_auth, require_fresh_reauth, revoke_refresh_tokens
from ..crypto import hash_uid
from ..edge.ratelimit import require_resource_throttle
from ..lifecycle.erase import erase_account_rows
from ..logging import get_logger
from ..repositories.base import get_sessionmaker
from ..repositories.profile import bootstrap_profile
from ..schemas.common import EmptyBody
from ..schemas.profile import ProfileOut

router = APIRouter(prefix="/me", tags=["me"])


@router.post("/bootstrap")
async def bootstrap(body: EmptyBody = EmptyBody(), user: dict = Depends(require_auth)) -> ProfileOut:
    """Idempotent create-if-absent: profile + 13 muscle base levels +
    defaults, atomically (AC4). `bootstrap_profile` is the atomic,
    idempotent-on-replay repository call; this route just opens the
    transaction and shapes the response."""
    async with get_sessionmaker()() as session:
        async with session.begin():
            profile, muscle_levels, _created = await bootstrap_profile(session, user["uid"])
    return ProfileOut.from_domain(profile, muscle_levels)


@router.post("/signout", status_code=204, dependencies=[Depends(require_resource_throttle)])
async def signout(body: EmptyBody = EmptyBody(), user: dict = Depends(require_auth)) -> None:
    """Invalidate every session for the caller (ASVS 7.4.1): `require_auth`'s
    `check_revoked=True` means any bearer ID token issued before this call is
    rejected 401 on its next use — not merely discarded client-side (session
    invalidation on sign-out, AC34).

    Dispatched to a worker thread: the Firebase Admin SDK is synchronous, so
    calling it inline would block the event loop for a network round trip."""
    await anyio.to_thread.run_sync(revoke_refresh_tokens, user["uid"])


@router.delete("", status_code=204, dependencies=[Depends(require_resource_throttle)])
async def delete_account(
    body: EmptyBody = EmptyBody(), user: dict = Depends(require_fresh_reauth)
) -> None:
    """Erase the caller's account: the hard-delete cascade (AC5/AC21 — one
    transaction across all five per-user domain tables via
    `lifecycle.erase.erase_account_rows`) followed by the Firebase identity
    delete. Requires fresh re-authentication (`require_fresh_reauth` — ASVS
    7.5.1): this is a destructive, irreversible operation, not merely an
    authenticated one.

    External-step ordering (Operator addendum #3): the DB cascade
    transaction commits FIRST; only then is
    `firebase_admin.auth.delete_user` attempted. If that post-commit step
    fails, the account's data is already gone — responding with anything but
    a generic failure would leak internal detail for no benefit — so this
    returns a generic 502 and the endpoint is retry-safe: the cascade delete
    is idempotent (a retry matches zero rows, a harmless no-op) and only
    re-attempts the identity delete. The `account.delete` audit event
    (hashed uid + outcome, no values) is emitted on both the success and
    failure path.
    """
    owner_uid = user["uid"]
    hashed_uid = hash_uid(owner_uid)

    async with get_sessionmaker()() as session:
        async with session.begin():
            await erase_account_rows(session, owner_uid)

    try:
        # Worker thread: the Admin SDK's delete is a blocking network call.
        await anyio.to_thread.run_sync(delete_firebase_user, owner_uid)
    except Exception:
        get_logger().warning(
            "account.delete", user_id=hashed_uid, outcome="firebase_identity_delete_failed"
        )
        raise HTTPException(
            status_code=502,
            detail="Account data was erased, but identity deletion failed. Please retry.",
        )

    get_logger().info("account.delete", user_id=hashed_uid, outcome="success")
