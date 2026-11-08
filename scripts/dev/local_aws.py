"""Host-side helper for the local stack: validates .env.local and prepares moto.

Not part of the app package (`src/orbit/`); it is ops tooling run from the venv by
the dev scripts. Subcommands are an argparse allowlist, and every one first checks
that AWS_ENDPOINT_URL points at loopback, so nothing here can reach real AWS.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections.abc import Mapping
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

EXIT_USAGE = 2

STATE_BUCKET_NAME = "orbit-local-tfstate"
STATE_REGION = "us-east-1"

CREATED_BUCKET_ACTION = "created bucket"
# The one line `ensure-state-backend --report` prints on stdout, parsed by dev-up.sh: 1 means the
# bucket had to be created, i.e. moto lost its in-memory state.
STATE_BUCKET_CREATED_REPORT = "state_bucket_created={created}"

SENTINEL = "CHANGE_ME"
SENTINEL_FIX_HINT = "replace it with a generated value, e.g. `openssl rand -hex 24`"

# Anchored, linear-time allowlists; the charsets exclude every URL/shell metacharacter
# so a value can be interpolated into a DSN or a JSON body without escaping.
_ENV_CONTRACT: dict[str, re.Pattern[str]] = {
    "POSTGRES_USER": re.compile(r"^[a-z_][a-z0-9_]{0,62}$"),
    "POSTGRES_DB": re.compile(r"^[a-z_][a-z0-9_]{0,62}$"),
    "POSTGRES_PASSWORD": re.compile(r"^[A-Za-z0-9_-]{16,128}$"),
    "ORBIT_DEV_USER_EMAIL": re.compile(
        r"^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9-]{1,63}){0,8}\.[A-Za-z]{2,24}$"
    ),
    "ORBIT_DEV_USER_PASSWORD": re.compile(r"^[\x21-\x7E]{12,128}$"),
}
_SECRET_KEYS = frozenset({"POSTGRES_PASSWORD", "ORBIT_DEV_USER_PASSWORD"})
_EMAIL_MAX_LENGTH = 254

_LOOPBACK_ENDPOINT = re.compile(r"^http://(localhost|127\.0\.0\.1):[0-9]{2,5}$")
_ENV_LINE = re.compile(r"^([A-Z][A-Z0-9_]{0,63})=(.*)$")

SUBCOMMANDS = ("validate-env", "ensure-state-backend", "seed-secrets")

DATABASE_URL_SECRET_NAME = "orbit/database-url"


class EnvFileError(Exception):
    """A .env.local problem; the message names the key or line, never a value."""


def _require_loopback_endpoint(environ: Mapping[str, str]) -> str:
    """Return AWS_ENDPOINT_URL if it is a loopback URL, else exit 2 before any client exists."""
    endpoint = environ.get("AWS_ENDPOINT_URL", "")
    if not _LOOPBACK_ENDPOINT.fullmatch(endpoint):
        print(
            "error: AWS_ENDPOINT_URL must be http://localhost:<port> or http://127.0.0.1:<port>; "
            "refusing to build an AWS client",
            file=sys.stderr,
        )
        raise SystemExit(EXIT_USAGE)
    return endpoint


def parse_env_file(path: Path) -> dict[str, str]:
    """Parse KEY=VALUE lines strictly (no quoting, export or expansion); unknown or repeated keys raise."""
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        match = _ENV_LINE.fullmatch(raw_line)
        if match is None:
            raise EnvFileError(f"line {line_number}: not a KEY=VALUE line")
        key, value = match.groups()
        if key not in _ENV_CONTRACT:
            raise EnvFileError(f"line {line_number}: key {key} is not allowed")
        if key in values:
            raise EnvFileError(f"line {line_number}: key {key} is repeated")
        values[key] = value
    return values


def validate_env(values: Mapping[str, str]) -> list[str]:
    """Check parsed values against the contract; return one message per problem, never a value."""
    problems: list[str] = []
    for key, pattern in _ENV_CONTRACT.items():
        value = values.get(key)
        if value is None:
            problems.append(f"{key}: missing")
        elif value == SENTINEL and key in _SECRET_KEYS:
            problems.append(f"{key}: still the {SENTINEL} placeholder; {SENTINEL_FIX_HINT}")
        elif not pattern.fullmatch(value) or (key == "ORBIT_DEV_USER_EMAIL" and len(value) > _EMAIL_MAX_LENGTH):
            problems.append(f"{key}: does not match its allowed format")
    return problems


def _bucket_exists(s3_client) -> bool:
    """Whether the state bucket is already present, distinguishing 'absent' from real errors."""
    try:
        s3_client.head_bucket(Bucket=STATE_BUCKET_NAME)
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") in {"404", "NoSuchBucket", "NotFound"}:
            return False
        raise
    return True


def _encryption_configured(s3_client) -> bool:
    """Whether the bucket already has a default-encryption rule."""
    try:
        s3_client.get_bucket_encryption(Bucket=STATE_BUCKET_NAME)
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "ServerSideEncryptionConfigurationNotFoundError":
            return False
        raise
    return True


def ensure_state_backend(s3_client) -> list[str]:
    """Idempotently create the Terraform state bucket (versioned, SSE-S3); return the actions taken.

    Only S3 is touched: locking uses Terraform's own S3 lockfile, so there is no lock table.
    """
    actions: list[str] = []
    if not _bucket_exists(s3_client):
        # us-east-1 is the one region where a LocationConstraint must NOT be sent.
        s3_client.create_bucket(Bucket=STATE_BUCKET_NAME)
        actions.append(CREATED_BUCKET_ACTION)
    if s3_client.get_bucket_versioning(Bucket=STATE_BUCKET_NAME).get("Status") != "Enabled":
        s3_client.put_bucket_versioning(
            Bucket=STATE_BUCKET_NAME, VersioningConfiguration={"Status": "Enabled"}
        )
        actions.append("enabled versioning")
    if not _encryption_configured(s3_client):
        s3_client.put_bucket_encryption(
            Bucket=STATE_BUCKET_NAME,
            ServerSideEncryptionConfiguration={
                "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
            },
        )
        actions.append("enabled default encryption")
    return actions


def _redact_dsn(dsn: str) -> str:
    """Replace the password in a DSN's userinfo with *** so the DSN is safe to print."""
    return re.sub(r"(://[^:/@\s]+:)[^@\s]*@", r"\1***@", dsn, count=1)


