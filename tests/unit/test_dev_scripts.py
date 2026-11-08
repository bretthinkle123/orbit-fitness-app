"""Contract tests for scripts/dev/local_aws.py (the host-side local-stack helper)."""

from __future__ import annotations

import pytest
from botocore.exceptions import ClientError

from scripts.dev import local_aws

LOOPBACK_ENV = {"AWS_ENDPOINT_URL": "http://localhost:5001"}
VALID_VALUES = {
    "POSTGRES_USER": "orbit",
    "POSTGRES_DB": "orbit",
    "POSTGRES_PASSWORD": "not-a-real-password-for-tests",
    "ORBIT_DEV_USER_EMAIL": "dev@orbit-fitness.test",
    "ORBIT_DEV_USER_PASSWORD": "Str0ng-dev-pass!",
}


def _write_env(tmp_path, values):
    """Write a .env file from a mapping and return its path."""
    path = tmp_path / ".env.local"
    path.write_text("".join(f"{key}={value}\n" for key, value in values.items()), encoding="utf-8")
    return path


def _problems_for(key, value):
    """Validate VALID_VALUES with one key overridden."""
    return local_aws.validate_env({**VALID_VALUES, key: value})


def test_valid_env_has_no_problems():
    assert local_aws.validate_env(VALID_VALUES) == []


@pytest.mark.parametrize("key", ["POSTGRES_USER", "POSTGRES_DB"])
@pytest.mark.parametrize("bad", ["Orbit", "1orbit", "orb it", "orbit;drop", "a" * 64, ""])
def test_postgres_identifier_contract(key, bad):
    assert _problems_for(key, bad)


@pytest.mark.parametrize("good", ["_o", "orbit_db1", "a" * 63])
def test_postgres_identifier_accepts_boundary_values(good):
    assert _problems_for("POSTGRES_DB", good) == []


@pytest.mark.parametrize("bad", ["a" * 15, "has space in it 123456", "p@ss/word:1234567890", "x" * 129])
def test_postgres_password_contract(bad):
    assert _problems_for("POSTGRES_PASSWORD", bad)


@pytest.mark.parametrize("good", ["a" * 16, "A-b_9" * 25 + "abc"])
def test_postgres_password_boundaries(good):
    assert _problems_for("POSTGRES_PASSWORD", good) == []


@pytest.mark.parametrize("bad", ["no-at-sign", "a@b", "a@b.c", "@x.test", "a b@x.test", "a@x.test\n"])
def test_dev_email_contract(bad):
    assert _problems_for("ORBIT_DEV_USER_EMAIL", bad)


def test_dev_email_over_254_characters_is_refused():
    long_email = f"{'x' * 64}@{'.'.join(['b' * 63] * 3)}.{'c' * 60}.test"
    assert len(long_email) > 254
    # The shape alone is valid, so only the explicit length cap can be what refuses it.
    assert local_aws._ENV_CONTRACT["ORBIT_DEV_USER_EMAIL"].fullmatch(long_email)
    assert _problems_for("ORBIT_DEV_USER_EMAIL", long_email)


@pytest.mark.parametrize("bad", ["short-pass", "has space 123456789", "x" * 129, "tab\there12345"])
def test_dev_password_contract(bad):
    assert _problems_for("ORBIT_DEV_USER_PASSWORD", bad)


@pytest.mark.parametrize("key", ["POSTGRES_PASSWORD", "ORBIT_DEV_USER_PASSWORD"])
def test_sentinel_refused(key):
    problems = _problems_for(key, "CHANGE_ME")
    assert any(key in problem and "CHANGE_ME" in problem and "openssl rand" in problem for problem in problems)


def test_missing_key_is_reported():
    values = dict(VALID_VALUES)
    del values["POSTGRES_DB"]
    assert any("POSTGRES_DB" in problem for problem in local_aws.validate_env(values))


def test_problem_messages_never_echo_the_value():
    secret_value = "bad value with SECRETTOKEN!"
    problems = _problems_for("POSTGRES_PASSWORD", secret_value)
    assert problems and all("SECRETTOKEN" not in problem for problem in problems)


