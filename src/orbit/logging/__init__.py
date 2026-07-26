"""structlog facade — the single configured logger for the whole app
(`logging-conventions`).

Every module imports `get_logger()` from here; nothing else calls
`structlog.configure()` or instantiates a second logger. Central redaction
(`_redact`) keeps secrets out of every log line regardless of call site, and
`request_logger` is the ASGI middleware that binds request-scoped fields
(`requestId`, `traceId`) and emits the start/completion pair every request
produces.
"""

import logging
import time
import uuid

import structlog

from ..config.settings import get_settings
from ..crypto import hash_uid

# Field names that must never reach a rendered log line, regardless of which
# call site produced them (defense in depth alongside "never log the value").
_REDACTED_FIELDS = {"authorization", "password", "token", "secret", "api_key", "cookie"}


def _redact(_, __, event_dict):
    """Replace sensitive field values with a marker before rendering."""
    for key in list(event_dict):
        if key.lower() in _REDACTED_FIELDS:
            event_dict[key] = "[REDACTED]"
    return event_dict


def _configure() -> None:
    """Configure the process-wide structlog pipeline. Safe to call more than
    once (idempotent) so tests/app re-imports never double-register."""
    settings = get_settings()
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,  # request-scoped fields
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            _redact,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.getLevelName(settings.log_level.upper())
        ),
        cache_logger_on_first_use=True,
    )


_configure()


def get_logger():
    """Return the configured structlog logger, bound with the service name."""
    return structlog.get_logger(service=get_settings().service_name)


def _trace_id(request) -> str:
    """Resolve the active trace id: the AWS `X-Amzn-Trace-Id` `Root=` segment
    when present (the deployed ALB/X-Ray header), else a generated UUID. Once
    the OTel SDK is wired, the active span's trace id takes priority over
    both (`logging-conventions` traceId resolution order)."""
    header = request.headers.get("x-amzn-trace-id", "")
    for part in header.split(";"):
        if part.startswith("Root="):
            return part[5:]
    return uuid.uuid4().hex


async def request_logger(request, call_next):
    """ASGI middleware: bind `requestId`/`traceId` for the request's lifetime
    and log its start and completion (duration, status, hashed userId)."""
    request_id = str(uuid.uuid4())
    # Exposed on request.state so the (later) error-envelope middleware can
    # echo the same id back to the client.
    request.state.request_id = request_id
    structlog.contextvars.bind_contextvars(request_id=request_id, trace_id=_trace_id(request))

    log = get_logger()
    start = time.monotonic()
    operation = f"{request.method} {request.url.path}"
    log.info("request started", operation=operation)

    response = await call_next(request)

    user = getattr(request.state, "user", None)
    owner_uid = user.get("uid") if isinstance(user, dict) else None
    log.info(
        "request completed",
        operation=operation,
        status_code=response.status_code,
        duration=round((time.monotonic() - start) * 1000),
        user_id=hash_uid(owner_uid) if owner_uid else "anonymous",
    )
    structlog.contextvars.clear_contextvars()
    return response
