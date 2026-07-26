"""Configuration facade — the single source of non-secret runtime config.

Every module reads app configuration through `get_settings()`; nothing else
calls `os.environ` directly (secret VALUES never live here — see
`config/secrets.py` for those). Settings are sourced from environment
variables via pydantic-settings, with safe defaults for local development.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Non-secret, process-wide configuration values."""

    model_config = SettingsConfigDict(extra="ignore")

    environment: str = "development"
    service_name: str = "orbit-api"
    log_level: str = "INFO"
    aws_region: str = "us-east-1"
    release_version: str = "0.1.0"
    # Unset locally so Sentry stays inert without a live project (observability/sentry.py).
    sentry_dsn: str | None = None
    # Local/dev/test override for the Postgres DSN (e.g. a testcontainers URL).
    # Unset in deploy, where the engine instead re-resolves the credential
    # through the secrets facade on every physical connection (rotation-aware
    # — see repositories/base.py) using the secret named below.
    database_url: str | None = None
    database_url_secret_name: str = "orbit/database-url"
    # Firebase project id — not a secret (it appears in every ID token's
    # `aud` claim and in the iOS app's public config). The Admin service-
    # account JSON itself IS a secret; see `firebase_admin_credentials_secret_name`.
    firebase_project_id: str = "orbit-fitness"
    firebase_admin_credentials_secret_name: str = "orbit/firebase-admin-credentials"
    # Shared rate-limit store (`edge/ratelimit.py`) — a local Redis in dev,
    # ElastiCache in deploy. Never in-process counters (api-edge-conventions).
    redis_url: str = "redis://localhost:6379/0"
    # Explicit CORS origin allowlist, comma-separated (empty by default — the
    # app is consumed by a native iOS client, not a browser; never "*").
    cors_allowed_origins: str = ""
    # DAST test user (DAST-2/DAST-3 — `dast-conventions`): a low-privilege,
    # non-production Firebase principal `scripts/seed_dast_user.py` creates
    # and the nightly Schemathesis/ZAP scan authenticates as. The email is an
    # identifier, not a secret (same non-sensitive class as `firebase_project_id`
    # above); the password/API-key never have a literal default — local/emulator
    # runs override via the two `*_password`/`*_web_api_key` fields below, deploy
    # fetches both from Secrets Manager via the paired `*_secret_name` fields
    # (mirrors `resolve_database_url()`'s local-override-else-secrets-manager
    # precedent in `repositories/base.py`).
    dast_test_user_email: str = "dast-scanner@orbit-fitness.test"
    dast_test_user_password: str | None = None
    dast_test_user_password_secret_name: str = "orbit/dast-test-user-password"
    firebase_web_api_key: str | None = None
    firebase_web_api_key_secret_name: str = "orbit/firebase-web-api-key"


@lru_cache
def get_settings() -> Settings:
    """Return the cached, process-wide `Settings` instance."""
    return Settings()