def test_parse_rejects_unknown_key(tmp_path):
    path = _write_env(tmp_path, {**VALID_VALUES, "AWS_SECRET_ACCESS_KEY": "x"})
    with pytest.raises(local_aws.EnvFileError, match="not allowed"):
        local_aws.parse_env_file(path)


def test_parse_rejects_duplicate_key(tmp_path):
    path = tmp_path / ".env.local"
    path.write_text("POSTGRES_DB=a\nPOSTGRES_DB=b\n", encoding="utf-8")
    with pytest.raises(local_aws.EnvFileError, match="repeated"):
        local_aws.parse_env_file(path)


@pytest.mark.parametrize("line", ["export POSTGRES_DB=orbit", "POSTGRES_DB = orbit", "just words", "$(id)"])
def test_parse_rejects_non_strict_lines(tmp_path, line):
    path = tmp_path / ".env.local"
    path.write_text(line + "\n", encoding="utf-8")
    with pytest.raises(local_aws.EnvFileError):
        local_aws.parse_env_file(path)


def test_parse_does_not_expand_or_unquote(tmp_path):
    path = tmp_path / ".env.local"
    path.write_text("# comment\n\nPOSTGRES_USER=$HOME\nPOSTGRES_DB='orbit'\n", encoding="utf-8")
    parsed = local_aws.parse_env_file(path)
    assert parsed == {"POSTGRES_USER": "$HOME", "POSTGRES_DB": "'orbit'"}
    assert local_aws.validate_env({**VALID_VALUES, **parsed})


def test_validate_env_command_exit_codes(tmp_path):
    good = _write_env(tmp_path, VALID_VALUES)
    assert local_aws.main(["validate-env", "--env-file", str(good)], LOOPBACK_ENV) == 0
    bad = _write_env(tmp_path, {**VALID_VALUES, "POSTGRES_PASSWORD": "CHANGE_ME"})
    assert local_aws.main(["validate-env", "--env-file", str(bad)], LOOPBACK_ENV) == 2


def test_validate_env_command_names_key_not_value(tmp_path, capsys):
    path = _write_env(tmp_path, {**VALID_VALUES, "POSTGRES_PASSWORD": "short SECRETTOKEN"})
    local_aws.main(["validate-env", "--env-file", str(path)], LOOPBACK_ENV)
    stderr = capsys.readouterr().err
    assert "POSTGRES_PASSWORD" in stderr and "SECRETTOKEN" not in stderr


@pytest.mark.parametrize(
    "endpoint",
    ["", "https://localhost:5001", "http://example.com:5001", "http://localhost.evil.com:5001",
     "http://localhost:5001/", "http://localhost", "http://127.0.0.1:1", "http://moto:5000",
     "http://localhost:5001\nhttp://evil"],
)
def test_loopback_guard_refuses_other_endpoints(endpoint):
    with pytest.raises(SystemExit) as exit_info:
        local_aws._require_loopback_endpoint({"AWS_ENDPOINT_URL": endpoint})
    assert exit_info.value.code == 2


def test_loopback_guard_refuses_when_unset():
    with pytest.raises(SystemExit) as exit_info:
        local_aws._require_loopback_endpoint({})
    assert exit_info.value.code == 2


@pytest.mark.parametrize("endpoint", ["http://localhost:5001", "http://127.0.0.1:5001"])
def test_loopback_guard_accepts_loopback(endpoint):
    assert local_aws._require_loopback_endpoint({"AWS_ENDPOINT_URL": endpoint}) == endpoint


def test_guard_runs_before_any_boto3_client_is_built(monkeypatch):
    def fail_if_called(*args, **kwargs):
        raise AssertionError("boto3.client was called before the endpoint guard")

    monkeypatch.setattr(local_aws.boto3, "client", fail_if_called)
    with pytest.raises(SystemExit) as exit_info:
        local_aws.main(["ensure-state-backend"], {"AWS_ENDPOINT_URL": "https://s3.amazonaws.com"})
    assert exit_info.value.code == 2


