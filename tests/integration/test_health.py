"""Integration test: `GET /health` returns 200 with no external dependencies
(no DB, no Firebase, no Redis) reachable — AC1."""


def test_health_returns_200_with_no_external_dependencies(client, monkeypatch):
    """No DB/Firebase/Redis client exists yet in this vertical slice, so this
    test also documents the invariant future tasks must preserve: `/health`
    never touches a downstream dependency."""
    # Belt-and-suspenders: point every future-dependency env var at an
    # unreachable target so a later regression (health handler starts
    # touching Postgres/Firebase/Redis) fails this test immediately.
    monkeypatch.setenv("DATABASE_URL", "postgresql://unreachable-host:1/db")
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "unreachable-host:1")
    monkeypatch.setenv("REDIS_URL", "redis://unreachable-host:1/0")

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
