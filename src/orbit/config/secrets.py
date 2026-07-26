"""Secrets facade — the ONLY module in the app permitted to call the AWS SDK
for secret material (`secrets-management`). Everything else (the DB engine,
the Firebase Admin client, once those land) asks `get_secret(name)` for a
value; nothing else imports `boto3` for Secrets Manager access.

Bootstrap env holds only the AWS region + secret names/ARNs (see
`config/settings.py`) — never a secret value. Fetched values are cached with
a short TTL so Secrets Manager rotation is adopted without a redeploy, and are
never logged (the logging facade's redaction list also covers this).
"""

import time

import boto3
from botocore.exceptions import ClientError

from .settings import get_settings

# 5-15 minute TTL per secrets-management: long enough to avoid per-request SDK
# calls, short enough that a rotated secret is adopted without a redeploy.
_CACHE_TTL_SECONDS = 900
_cache: dict[str, tuple[str, float]] = {}


class SecretNotFoundError(RuntimeError):
    """Raised when the configured store has no value for the requested secret
    name — callers must fail loudly rather than fall back to a default."""


def _secrets_manager_client():
    """Build a Secrets Manager client scoped to the configured AWS region."""
    return boto3.client("secretsmanager", region_name=get_settings().aws_region)


def get_secret(name: str) -> str:
    """Fetch a secret's current string value by name, cached with a short TTL.

    Raises `SecretNotFoundError` when the store has no such secret — never
    silently substitutes a hardcoded default.
    """
    cached = _cache.get(name)
    now = time.monotonic()
    if cached is not None and now - cached[1] < _CACHE_TTL_SECONDS:
        return cached[0]

    try:
        response = _secrets_manager_client().get_secret_value(SecretId=name)
    except ClientError as error:
        raise SecretNotFoundError(f"secret '{name}' not found in Secrets Manager") from error

    value = response["SecretString"]
    _cache[name] = (value, now)
    return value