def test_subcommand_allowlist_rejects_unknown_commands(capsys):
    for command in ("delete-everything", "put-secret", "ensure-state-backend; rm -rf /"):
        with pytest.raises(SystemExit) as exit_info:
            local_aws.main([command], LOOPBACK_ENV)
        assert exit_info.value.code == 2
    assert "invalid choice" in capsys.readouterr().err


def test_missing_subcommand_exits_2():
    with pytest.raises(SystemExit) as exit_info:
        local_aws.main([], LOOPBACK_ENV)
    assert exit_info.value.code == 2


class _FakeS3:
    """In-memory stand-in for the S3 calls ensure_state_backend makes."""

    def __init__(self):
        self.bucket_exists = False
        self.versioning = None
        self.encryption = None
        self.calls = []

    def _missing(self, code, operation):
        return ClientError({"Error": {"Code": code, "Message": "x"}}, operation)

    def head_bucket(self, Bucket):
        if not self.bucket_exists:
            raise self._missing("404", "HeadBucket")

    def create_bucket(self, Bucket, **kwargs):
        assert "CreateBucketConfiguration" not in kwargs  # us-east-1 forbids a LocationConstraint
        self.calls.append("create_bucket")
        self.bucket_exists = True

    def get_bucket_versioning(self, Bucket):
        return {"Status": self.versioning} if self.versioning else {}

    def put_bucket_versioning(self, Bucket, VersioningConfiguration):
        self.calls.append("put_bucket_versioning")
        self.versioning = VersioningConfiguration["Status"]

    def get_bucket_encryption(self, Bucket):
        if self.encryption is None:
            raise self._missing("ServerSideEncryptionConfigurationNotFoundError", "GetBucketEncryption")
        return {"ServerSideEncryptionConfiguration": self.encryption}

    def put_bucket_encryption(self, Bucket, ServerSideEncryptionConfiguration):
        self.calls.append("put_bucket_encryption")
        self.encryption = ServerSideEncryptionConfiguration


def test_ensure_state_backend_creates_then_is_a_no_op():
    fake = _FakeS3()
    first = local_aws.ensure_state_backend(fake)
    assert first == ["created bucket", "enabled versioning", "enabled default encryption"]
    assert fake.versioning == "Enabled"
    assert fake.encryption["Rules"][0]["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"] == "AES256"
    calls_after_first = list(fake.calls)
    assert local_aws.ensure_state_backend(fake) == []
    assert fake.calls == calls_after_first


def test_ensure_state_backend_propagates_unexpected_errors():
    class Denied(_FakeS3):
        def head_bucket(self, Bucket):
            raise self._missing("403", "HeadBucket")

    with pytest.raises(ClientError):
        local_aws.ensure_state_backend(Denied())


def test_ensure_state_backend_creates_no_dynamodb(monkeypatch):
    requested_services = []
    fake = _FakeS3()

    def record_client(service_name, **kwargs):
        requested_services.append(service_name)
        assert kwargs["endpoint_url"] == "http://localhost:5001"
        assert kwargs["aws_access_key_id"] == "test"
        return fake

    monkeypatch.setattr(local_aws.boto3, "client", record_client)
    assert local_aws.main(["ensure-state-backend"], LOOPBACK_ENV) == 0
    assert requested_services == ["s3"]


def test_ensure_state_backend_report_is_one_machine_readable_line(monkeypatch, capsys):
    """The contract dev-up.sh parses (code-review #9): stdout is exactly state_bucket_created=1|0."""
    fake = _FakeS3()
    monkeypatch.setattr(local_aws.boto3, "client", lambda service_name, **kwargs: fake)

    assert local_aws.main(["ensure-state-backend", "--report"], LOOPBACK_ENV) == 0
    first = capsys.readouterr()
    assert first.out == "state_bucket_created=1\n"
    assert "orbit-local-tfstate" in first.err  # the human summary moves to stderr

    assert local_aws.main(["ensure-state-backend", "--report"], LOOPBACK_ENV) == 0
    assert capsys.readouterr().out == "state_bucket_created=0\n"


