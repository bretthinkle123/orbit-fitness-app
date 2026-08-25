"""Integration test for the Tier-2 (post-auth, uid-keyed) resource throttle
— the two-principals-one-IP correctness property `api-edge-conventions`
requires: two identities sharing one client IP get INDEPENDENT buckets. This
needs a REAL, reachable Redis (unlike the fail-open tests, which deliberately
use an unreachable store) so actual limiting takes effect.

The `real_redis_client`/`_wire_real_redis_and_tight_tier2_limit` fixtures live
in `tests/conftest.py` (rule-of-two — `tests/integration/test_account_
deletion.py`'s Tier-2-throttle test is the second consumer).
"""

import pytest


@pytest.fixture(autouse=True)
def _tight_tier2_limit(_wire_real_redis_and_tight_tier2_limit):
    """Opt this module into the shared Tier-2-throttle Redis fixture for
    every test in this file (safe as a module-wide autouse here since this
    module's tests each use a single uid making a single Tier-2 call — unlike
    a module that also makes OTHER Tier-2-gated write calls for the same
    uid, where a shared, tightened bucket would starve them)."""
    yield


def test_two_principals_sharing_one_ip_get_independent_tier2_buckets(
    client, firebase_test_user, firebase_second_user
):
    """Principal A exhausts their own (limit=1) Tier-2 bucket; principal B —
    a different Firebase user hitting the SAME TestClient (i.e. the same
    client IP from the app's perspective) — must still succeed. If Tier-2
    were mis-keyed on IP instead of uid, B would also 429 here."""
    token_a = firebase_test_user["id_token"]

    first_call_for_a = client.post("/me/signout", headers={"Authorization": f"Bearer {token_a}"})
    assert first_call_for_a.status_code == 204

    second_call_for_a = client.post("/me/signout", headers={"Authorization": f"Bearer {token_a}"})
    assert second_call_for_a.status_code == 429
    assert "Retry-After" in second_call_for_a.headers
    assert second_call_for_a.json()["error"]["code"] == "rate_limited"

    # A second, distinct principal on the identical TestClient (same "IP").
    token_b = firebase_second_user()["id_token"]

    call_for_b = client.post("/me/signout", headers={"Authorization": f"Bearer {token_b}"})
    assert call_for_b.status_code == 204, "a different principal must not share A's exhausted bucket"
