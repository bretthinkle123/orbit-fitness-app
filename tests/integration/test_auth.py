"""Integration tests for the auth facade against a REAL Firebase Auth
emulator (Operator addendum #1 — no mocked guard for these):

- unauthenticated-access-denied on every current protected route (AC2)
- token validation: expired + wrong-audience both 401 (AC2, AC33)
- session lifecycle (T2-4 / AC34): sign-out revokes the prior token via
  `check_revoked`, and a fresh sign-in mints a working new token
"""

import base64
import json
import time

import pytest

_PROTECTED_ROUTES = [
    ("POST", "/me/bootstrap"),
    ("POST", "/me/signout"),
]


def _b64url_json(payload: dict) -> str:
    """Base64url-encode a dict with no padding, matching JWT segment form."""
    raw = json.dumps(payload).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _forge_token_with_claim_overrides(id_token: str, overrides: dict) -> str:
    """Rebuild an emulator-issued (unsigned, `alg: none`) token with modified
    claims — the emulator never checks a signature, so this reliably
    produces a token with the exact wrong-audience / expired-timestamp shape
    a real client could never legitimately obtain, without needing the
    emulator to run two different projects (which it doesn't support the
    way this test needs)."""
    header_segment, payload_segment, _signature_segment = id_token.split(".")

    def _pad(segment: str) -> str:
        return segment + "=" * (-len(segment) % 4)

    header = json.loads(base64.urlsafe_b64decode(_pad(header_segment)))
    payload = json.loads(base64.urlsafe_b64decode(_pad(payload_segment)))
    payload.update(overrides)
    return f"{_b64url_json(header)}.{_b64url_json(payload)}."


@pytest.mark.parametrize("method,path", _PROTECTED_ROUTES)
def test_protected_route_denies_a_missing_token(client, method, path):
    response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


@pytest.mark.parametrize("method,path", _PROTECTED_ROUTES)
def test_protected_route_denies_a_malformed_authorization_header(client, method, path):
    response = client.request(method, path, headers={"Authorization": "NotBearer whatever"})
    assert response.status_code == 401


@pytest.mark.parametrize("method,path", _PROTECTED_ROUTES)
def test_protected_route_denies_garbage_bearer_token(client, method, path):
    response = client.request(method, path, headers={"Authorization": "Bearer not-a-real-token"})
    assert response.status_code == 401


def test_expired_token_is_denied(client, firebase_test_user):
    """A token whose `exp` is in the past must be rejected 401 regardless of
    which specific verification step catches it."""
    forged = _forge_token_with_claim_overrides(
        firebase_test_user["id_token"],
        {"exp": 1_000_000_000, "iat": 999_999_000},  # deep in the past
    )
    response = client.post("/me/signout", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401


def test_wrong_audience_token_is_denied(client, firebase_test_user):
    """A token minted for a different Firebase project (`aud`/`iss` mismatch)
    must be rejected 401 — the spoofing defense this app relies on."""
    forged = _forge_token_with_claim_overrides(
        firebase_test_user["id_token"],
        {"aud": "some-other-project", "iss": "https://securetoken.google.com/some-other-project"},
    )
    response = client.post("/me/signout", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401


def test_valid_token_is_accepted(client, firebase_test_user):
    """Baseline: an unmodified, freshly-minted token from the emulator is
    accepted (proves the two rejection tests above are testing the claim,
    not an unrelated failure)."""
    response = client.post(
        "/me/signout", headers={"Authorization": f"Bearer {firebase_test_user['id_token']}"}
    )
    assert response.status_code == 204


def test_signout_invalidates_the_old_token_and_a_fresh_signin_mints_a_new_one(
    client, firebase_test_user, firebase_sign_in
):
    """T2-4 / AC34: after `POST /me/signout`, the prior bearer token is
    rejected 401 on its next use (`check_revoked=True`) — not merely
    discarded client-side. A fresh sign-in mints a new, working token
    (rotation on auth, ASVS 7.2.4)."""
    old_token = firebase_test_user["id_token"]

    # Firebase's revocation check compares the token's `iat` against the
    # user's `tokens_valid_after_time` at one-SECOND resolution — revoking
    # in the same wall-clock second the token was minted is a real race
    # (reproduced without this sleep: the "revoked" token was still
    # accepted). A real client's sign-in-to-signout gap is always >1s.
    time.sleep(1.1)

    signout_response = client.post("/me/signout", headers={"Authorization": f"Bearer {old_token}"})
    assert signout_response.status_code == 204

    reuse_response = client.post("/me/signout", headers={"Authorization": f"Bearer {old_token}"})
    assert reuse_response.status_code == 401, "a revoked token must be rejected on its next use"

    fresh_token = firebase_sign_in(firebase_test_user["email"])
    fresh_response = client.post("/me/signout", headers={"Authorization": f"Bearer {fresh_token}"})
    assert fresh_response.status_code == 204, "a fresh sign-in must mint a token that works"