def test_ensure_state_backend_report_is_0_when_only_settings_were_repaired(monkeypatch, capsys):
    """Only a created bucket means moto was reset; re-enabling versioning on a kept bucket does not."""
    fake = _FakeS3()
    fake.bucket_exists = True
    monkeypatch.setattr(local_aws.boto3, "client", lambda service_name, **kwargs: fake)
    assert local_aws.main(["ensure-state-backend", "--report"], LOOPBACK_ENV) == 0
    assert capsys.readouterr().out == "state_bucket_created=0\n"
    assert fake.calls == ["put_bucket_versioning", "put_bucket_encryption"]


def test_ensure_state_backend_without_report_keeps_the_human_summary_on_stdout(monkeypatch, capsys):
    """CI's local-stack job calls it with no flag; that output is unchanged."""
    monkeypatch.setattr(local_aws.boto3, "client", lambda service_name, **kwargs: _FakeS3())
    assert local_aws.main(["ensure-state-backend"], LOOPBACK_ENV) == 0
    assert capsys.readouterr().out == (
        "state bucket orbit-local-tfstate: created bucket, enabled versioning, enabled default encryption\n"
    )


def test_redact_dsn_hides_the_password_only():
    dsn = "postgresql+asyncpg://orbit:s3cretpassword1234@postgres:5432/orbit"
    redacted = local_aws._redact_dsn(dsn)
    assert redacted == "postgresql+asyncpg://orbit:***@postgres:5432/orbit"
    assert "s3cretpassword1234" not in redacted


def test_redact_dsn_leaves_a_dsn_without_credentials_alone():
    assert local_aws._redact_dsn("postgresql://postgres:5432/orbit") == "postgresql://postgres:5432/orbit"


def test_build_database_dsn_uses_the_container_network_host():
    dsn = local_aws.build_database_dsn(VALID_VALUES)
    assert dsn == "postgresql+asyncpg://orbit:not-a-real-password-for-tests@postgres:5432/orbit"


class _FakeSecretsManager:
    """Records put_secret_value calls."""

    def __init__(self):
        self.puts = []

    def put_secret_value(self, SecretId, SecretString):
        self.puts.append((SecretId, SecretString))


def test_seed_secrets_writes_the_dsn_and_prints_only_the_redacted_form(tmp_path, monkeypatch, capsys):
    fake = _FakeSecretsManager()
    requested = []

    def record_client(service_name, **kwargs):
        requested.append(service_name)
        return fake

    monkeypatch.setattr(local_aws.boto3, "client", record_client)
    path = _write_env(tmp_path, VALID_VALUES)
    assert local_aws.main(["seed-secrets", "--env-file", str(path)], LOOPBACK_ENV) == 0
    assert requested == ["secretsmanager"]
    assert fake.puts == [("orbit/database-url", "postgresql+asyncpg://orbit:not-a-real-password-for-tests@postgres:5432/orbit")]
    output = capsys.readouterr()
    assert "not-a-real-password-for-tests" not in output.out + output.err
    assert "orbit:***@postgres" in output.out


def test_seed_secrets_refuses_an_invalid_env_file_before_building_a_client(tmp_path, monkeypatch):
    def fail_if_called(*args, **kwargs):
        raise AssertionError("client built despite an invalid env file")

    monkeypatch.setattr(local_aws.boto3, "client", fail_if_called)
    path = _write_env(tmp_path, {**VALID_VALUES, "POSTGRES_PASSWORD": "CHANGE_ME"})
    assert local_aws.main(["seed-secrets", "--env-file", str(path)], LOOPBACK_ENV) == 2


# --- scripts/seed_dev_data.py ---------------------------------------------------------------

import datetime  # noqa: E402
import json  # noqa: E402

import requests  # noqa: E402

from scripts import seed_dev_data  # noqa: E402

TODAY = datetime.date(2026, 10, 20)
NOW = datetime.datetime(2026, 10, 20, 12, 0, tzinfo=datetime.timezone.utc)


