"""Unit tests for the crypto facade's `hash_uid` — the one-way hash the
logging facade uses so a Firebase UID never reaches a log verbatim."""

from orbit.crypto import hash_uid


def test_hash_uid_is_deterministic_and_never_returns_the_raw_input():
    """Same input hashes to the same output, and the raw uid never leaks
    through as a substring of its own hash."""
    owner_uid = "firebase-uid-abc123"

    first = hash_uid(owner_uid)
    second = hash_uid(owner_uid)

    assert first == second
    assert owner_uid not in first


def test_hash_uid_differs_for_different_inputs():
    """Two distinct uids must not collide onto the same hash."""
    assert hash_uid("uid-one") != hash_uid("uid-two")
