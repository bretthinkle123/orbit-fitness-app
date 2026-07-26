#!/usr/bin/env python
"""Seed a non-production, low-privilege DAST test user (`dast-conventions`
DAST-2/DAST-3) — the Firebase principal `dast-staging.yml`'s Schemathesis/ZAP
jobs authenticate as.

Idempotent: reuses the existing account (signs in) if a prior run already
created it, rather than erroring on a duplicate signup — safe to re-run on
every DAST seeding cycle.

Every credential is read through this app's config/secrets facades
(`config/settings.py` / `config/secrets.py`), never a bare `os.environ` call
or a hardcoded literal in this file (code-standards). Refuses to run at all
against a `production` `ENVIRONMENT` — this is deliberately a non-production
principal (DAST-2).

Usage (local/emulator):
    FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 python scripts/seed_dast_user.py

Usage (a real, non-production Firebase project — deploy/staging seeding):
    DAST_TEST_USER_PASSWORD=... FIREBASE_WEB_API_KEY=... python scripts/seed_dast_user.py

Prints the minted ID token to stdout on success (never the password) — a
human/CI step stores it in SSM (`dast-staging.yml`'s `<DAST_TOKEN_SSM_PARAM>`);
this script's job ends at "the test user exists and here is a working token,"
not at storing it (no AWS account exists yet this run — Operator addendum #4).

`requests` is a dev-group dependency (already pinned for test use, T3) reused
here rather than promoted to a main dependency — this script runs in the same
dev/ops context as the test suite (local, or a future seeding job with dev
deps installed), not the deployed API process itself (YAGNI: no proven
production-runtime need for `requests` exists yet).
"""

from __future__ import annotations

import os
import sys

import requests

from orbit.config.secrets import get_secret
from orbit.config.settings import get_settings

_IDENTITY_TOOLKIT_HOST = "identitytoolkit.googleapis.com"
_EMAIL_ALREADY_EXISTS = "EMAIL_EXISTS"


class ProductionEnvironmentRefusalError(RuntimeError):
    """Raised when this script is invoked against a `production` environment
    — DAST-2 requires a NON-production test principal, never a real one."""


def _identity_toolkit_url(path: str, emulator_host: str | None) -> str:
    """Build the Identity Toolkit REST endpoint — the local emulator's plain
    HTTP host when set (dev/test), else the real Google endpoint (a real,
    non-production Firebase project)."""
    if emulator_host:
        return f"http://{emulator_host}/{_IDENTITY_TOOLKIT_HOST}/v1/{path}"
    return f"https://{_IDENTITY_TOOLKIT_HOST}/v1/{path}"


def _resolve_web_api_key(settings) -> str:
    """The Identity Toolkit REST API's `key` query param. The emulator
    ignores its value entirely (any string works); a real project needs the
    genuine Firebase Web API key — never hardcoded, so a local override
    (`firebase_web_api_key`) is tried first, falling back to Secrets Manager
    (mirrors `repositories/base.py::resolve_database_url`'s precedent)."""
    if settings.firebase_web_api_key:
        return settings.firebase_web_api_key
    return get_secret(settings.firebase_web_api_key_secret_name)


def _resolve_password(settings) -> str:
    """The DAST test user's password — never hardcoded. A local override
    (`dast_test_user_password`, e.g. against the emulator) is tried first,
    falling back to Secrets Manager for a real, non-production project."""
    if settings.dast_test_user_password:
        return settings.dast_test_user_password
    return get_secret(settings.dast_test_user_password_secret_name)


def _refuse_production_environment(settings) -> None:
    """DAST-2 requires a NON-production test principal — fail loudly rather
    than silently seeding (or worse, reusing) an account in a real
    production Firebase project."""
    if settings.environment.lower() in ("production", "prod"):
        raise ProductionEnvironmentRefusalError(
            "refusing to seed a DAST test user against a production environment"
        )


def seed_dast_user(emulator_host: str | None = None) -> dict:
    """Create (or, on a repeat run, sign in as) the seeded DAST test user and
    return `{"uid", "email", "id_token"}`.

    `emulator_host` defaults to reading `FIREBASE_AUTH_EMULATOR_HOST` directly
    — the one deliberate, already-established exception to "route config
    through the settings facade" (`auth/firebase.py::_build_credential` reads
    this exact env var the same direct way): it is the Firebase SDK's own
    environment-toggle contract, not app config this script names, so a
    second, redundant `Settings` field for it would just duplicate that
    convention rather than centralize it.
    """
    resolved_emulator_host = emulator_host or os.environ.get("FIREBASE_AUTH_EMULATOR_HOST")

    settings = get_settings()
    _refuse_production_environment(settings)

    email = settings.dast_test_user_email
    password = _resolve_password(settings)
    api_key = _resolve_web_api_key(settings)

    signup_response = requests.post(
        _identity_toolkit_url("accounts:signUp", resolved_emulator_host),
        params={"key": api_key},
        json={"email": email, "password": password, "returnSecureToken": True},
        timeout=10,
    )
    if signup_response.status_code == 200:
        data = signup_response.json()
        return {"uid": data["localId"], "email": email, "id_token": data["idToken"]}

    error_message = signup_response.json().get("error", {}).get("message", "")
    if _EMAIL_ALREADY_EXISTS not in error_message:
        signup_response.raise_for_status()

    # Idempotent path: the account already exists from a prior seeding run —
    # sign in instead of failing on the duplicate-signup error.
    signin_response = requests.post(
        _identity_toolkit_url("accounts:signInWithPassword", resolved_emulator_host),
        params={"key": api_key},
        json={"email": email, "password": password, "returnSecureToken": True},
        timeout=10,
    )
    signin_response.raise_for_status()
    data = signin_response.json()
    return {"uid": data["localId"], "email": email, "id_token": data["idToken"]}


def main() -> None:
    """CLI entry point: seed the DAST test user and print the result (never
    the password) to stdout for a human/CI step to consume."""
    result = seed_dast_user()
    print(f"DAST test user ready: uid={result['uid']} email={result['email']}")
    print(f"DAST_TOKEN={result['id_token']}")


if __name__ == "__main__":
    main()
    sys.exit(0)