@pytest.mark.parametrize(
    "api_base",
    ["", "https://localhost:8080", "http://example.com:8080", "http://localhost", "http://localhost:8080/", "http://10.0.0.5:8080"],
)
def test_seed_api_base_guard_refuses_non_loopback(api_base):
    with pytest.raises(SystemExit) as exit_info:
        seed_dev_data.require_loopback_api_base(api_base)
    assert exit_info.value.code == 2


@pytest.mark.parametrize("api_base", ["http://localhost:8080", "http://127.0.0.1:8080"])
def test_seed_api_base_guard_accepts_loopback(api_base):
    assert seed_dev_data.require_loopback_api_base(api_base) == api_base


@pytest.mark.parametrize("host", ["", "example.com:9100", "localhost", "http://localhost:9100", "10.1.1.1:9100", "localhost:9100/x"])
def test_seed_emulator_host_guard_refuses_non_loopback(host):
    with pytest.raises(SystemExit) as exit_info:
        seed_dev_data.require_loopback_emulator_host(host)
    assert exit_info.value.code == 2


@pytest.mark.parametrize("host", ["localhost:9100", "127.0.0.1:9100"])
def test_seed_emulator_host_guard_accepts_loopback(host):
    assert seed_dev_data.require_loopback_emulator_host(host) == host


def test_seed_env_validation_names_the_key_and_never_echoes_the_value(tmp_path, capsys):
    path = _write_env(tmp_path, {**VALID_VALUES, "ORBIT_DEV_USER_PASSWORD": "short SECRETTOKEN"})
    with pytest.raises(SystemExit) as exit_info:
        seed_dev_data.load_dev_user_credentials(path)
    assert exit_info.value.code == 2
    err = capsys.readouterr().err
    assert "ORBIT_DEV_USER_PASSWORD" in err and "SECRETTOKEN" not in err


def test_seed_env_validation_returns_only_the_dev_user_credentials(tmp_path):
    path = _write_env(tmp_path, VALID_VALUES)
    assert seed_dev_data.load_dev_user_credentials(path) == ("dev@orbit-fitness.test", "Str0ng-dev-pass!")


def _emulator_response(status_code: int, body: object) -> requests.Response:
    """A real requests.Response; a bytes body is sent as-is, anything else as JSON."""
    response = requests.Response()
    response.status_code = status_code
    response._content = body if isinstance(body, bytes) else json.dumps(body).encode()
    response.encoding = "utf-8"
    response.url = "http://localhost:9100/identitytoolkit.googleapis.com/v1/accounts:x"
    return response


@pytest.fixture
def emulator(monkeypatch):
    """Script the emulator's answers in order; records the accounts:<action> each call hit."""
    script: list[requests.Response] = []
    actions: list[str] = []

    def fake_post(url, **kwargs):
        actions.append(url.rsplit(":", 1)[1])
        return script.pop(0)

    monkeypatch.setattr(seed_dev_data.requests, "post", fake_post)
    return script, actions


_SIGNED_IN = {"localId": "uid-1", "idToken": "token-1"}


def test_sign_up_returns_the_new_users_uid_and_token(emulator):
    script, actions = emulator
    script.append(_emulator_response(200, _SIGNED_IN))
    assert seed_dev_data.sign_up_or_sign_in("localhost:9100", "dev@orbit-fitness.test", "pw") == ("uid-1", "token-1")
    assert actions == ["signUp"]


def test_an_existing_email_falls_back_to_sign_in(emulator):
    script, actions = emulator
    script.extend([_emulator_response(400, {"error": {"message": "EMAIL_EXISTS"}}), _emulator_response(200, _SIGNED_IN)])
    assert seed_dev_data.sign_up_or_sign_in("localhost:9100", "dev@orbit-fitness.test", "pw") == ("uid-1", "token-1")
    assert actions == ["signUp", "signInWithPassword"]


