"""The served OpenAPI schema matches the implemented routes verbatim
(DAST-1, AC26). Schemathesis's fuzz driver (`dast-staging.yml`'s `api-fuzz`
job) only ever visits what the schema documents — a route present in the
app but absent (or mismatched) from the schema is an endpoint DAST silently
never reaches, so this is a real equality assertion between two independently
derived sets, not a reachability smoke check.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from orbit.main import create_app
from orbit.routes import body, fuel, health, me, profile, train, weight

# The ground truth: every (path, HTTP method) pair actually registered, read
# directly from each domain's own `APIRouter.routes` — NOT `app.routes`,
# whose internal representation this FastAPI/Starlette version restructures
# behind a routing-trie wrapper (`_IncludedRouter`) not meant for external
# introspection; each router module's own `.routes` list is the same object
# `main.py::create_app` registers, so it stays authoritative regardless of
# how the assembled app represents it internally.
_ROUTE_MODULES = (health, me, profile, fuel, train, body, weight)


def _implemented_route_pairs() -> set[tuple[str, str]]:
    """Every (path, HTTP method) pair this app actually implements."""
    return {
        (route.path, method)
        for module in _ROUTE_MODULES
        for route in module.router.routes
        for method in route.methods
    }


def test_openapi_schema_paths_match_the_implemented_routes_exactly():
    with TestClient(create_app()) as client:
        response = client.get("/openapi.json")
        assert response.status_code == 200
        schema = response.json()

    schema_pairs = {
        (path, method.upper())
        for path, methods_for_path in schema["paths"].items()
        for method in methods_for_path
    }

    assert schema_pairs == _implemented_route_pairs()
