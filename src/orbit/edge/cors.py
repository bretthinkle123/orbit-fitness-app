"""CORS facade (`api-edge-conventions`) — an explicit origin allowlist read
through the config facade, never hardcoded and never `*` with credentials.
The app is consumed by a native iOS client, not a browser, so the allowlist
is empty by default; it exists so a future browser-based admin tool (if any)
has one place to widen, not a per-route CORS decision.
"""

from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

from ..config.settings import get_settings


def _parse_allowed_origins(raw: str) -> list[str]:
    """Split the comma-separated `cors_allowed_origins` setting into a list,
    dropping blanks."""
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def register_cors(app: FastAPI) -> None:
    """Register CORS with the configured allowlist. `allow_credentials` is
    only ever true alongside an explicit origin list — never paired with a
    wildcard (the browser rejects that pair anyway, but the app never even
    constructs it)."""
    allowed_origins = _parse_allowed_origins(get_settings().cors_allowed_origins)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=bool(allowed_origins),
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
