"""Integration tests for the edge middleware stack:

- security headers present on every response, including errors (AC18)
- the error-envelope's safe-error / fail-closed shape: an unanticipated
  internal error never leaks a stack trace, exception type, or message (AC18)
- the rate limiter fails OPEN with a `warning` log when Redis is
  unreachable, and `/health` never touches Redis at all (Operator addendum #2)
"""

import structlog
from structlog.testing import capture_logs

from orbit.edge import ratelimit as ratelimit_module

# capture_logs() disables ALL configured processors by default and applies
# only what is passed via `processors=` (structlog >= 25.5) — reapply
# add_log_level so captured entries carry the `level` field our assertions
# check (see tests/unit/test_logging.py for the same pattern).
_LEVEL_TAGGING_PROCESSOR = [structlog.processors.add_log_level]
from orbit.edge.headers import SECURITY_HEADERS


def test_security_headers_present_on_a_normal_response(client):
    response = client.get("/health")
    assert response.status_code == 200
    for header_name, header_value in SECURITY_HEADERS.items():
        assert response.headers.get(header_name) == header_value


def test_security_headers_present_on_an_error_response(client):
    """Headers must carry through even on a 401 (they are set by the
    outermost middleware layer, wrapping every inner response including
    error-envelope ones)."""
    response = client.post("/me/signout")  # no token -> 401
    assert response.status_code == 401
    for header_name in SECURITY_HEADERS:
        assert header_name in response.headers


def test_unanticipated_internal_error_returns_the_generic_safe_envelope(client, firebase_test_user, monkeypatch):
    """Force a genuine, unanticipated exception (not a deliberate
    `HTTPException`) inside the signout route and confirm: 500, the generic
    envelope shape, and — critically — that neither the exception's type nor
    its message text reaches the client (fails closed, no leak)."""
    distinctive_secret_looking_message = "super-secret-internal-detail-should-never-leak-12345"

    def _boom(owner_uid):
        raise RuntimeError(distinctive_secret_looking_message)

    monkeypatch.setattr("orbit.routes.me.revoke_refresh_tokens", _boom)

    response = client.post(
        "/me/signout", headers={"Authorization": f"Bearer {firebase_test_user['id_token']}"}
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "internal"
    assert distinctive_secret_looking_message not in response.text
    assert "RuntimeError" not in response.text
    assert "Traceback" not in response.text
    assert "requestId" in body["error"]


def test_health_returns_200_even_when_the_rate_limit_store_call_would_raise(client, monkeypatch):
    """`/health` must never touch Redis at all — proven by making the
    counter function itself raise if it's ever called, then confirming
    `/health` still returns 200 (the path-exemption check runs strictly
    before any Redis touch, Operator addendum #2)."""

    async def _fail_if_called(*_args, **_kwargs):
        raise AssertionError("the rate-limit store must never be touched for /health")

    monkeypatch.setattr(ratelimit_module, "_increment_fixed_window", _fail_if_called)

    response = client.get("/health")
    assert response.status_code == 200


def test_a_protected_route_fails_open_with_a_warning_log_when_redis_is_unreachable(
    client, firebase_test_user, monkeypatch
):
    """Operator addendum #2: fail-mode is fail-OPEN (never self-DoS the API
    off a cache outage), and every fail-open is logged at `warning`."""
    monkeypatch.setattr(ratelimit_module, "_redis_client", None)
    # An unreachable host guarantees the connection attempt fails fast.
    monkeypatch.setattr(
        ratelimit_module,
        "get_redis_client",
        lambda: ratelimit_module.redis_asyncio.from_url(
            "redis://127.0.0.1:1/0", decode_responses=True, socket_connect_timeout=1
        ),
    )

    with capture_logs(processors=_LEVEL_TAGGING_PROCESSOR) as captured:
        response = client.post(
            "/me/signout", headers={"Authorization": f"Bearer {firebase_test_user['id_token']}"}
        )

    assert response.status_code == 204, "a Redis outage must never block the request (fail open)"
    fail_open_events = [entry for entry in captured if "failing open" in entry.get("event", "")]
    assert len(fail_open_events) >= 1
    assert all(entry["level"] == "warning" for entry in fail_open_events)
