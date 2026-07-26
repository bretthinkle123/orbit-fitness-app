"""Error-envelope facade (`api-edge-conventions`) — the single response
shape for every error: `{"error": {"code", "message", "requestId"}}`. No
route builds its own error response; handlers/dependencies `raise
HTTPException` (or let a DB constraint violation propagate) and
`install_error_handlers` maps it centrally. Internal exceptions become a
generic `500 internal`; nothing server-side (stack, SQL, exception type,
file path) ever reaches the client.
"""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from ..logging import get_logger

_CODE_BY_STATUS = {
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    409: "conflict",
    422: "validation_failed",
    429: "rate_limited",
}

# Postgres SQLSTATE -> (error code, HTTP status). A DB constraint violation
# always maps to a 4xx here, never a 500 (plan's "constraint -> 4xx not 500"
# acceptance shape) — asyncpg exposes `.sqlstate` on the driver exception
# SQLAlchemy wraps as `IntegrityError.orig`.
_SQLSTATE_TO_ERROR = {
    "23505": ("conflict", 409),  # unique_violation
    "23514": ("validation_failed", 422),  # check_violation
    "23503": ("not_found", 404),  # foreign_key_violation
    "23502": ("validation_failed", 422),  # not_null_violation
}
_DEFAULT_CONSTRAINT_ERROR = ("validation_failed", 422)


def classify_integrity_error(exc: IntegrityError) -> tuple[str, int]:
    """Map a DB constraint violation to a stable error code + 4xx status.

    Reads the underlying driver's SQLSTATE rather than string-matching the
    exception message (message text is not a stable API across drivers).
    """
    sqlstate = getattr(getattr(exc, "orig", None), "sqlstate", None)
    return _SQLSTATE_TO_ERROR.get(sqlstate, _DEFAULT_CONSTRAINT_ERROR)


def build_error_response(
    code: str,
    message: str,
    request: Request,
    status: int,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    """Build the one response shape every error path returns. Public so
    ASGI-level middleware that can't rely on FastAPI's exception-handler
    dispatch (`edge/ratelimit.py`'s Tier-1 throttle) still produces the same
    envelope. `requestId` echoes `request.state.request_id` (set by
    `logging`'s `request_logger`) so a user report ties to a server log line.
    """
    body = {
        "error": {
            "code": code,
            "message": message,
            "requestId": getattr(request.state, "request_id", None),
        }
    }
    return JSONResponse(body, status_code=status, headers=headers)


async def _handle_http_exception(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    """Central mapping for every deliberately-raised `HTTPException` (auth
    denials, rate limits, not-found, etc.) to the shared envelope shape."""
    code = _CODE_BY_STATUS.get(exc.status_code, "error")
    headers = dict(exc.headers) if exc.headers else None
    return build_error_response(code, str(exc.detail), request, exc.status_code, headers)


async def _handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    """FastAPI/Pydantic request validation failures — logged at `warn`
    (validation failures are a reliable attack signal, `logging-conventions`)
    without echoing the raw input value, only the field path and error type."""
    error_summary = [{"loc": list(error["loc"]), "type": error["type"]} for error in exc.errors()]
    get_logger().warning(
        "validation failed",
        operation=f"{request.method} {request.url.path}",
        errors=error_summary,
    )
    return build_error_response("validation_failed", "The request failed validation.", request, 422)


async def _handle_integrity_error(request: Request, exc: IntegrityError) -> JSONResponse:
    """Every DB constraint violation maps to a 4xx here — never a 500."""
    code, status = classify_integrity_error(exc)
    get_logger().warning(
        "db constraint violation",
        operation=f"{request.method} {request.url.path}",
        code=code,
    )
    return build_error_response(code, "The request violates a data constraint.", request, status)


class UnhandledExceptionEnvelopeMiddleware(BaseHTTPMiddleware):
    """Last-resort catch for any exception not covered by a registered
    handler above (FastAPI's `HTTPException`/`RequestValidationError`/
    `IntegrityError` handlers only intercept exceptions that bubble up
    through the router's own exception middleware — anything else surfaces
    here). Logs the full detail server-side (`exc_info=True`) and returns a
    generic, detail-free 500 — this is what makes the "safe-error" /
    fail-closed acceptance shape true for an unanticipated failure."""

    async def dispatch(self, request: Request, call_next):
        try:
            return await call_next(request)
        except Exception:
            get_logger().error(
                "unhandled exception",
                operation=f"{request.method} {request.url.path}",
                exc_info=True,
            )
            return build_error_response("internal", "An unexpected error occurred.", request, 500)


def install_error_handlers(app: FastAPI) -> None:
    """Register the centralized error-envelope handlers + the last-resort
    middleware. Call once at app construction (`main.py`)."""
    app.add_exception_handler(StarletteHTTPException, _handle_http_exception)
    app.add_exception_handler(RequestValidationError, _handle_validation_error)
    app.add_exception_handler(IntegrityError, _handle_integrity_error)
    app.add_middleware(UnhandledExceptionEnvelopeMiddleware)
