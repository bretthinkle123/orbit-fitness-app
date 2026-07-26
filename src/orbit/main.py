"""Orbit FastAPI application — composition root.

`create_app()` builds the app and registers the edge-middleware stack in one
place (`api-edge-conventions`: outermost -> innermost, registered once at app
construction — never per-route). Starlette applies `add_middleware` calls
LAST-ADDED-OUTERMOST (verified empirically, not assumed), so the calls below
are ordered innermost-first to produce plan.md §Edge-middleware's stated
outer -> inner chain:

    request-ID/trace -> security headers -> CORS -> Tier-1 edge throttle
    -> request-size limit
    -> [FastAPI routing: require_auth -> Tier-2 throttle -> handler],
    with the error-envelope as the innermost ASGI layer (wrapping routing +
    every dependency) so it can catch anything a registered exception
    handler doesn't (`edge/errors.py`).
"""

from fastapi import FastAPI

from .config.settings import get_settings
from .edge.bodysize import RequestSizeLimitMiddleware
from .edge.cors import register_cors
from .edge.errors import install_error_handlers
from .edge.headers import SecurityHeadersMiddleware
from .edge.ratelimit import EdgeThrottleMiddleware
from .logging import request_logger
from .observability.sentry import init_sentry
from .routes.body import router as body_router
from .routes.fuel import router as fuel_router
from .routes.health import router as health_router
from .routes.me import router as me_router
from .routes.profile import router as profile_router
from .routes.train import router as train_router
from .routes.weight import router as weight_router


def create_app() -> FastAPI:
    """Build and configure the Orbit FastAPI application instance."""
    init_sentry()
    settings = get_settings()
    app = FastAPI(title="Orbit API", version=settings.release_version)

    # Innermost first (see module docstring for why this order produces the
    # plan's stated outer->inner chain).
    install_error_handlers(app)  # innermost ASGI layer + the exception-handler registry
    app.add_middleware(RequestSizeLimitMiddleware)  # reject oversized bodies before routing
    app.add_middleware(EdgeThrottleMiddleware)  # Tier-1: pre-auth, IP+route-keyed
    register_cors(app)
    app.add_middleware(SecurityHeadersMiddleware)
    app.middleware("http")(request_logger)  # outermost: request-id/trace

    app.include_router(health_router)
    app.include_router(me_router)
    app.include_router(profile_router)
    app.include_router(fuel_router)
    app.include_router(train_router)
    app.include_router(body_router)
    app.include_router(weight_router)
    return app


app = create_app()