@pytest.mark.parametrize(
    ("status_code", "body"),
    [(502, b"<html>Bad Gateway</html>"), (500, b""), (400, b"not json at all")],
)
def test_a_non_json_error_body_surfaces_as_the_http_error(emulator, status_code, body):
    """Code-review #6: the status is checked before the body is parsed."""
    script, actions = emulator
    script.append(_emulator_response(status_code, body))
    with pytest.raises(requests.HTTPError) as error_info:
        seed_dev_data.sign_up_or_sign_in("localhost:9100", "dev@orbit-fitness.test", "pw")
    assert error_info.value.response.status_code == status_code
    assert actions == ["signUp"]


@pytest.mark.parametrize("body", [{"error": {"message": "WEAK_PASSWORD"}}, ["EMAIL_EXISTS"], {"error": "EMAIL_EXISTS"}])
def test_a_400_other_than_email_exists_raises_without_signing_in(emulator, body):
    script, actions = emulator
    script.append(_emulator_response(400, body))
    with pytest.raises(requests.HTTPError):
        seed_dev_data.sign_up_or_sign_in("localhost:9100", "dev@orbit-fitness.test", "pw")
    assert actions == ["signUp"]


def test_email_exists_on_a_non_400_status_is_still_an_error(emulator):
    script, actions = emulator
    script.append(_emulator_response(500, {"error": {"message": "EMAIL_EXISTS"}}))
    with pytest.raises(requests.HTTPError):
        seed_dev_data.sign_up_or_sign_in("localhost:9100", "dev@orbit-fitness.test", "pw")
    assert actions == ["signUp"]


class _FakeApi:
    """Records calls; `state` decides what the GETs report."""

    def __init__(self, fuel_entries=0, done_sets=0, weight_for_today=False):
        self.fuel_entries, self.done_sets, self.weight_for_today = fuel_entries, done_sets, weight_for_today
        self.posts = []

    def get(self, path, params=None):
        if path == "/fuel":
            return {"meals": {"breakfast": [{}] * self.fuel_entries, "lunch": [], "snacks": [], "dinner": []}}
        if path == "/catalog/quick-foods":
            return [{"id": 1}, {"id": 2}, {"id": 3}]
        if path == "/train":
            return {"exercises": [{"id": 10, "sets": 3, "done_set_indexes": list(range(self.done_sets))}]}
        if path == "/weight":
            return {"entries": [{"day_key": TODAY.isoformat()}] if self.weight_for_today else []}
        raise AssertionError(path)

    def post(self, path, body=None):
        self.posts.append((path, body))
        return {}


def test_seed_demo_data_inserts_everything_into_an_empty_account():
    api = _FakeApi()
    seed_dev_data.seed_demo_data(api, TODAY, NOW)
    paths = [path for path, _ in api.posts]
    assert paths == ["/me/bootstrap", "/fuel/entries", "/fuel/entries", "/train/sets", "/train/sets", "/weight"]
    assert api.posts[1][1]["quick_food_id"] == 1 and api.posts[2][1]["quick_food_id"] == 2
    assert all(body["day_key"] == "2026-10-20" for path, body in api.posts if path != "/me/bootstrap")


def test_seed_demo_data_is_check_before_insert_on_a_seeded_account():
    api = _FakeApi(fuel_entries=2, done_sets=2, weight_for_today=True)
    seed_dev_data.seed_demo_data(api, TODAY, NOW)
    assert [path for path, _ in api.posts] == ["/me/bootstrap"]  # bootstrap is itself idempotent


def test_seed_demo_data_fills_only_the_missing_parts():
    api = _FakeApi(fuel_entries=1, done_sets=0, weight_for_today=True)
    seed_dev_data.seed_demo_data(api, TODAY, NOW)
    assert [path for path, _ in api.posts] == ["/me/bootstrap", "/train/sets", "/train/sets"]


def test_a_weight_entry_for_another_day_does_not_count_as_today():
    class OtherDayWeight(_FakeApi):
        def get(self, path, params=None):
            if path == "/weight":
                return {"entries": [{"day_key": "2026-10-19"}]}
            return super().get(path, params)

    api = OtherDayWeight(fuel_entries=1, done_sets=2)
    seed_dev_data.seed_demo_data(api, TODAY, NOW)
    assert [path for path, _ in api.posts] == ["/me/bootstrap", "/weight"]
