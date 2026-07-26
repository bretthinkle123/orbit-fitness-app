"""Security-headers middleware (`api-edge-conventions`) — set on every
response, including errors. A JSON-only API that never serves browser HTML
still sends `nosniff` and the tightest CSP (`default-src 'none'`)."""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

SECURITY_HEADERS = {
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
    "Content-Security-Policy": "default-src 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=()",
}


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Registered as the outermost layer (`main.py`) so error responses from
    every inner layer carry these headers too."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        for name, value in SECURITY_HEADERS.items():
            response.headers.setdefault(name, value)
        return response
