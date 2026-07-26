"""Firebase Admin SDK wrapper — the ONLY module that imports `firebase_admin`
directly (`auth-patterns`: "no route calls the SDK directly"). Everything
else in the app calls `auth/__init__.py`'s `require_auth` /
`revoke_refresh_tokens` / `delete_firebase_user` facade functions.
"""

import json
import os
import threading

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials

from ..config.secrets import get_secret
from ..config.settings import get_settings

_app: firebase_admin.App | None = None

# The SDK's blocking calls below are dispatched to a worker THREAD by their
# async callers (`auth/__init__.py`, `routes/me.py`) so they never stall the
# event loop. That makes `_get_app()` genuinely concurrent, so its lazy init
# needs a lock: without one, two cold-start requests can both observe
# `_app is None` and race into `initialize_app()`, and the loser raises
# ValueError ("the default Firebase app already exists").
_app_lock = threading.Lock()


def _build_credential() -> credentials.Base | None:
    """Return the Admin SDK credential to initialize with.

    Against the Firebase Auth emulator (`FIREBASE_AUTH_EMULATOR_HOST` set —
    local dev/tests), no real credential is needed at all, only the project
    id (verified against a live emulator this session). In deploy, the
    service-account JSON is fetched through the secrets facade (`config/
    secrets.py` — the only module that talks to the AWS SDK directly) and
    never appears as a literal credential in source.
    """
    if os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"):
        return None
    settings = get_settings()
    service_account_info = json.loads(get_secret(settings.firebase_admin_credentials_secret_name))
    return credentials.Certificate(service_account_info)


def _get_app() -> firebase_admin.App:
    """Return the singleton Firebase Admin app, initializing it on first use."""
    global _app
    if _app is not None:
        return _app
    with _app_lock:
        # Re-check inside the lock: another thread may have initialized the
        # app while this one was waiting to acquire it.
        if _app is not None:
            return _app
        settings = get_settings()
        credential = _build_credential()
        if credential is None:
            _app = firebase_admin.initialize_app(options={"projectId": settings.firebase_project_id})
        else:
            _app = firebase_admin.initialize_app(credential, options={"projectId": settings.firebase_project_id})
        return _app


def verify_id_token(id_token: str) -> dict:
    """Verify a Firebase ID token's signature (RS256, Google public keys, or
    the emulator's unsigned-but-claim-checked equivalent), `exp`, `aud`
    (project id), and `iss`, and honor revocation (`check_revoked=True`).
    Returns the normalized claims dict (includes `uid`)."""
    _get_app()
    return firebase_auth.verify_id_token(id_token, check_revoked=True)


def revoke_refresh_tokens(uid: str) -> None:
    """Invalidate every session for `uid` — any bearer ID token issued
    before this call is rejected on its next `verify_id_token` call (session
    invalidation on sign-out, ASVS 7.4.1)."""
    _get_app()
    firebase_auth.revoke_refresh_tokens(uid)


def delete_firebase_user(uid: str) -> None:
    """Delete the Firebase identity outright (account-deletion path, T8)."""
    _get_app()
    firebase_auth.delete_user(uid)


def reset_app_for_tests() -> None:
    """Test-only: tear down the real `firebase_admin` app registry entry (not
    just this module's cache — the SDK keeps its own singleton registry and
    raises on a second `initialize_app()` for the same name otherwise) so a
    test can reinitialize against a fresh emulator instance. Never called
    from application code."""
    global _app
    if _app is not None:
        firebase_admin.delete_app(_app)
    _app = None
