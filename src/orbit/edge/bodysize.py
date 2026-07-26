"""Request-size limit middleware (`api-edge-conventions`) — the concrete
mechanism plan.md's STRIDE "Denial of Service | request size" row names
("request-size limit middleware + Pydantic bounds").

Pydantic's field bounds only constrain a body the server has ALREADY read and
parsed, so they are not a size defense on their own: an oversized body is
buffered before any schema sees it. This middleware rejects it at the edge,
before the request reaches routing.

There is no load balancer or reverse proxy in front of the app this run (the
compute topology is deferred), so there is no upstream body cap to fall back
on — this is the only one.
"""

from __future__ import annotations

from starlette.requests import Request

from .errors import build_error_response

# Every request body this API accepts is a small JSON document (the largest,
# `PATCH /profile`, is a few hundred bytes). 64 KiB is far above any
# legitimate payload and far below a memory-exhaustion threat.
MAX_BODY_BYTES = 64 * 1024


class RequestSizeLimitMiddleware:
    """Reject a request whose declared `Content-Length` exceeds the cap with a
    `413`, before the body is read or routing happens.

    A PURE ASGI middleware (not `BaseHTTPMiddleware`) for the same reason the
    Tier-1 throttle is: it sits outside FastAPI's exception-handling layer, so
    it BUILDS AND SENDS the shared error envelope directly rather than raising
    `HTTPException` (which would surface as an unmapped 500 from here).

    KNOWN LIMIT: this enforces the DECLARED `Content-Length`. A chunked
    request that omits the header is not capped here — closing that needs a
    streaming byte-counter, or (the usual answer) the ingress/ALB body cap
    that lands with the compute topology. Recorded in security-report.md
    rather than left implicit.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request = Request(scope, receive=receive)
        declared_length = request.headers.get("content-length")
        if declared_length is not None:
            try:
                length = int(declared_length)
            except ValueError:
                # A malformed Content-Length is not a size decision to make
                # here; let the server/router reject it normally.
                length = 0
            if length > MAX_BODY_BYTES:
                response = build_error_response(
                    "payload_too_large",
                    "Request body is too large.",
                    request,
                    413,
                )
                await response(scope, receive, send)
                return

        await self.app(scope, receive, send)
