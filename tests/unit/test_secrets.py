"""Unit tests for the secrets facade (T1 test slice: "raises-on-missing +
facade-is-only-caller")."""

from pathlib import Path

import pytest
from botocore.exceptions import ClientError

from orbit.config import secrets as secrets_module
from orbit.config.secrets import SecretNotFoundError, get_secret


class _FakeMissingSecretClient:
    """Stands in for the Secrets Manager client and raises the same
    ClientError shape AWS returns for an absent secret."""

    def get_secret_value(self, SecretId: str):  # noqa: N803 - matches boto3's kwarg casing
        raise ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "no such secret"}},
            "GetSecretValue",
        )


class _FakePresentSecretClient:
    """Stands in for the Secrets Manager client and returns a fixed value."""

    def __init__(self, value: str):
        self._value = value
        self.calls = 0

    def get_secret_value(self, SecretId: str):  # noqa: N803
        self.calls += 1
        return {"SecretString": self._value}


def test_get_secret_raises_when_the_store_has_no_such_secret(monkeypatch):
    """The facade fails loudly rather than falling back to a default."""
    monkeypatch.setattr(secrets_module, "_secrets_manager_client", _FakeMissingSecretClient)

    with pytest.raises(SecretNotFoundError):
        get_secret("does-not-exist")


def test_get_secret_returns_and_caches_a_present_value(monkeypatch):
    """A found secret is returned, and a second call within the TTL window
    hits the cache rather than the store again."""
    fake_client = _FakePresentSecretClient("db-password-value")
    monkeypatch.setattr(secrets_module, "_secrets_manager_client", lambda: fake_client)
    secrets_module._cache.clear()

    first = get_secret("db-url")
    second = get_secret("db-url")

    assert first == "db-password-value"
    assert second == "db-password-value"
    assert fake_client.calls == 1


def test_secrets_facade_is_the_only_module_that_imports_boto3():
    """No other module under src/orbit may import boto3 directly — every
    caller routes through `config/secrets.py` (secrets-management)."""
    src_root = Path(__file__).resolve().parents[2] / "src" / "orbit"
    secrets_file = src_root / "config" / "secrets.py"

    offenders = [
        str(path)
        for path in src_root.rglob("*.py")
        if path != secrets_file and "boto3" in path.read_text()
    ]

    assert offenders == []
