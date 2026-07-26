"""Integration tests for `scripts/seed_dast_user.py` (T9; AC26/DAST-2) against
the REAL Firebase Auth emulator (Operator addendum #1 — no mocked guard) —
the actual account-creation/sign-in logic this script runs, not a smoke
import.
"""

from __future__ import annotations

import pytest

from orbit.config.settings import get_settings
from scripts.seed_dast_user import ProductionEnvironmentRefusalError, seed_dast_user

_TEST_EMAIL = "dast-scanner-test@example.com"
_TEST_PASSWORD = "DastScanner123!"
# The emulator ignores this value entirely (it never reaches a real Google
# endpoint) — same rationale as `tests/conftest.py`'s `_EMULATOR_API_KEY`.
_EMULATOR_API_KEY = "fake-api-key"


@pytest.fixture(autouse=True)
def _dast_test_user_env(monkeypatch, firebase_emulator):
    """Point the script at a throwaway (email, password, API key) triple for
    this test module, and force `get_settings()` to re-read the env vars
    this fixture sets (mirrors `conftest.py`'s own `FIREBASE_PROJECT_ID`/
    `DATABASE_URL` cache-clearing precedent)."""
    monkeypatch.setenv("DAST_TEST_USER_EMAIL", _TEST_EMAIL)
    monkeypatch.setenv("DAST_TEST_USER_PASSWORD", _TEST_PASSWORD)
    monkeypatch.setenv("FIREBASE_WEB_API_KEY", _EMULATOR_API_KEY)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_seed_dast_user_creates_the_account_on_first_run(firebase_emulator):
    result = seed_dast_user(emulator_host=firebase_emulator)
    assert result["email"] == _TEST_EMAIL
    assert result["uid"]
    assert result["id_token"]


def test_seed_dast_user_is_idempotent_and_signs_in_on_a_second_run(firebase_emulator):
    """A second run must reuse the SAME account (sign-in), never error on
    Firebase's `EMAIL_EXISTS` — this is what makes re-running the seed script
    on every DAST cycle safe."""
    first = seed_dast_user(emulator_host=firebase_emulator)
    second = seed_dast_user(emulator_host=firebase_emulator)

    assert second["uid"] == first["uid"]
    assert second["id_token"], "the second run must still mint a working token via sign-in"


def test_seed_dast_user_refuses_a_production_environment(monkeypatch, firebase_emulator):
    """DAST-2 requires a NON-production test principal — the script must
    refuse outright rather than silently seeding (or reusing) an account in
    a real production Firebase project."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    get_settings.cache_clear()

    with pytest.raises(ProductionEnvironmentRefusalError):
        seed_dast_user(emulator_host=firebase_emulator)
