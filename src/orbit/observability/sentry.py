"""Sentry facade — thin, release-tagged error-tracking init.

Full SLO/alarm/synthetics wiring is a deploy-time concern deferred with the
compute topology (`observability-conventions`); this run ships just enough to
tag captured errors with the release and environment. `init_sentry()` is a
no-op when `SENTRY_DSN` is unset so local dev and CI never need a live Sentry
project to boot the app (mirrors the `/health` no-external-deps contract).
"""

import sentry_sdk

from ..config.settings import get_settings


def init_sentry() -> None:
    """Initialize the Sentry SDK once at app startup, tagged with the
    deployed release and environment. Does nothing if no DSN is configured."""
    settings = get_settings()
    if not settings.sentry_dsn:
        return
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.environment,
        release=settings.release_version,
        # Set EXPLICITLY, not left to the SDK default: keeps request bodies,
        # cookies, headers and client IPs out of every captured event, so the
        # Sentry sink honors the same "no PII/secret leaves the process"
        # contract the structlog facade enforces for app logs
        # (plan.md STRIDE "Info Disclosure | logs"). A future SDK default
        # flip cannot silently start shipping PII.
        send_default_pii=False,
        # Full tracing sample rate is an observability-conventions deploy-time
        # decision; keep capture-only (errors) at this stage.
        traces_sample_rate=0.0,
    )
