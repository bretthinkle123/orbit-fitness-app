"""AC10: the unchanged secrets facade reads from a moto server reached via AWS_ENDPOINT_URL.

This is the local stack's whole premise: pointing boto3 at moto with environment variables is
enough for `get_secret` and `resolve_database_url` to behave as they do in deploy, with no
branch in the app. The moto image is parsed from docker-compose.yml so the test and the stack
can never drift to different versions.
"""

from __future__ import annotations

import re
import time
from pathlib import Path

import boto3
import pytest
import requests
from testcontainers.core.container import DockerContainer

from orbit.config import secrets as secrets_module
from orbit.config.secrets import SecretNotFoundError, get_secret
from orbit.config.settings import get_settings
from orbit.repositories.base import resolve_database_url

COMPOSE_FILE = Path(__file__).resolve().parents[2] / "docker-compose.yml"
SECRET_NAME = "orbit/database-url"
SECRET_VALUE = "postgresql+asyncpg://orbit:not-a-real-password@postgres:5432/orbit"
MOTO_CONTAINER_PORT = 5000


def _moto_image_from_compose() -> str:
    """The pinned moto image (tag@digest) from the compose file's moto service."""
    moto_block = COMPOSE_FILE.read_text(encoding="utf-8").split("\n  moto:\n", 1)[1]
    match = re.search(r"^    image:\s*(\S+)\s*$", moto_block, re.MULTILINE)
    assert match, "moto service has no image"
    return match.group(1)


def _wait_until_ready(url, timeout_seconds, *, get=requests.get, sleep=time.sleep, clock=time.monotonic) -> bool:
    """Poll url until it answers 200, sleeping 0.5 s after every miss; False once timeout_seconds pass."""
    deadline = clock() + timeout_seconds
    while clock() < deadline:
        try:
            if get(url, timeout=1).status_code == 200:
                return True
        except requests.RequestException:
            pass  # not up yet; a non-200 answer and a refused connection back off alike
        sleep(0.5)
    return False


@pytest.fixture(scope="module")
def moto_endpoint():
    """Start moto from the compose-pinned image and yield its base URL once it answers."""
    container = DockerContainer(_moto_image_from_compose()).with_exposed_ports(MOTO_CONTAINER_PORT)
    with container:
        endpoint = f"http://{container.get_container_host_ip()}:{container.get_exposed_port(MOTO_CONTAINER_PORT)}"
        if not _wait_until_ready(f"{endpoint}/moto-api/", 60):
            pytest.fail("moto did not become ready")
        yield endpoint


@pytest.fixture
def facade_against_moto(moto_endpoint, monkeypatch):
    """Point boto3 at moto purely through environment variables, with clean caches either side."""
    monkeypatch.setenv("AWS_ENDPOINT_URL", moto_endpoint)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    get_settings.cache_clear()
    secrets_module._cache.clear()
    client = boto3.client("secretsmanager", region_name="us-east-1")
    yield client
    secrets_module._cache.clear()
    get_settings.cache_clear()


@pytest.fixture
def stored_secret(facade_against_moto):
    """Create the database-url secret in moto and force-delete it afterwards."""
    facade_against_moto.create_secret(Name=SECRET_NAME, SecretString=SECRET_VALUE)
    yield facade_against_moto
    facade_against_moto.delete_secret(SecretId=SECRET_NAME, ForceDeleteWithoutRecovery=True)


def test_get_secret_returns_the_value_stored_in_moto(stored_secret):
    assert get_secret(SECRET_NAME) == SECRET_VALUE


def test_a_repeat_call_is_served_from_the_ttl_cache(stored_secret):
    assert get_secret(SECRET_NAME) == SECRET_VALUE
    # Deleting the secret proves the second answer cannot have come from moto.
    stored_secret.delete_secret(SecretId=SECRET_NAME, ForceDeleteWithoutRecovery=True)
    assert get_secret(SECRET_NAME) == SECRET_VALUE
    stored_secret.create_secret(Name=SECRET_NAME, SecretString=SECRET_VALUE)  # let the fixture clean up


def test_resolve_database_url_falls_through_to_moto_when_database_url_is_unset(stored_secret):
    assert resolve_database_url() == SECRET_VALUE


def test_database_url_env_var_still_takes_precedence(stored_secret, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://override@localhost/override")
    get_settings.cache_clear()
    assert resolve_database_url() == "postgresql+asyncpg://override@localhost/override"


def test_a_missing_secret_raises_secret_not_found(facade_against_moto):
    with pytest.raises(SecretNotFoundError):
        get_secret("orbit/does-not-exist")


class _ScriptedProbe:
    """Answers the readiness probe from a script (an int status, or None for a refused connection).

    The clock moves 0.01 s per request as well as on sleep, so a loop that never sleeps still
    reaches its deadline and the test fails instead of hanging.
    """

    def __init__(self, answers, then=503):
        self.answers, self.then = list(answers), then
        self.now, self.requests, self.sleeps = 0.0, 0, []

    def get(self, url, timeout):
        self.requests += 1
        self.now += 0.01
        answer = self.answers.pop(0) if self.answers else self.then
        if answer is None:
            raise requests.ConnectionError("connection refused")
        return type("Response", (), {"status_code": answer})()

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds

    def clock(self):
        return self.now


def test_the_readiness_wait_backs_off_after_a_non_200_answer_too():
    """Code-review #5: a 503 must be followed by a sleep, exactly like a refused connection."""
    probe = _ScriptedProbe([503, 503, None, 200])
    assert _wait_until_ready("http://moto/moto-api/", 60, get=probe.get, sleep=probe.sleep, clock=probe.clock)
    assert probe.requests == 4
    assert probe.sleeps == [0.5, 0.5, 0.5]


def test_the_readiness_wait_gives_up_at_the_deadline_without_spinning():
    probe = _ScriptedProbe([], then=503)
    assert not _wait_until_ready("http://moto/moto-api/", 5, get=probe.get, sleep=probe.sleep, clock=probe.clock)
    assert probe.requests <= 10  # one probe per 0.5 s sleep over 5 s, not one per 0.01 s request