def build_database_dsn(values: Mapping[str, str]) -> str:
    """The asyncpg DSN for the compose network (host `postgres`), since api/migrate are its consumers.

    The contract charsets make the userinfo URL-safe, so no escaping is needed.
    """
    return (
        f"postgresql+asyncpg://{values['POSTGRES_USER']}:{values['POSTGRES_PASSWORD']}"
        f"@postgres:5432/{values['POSTGRES_DB']}"
    )


def seed_database_url_secret(secrets_client, values: Mapping[str, str]) -> str:
    """Write the DSN into the existing moto secret (the out-of-band step prod does at deploy); return it redacted."""
    dsn = build_database_dsn(values)
    secrets_client.put_secret_value(SecretId=DATABASE_URL_SECRET_NAME, SecretString=dsn)
    return _redact_dsn(dsn)


def _build_s3_client(endpoint_url: str):
    """Build an S3 client pinned to moto with static dummy credentials (ambient ones are ignored)."""
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        region_name=STATE_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )


def _load_valid_env(env_file: Path) -> dict[str, str] | None:
    """Parse and validate the env file; print problems (keys only) and return None if any."""
    try:
        values = parse_env_file(env_file)
    except (EnvFileError, OSError) as error:
        print(f"error: {env_file}: {error}", file=sys.stderr)
        return None
    problems = validate_env(values)
    for problem in problems:
        print(f"error: {env_file}: {problem}", file=sys.stderr)
    return None if problems else values


def _build_secrets_manager_client(endpoint_url: str):
    """Build a Secrets Manager client pinned to moto with static dummy credentials."""
    return boto3.client(
        "secretsmanager",
        endpoint_url=endpoint_url,
        region_name=STATE_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )


def _build_parser() -> argparse.ArgumentParser:
    """Argparse front end; the subcommand choices are the allowlist."""
    parser = argparse.ArgumentParser(description="Local-stack helper (moto only).")
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate-env", help="check .env.local against its contract")
    validate_parser.add_argument("--env-file", type=Path, required=True)
    ensure_parser = subparsers.add_parser("ensure-state-backend", help="create the moto state bucket if absent")
    ensure_parser.add_argument(
        "--report",
        action="store_true",
        help="print only state_bucket_created=0|1 on stdout; the human summary goes to stderr",
    )
    seed_parser = subparsers.add_parser("seed-secrets", help="write the database DSN into moto Secrets Manager")
    seed_parser.add_argument("--env-file", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None, environ: Mapping[str, str] | None = None) -> int:
    """Entry point: guard the endpoint first, then dispatch one allowlisted subcommand."""
    arguments = _build_parser().parse_args(argv)
    endpoint_url = _require_loopback_endpoint(os.environ if environ is None else environ)
    if arguments.command in {"validate-env", "seed-secrets"}:
        values = _load_valid_env(arguments.env_file)
        if values is None:
            return EXIT_USAGE
        if arguments.command == "validate-env":
            return 0
        redacted_dsn = seed_database_url_secret(_build_secrets_manager_client(endpoint_url), values)
        print(f"seeded {DATABASE_URL_SECRET_NAME} = {redacted_dsn}")
        return 0
    actions = ensure_state_backend(_build_s3_client(endpoint_url))
    summary = f"state bucket {STATE_BUCKET_NAME}: {', '.join(actions) if actions else 'unchanged'}"
    if arguments.report:
        print(summary, file=sys.stderr)
        print(STATE_BUCKET_CREATED_REPORT.format(created=int(CREATED_BUCKET_ACTION in actions)))
    else:
        print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
