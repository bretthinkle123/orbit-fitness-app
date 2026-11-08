#!/usr/bin/env python
"""Seed the local dev account: a Firebase emulator user plus demo data, all through the real API.

Going through the API (not SQL) means the seed can only create states the app itself could
produce, needs no database credentials on the host, and doubles as a deep readiness probe
(auth -> emulator, DB -> moto DSN, Redis throttle). Every step checks before it inserts, so
re-running changes nothing. This is a dev-only fixture: it is never a migration, because new
users start empty.

Usage (from the repo root, venv active):
    python -m scripts.seed_dev_data --env-file .env.local

Prints the dev user's UID and what it did; never the ID token or the password.
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import sys
from collections.abc import Mapping
from pathlib import Path

import requests

from scripts.dev import local_aws

EXIT_USAGE = 2
REQUEST_TIMEOUT_SECONDS = 10

DEFAULT_API_BASE = "http://localhost:8080"
DEFAULT_EMULATOR_HOST = "localhost:9100"
_LOOPBACK_API_BASE = re.compile(r"^http://(localhost|127\.0\.0\.1):[0-9]{2,5}$")
_LOOPBACK_EMULATOR_HOST = re.compile(r"^(localhost|127\.0\.0\.1):[0-9]{2,5}$")

# The emulator ignores the key's value entirely; the REST shape just requires one.
_EMULATOR_API_KEY = "fake-api-key"
_SEEDED_FUEL_ENTRIES = (("breakfast", 0), ("lunch", 1))  # (meal group, quick-food catalog index)
_SEEDED_SET_COUNT = 2
_SEEDED_WEIGHT_KG = 72.5


def _refuse(message: str) -> None:
    """Print an error and exit 2, the script's usage-error status."""
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(EXIT_USAGE)


def require_loopback_api_base(api_base: str) -> str:
    """Return the API base URL if it is loopback, else exit 2 so a real environment is never seeded."""
    if not _LOOPBACK_API_BASE.fullmatch(api_base):
        _refuse("the API base URL must be http://localhost:<port> or http://127.0.0.1:<port>")
    return api_base


def require_loopback_emulator_host(host: str) -> str:
    """Return the emulator host:port if it is loopback, else exit 2."""
    if not _LOOPBACK_EMULATOR_HOST.fullmatch(host):
        _refuse("the Firebase emulator host must be localhost:<port> or 127.0.0.1:<port>")
    return host


def load_dev_user_credentials(env_file: Path) -> tuple[str, str]:
    """Validate the whole env file with the shared contract and return (email, password).

    Delegating to local_aws keeps one definition of each contract; errors name keys only.
    """
    try:
        values = local_aws.parse_env_file(env_file)
    except (local_aws.EnvFileError, OSError) as error:
        _refuse(f"{env_file}: {error}")
    problems = local_aws.validate_env(values)
    for problem in problems:
        print(f"error: {env_file}: {problem}", file=sys.stderr)
    if problems:
        raise SystemExit(EXIT_USAGE)
    return values["ORBIT_DEV_USER_EMAIL"], values["ORBIT_DEV_USER_PASSWORD"]


def sign_up_or_sign_in(emulator_host: str, email: str, password: str) -> tuple[str, str]:
    """Create the dev user, or sign in if it already exists; return (uid, id_token).

    Same idempotent pattern as scripts/seed_dast_user.py, against the compose emulator.
    """
    credentials = {"email": email, "password": password, "returnSecureToken": True}

    def call(action: str) -> requests.Response:
        return requests.post(
            f"http://{emulator_host}/identitytoolkit.googleapis.com/v1/accounts:{action}",
            params={"key": _EMULATOR_API_KEY},
            json=credentials,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )

    response = call("signUp")
    if response.status_code != 200:
        # Status first: only a 400 can be EMAIL_EXISTS, so only a 400's body is parsed, and any
        # other failure (including a non-JSON error page) surfaces as the HTTP error itself.
        if response.status_code != 400 or not _is_email_exists(response):
            response.raise_for_status()
        response = call("signInWithPassword")
        response.raise_for_status()
    data = response.json()
    return data["localId"], data["idToken"]


def _is_email_exists(response: requests.Response) -> bool:
    """Whether a signUp 400 is the emulator's EMAIL_EXISTS; a body of any other shape is not."""
    try:
        body = response.json()
    except ValueError:  # requests' JSONDecodeError is a ValueError
        return False
    error = body.get("error") if isinstance(body, dict) else None
    return isinstance(error, dict) and "EMAIL_EXISTS" in str(error.get("message", ""))


class ApiClient:
    """A minimal authenticated JSON client for the local API."""

    def __init__(self, base_url: str, id_token: str) -> None:
        self._base_url = base_url
        self._headers = {"Authorization": f"Bearer {id_token}"}

    def get(self, path: str, params: Mapping[str, str] | None = None):
        """GET a path and return the decoded JSON body, raising on any HTTP error."""
        response = requests.get(
            self._base_url + path, params=params, headers=self._headers, timeout=REQUEST_TIMEOUT_SECONDS
        )
        response.raise_for_status()
        return response.json()

    def post(self, path: str, body: Mapping[str, object] | None = None):
        """POST a JSON body (none for the bodiless routes) and return the decoded response."""
        response = requests.post(
            self._base_url + path,
            json=body if body is not None else None,
            headers=self._headers,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json() if response.content else {}


def seed_demo_data(api, today: datetime.date, now: datetime.datetime) -> dict[str, int]:
    """Bring the dev account to: bootstrapped, 2 food entries, 2 done sets and a weight for today.

    Each section reads first and writes only what is missing; returns how many rows were added.
    """
    day_key = today.isoformat()
    logged_at = now.isoformat()
    added = {"fuel_entries": 0, "done_sets": 0, "weight_entries": 0}
    api.post("/me/bootstrap")

    fuel_day = api.get("/fuel", params={"day_key": day_key})
    if not any(fuel_day["meals"].values()):
        catalog = api.get("/catalog/quick-foods")
        for meal_group, catalog_index in _SEEDED_FUEL_ENTRIES:
            api.post(
                "/fuel/entries",
                {"meal_group": meal_group, "day_key": day_key, "logged_at": logged_at, "quick_food_id": catalog[catalog_index]["id"]},
            )
            added["fuel_entries"] += 1

    train_day = api.get("/train", params={"day_key": day_key})
    first_exercise = train_day["exercises"][0]
    if not first_exercise["done_set_indexes"]:
        for set_index in range(min(_SEEDED_SET_COUNT, first_exercise["sets"])):
            api.post(
                "/train/sets",
                {"exercise_id": first_exercise["id"], "set_index": set_index, "day_key": day_key, "done_at": logged_at},
            )
            added["done_sets"] += 1

    weight_window = api.get("/weight")
    if not any(entry["day_key"] == day_key for entry in weight_window["entries"]):
        api.post("/weight", {"weight_kg": _SEEDED_WEIGHT_KG, "day_key": day_key, "logged_at": logged_at})
        added["weight_entries"] += 1
    return added


def main(argv: list[str] | None = None, environ: Mapping[str, str] | None = None) -> int:
    """Validate inputs, ensure the dev user exists, seed demo data, and report counts (never secrets)."""
    parser = argparse.ArgumentParser(description="Seed the local dev account through the API.")
    parser.add_argument("--env-file", type=Path, required=True)
    arguments = parser.parse_args(argv)
    environment = os.environ if environ is None else environ

    api_base = require_loopback_api_base(environment.get("ORBIT_SEED_API_BASE", DEFAULT_API_BASE))
    emulator_host = require_loopback_emulator_host(environment.get("ORBIT_SEED_EMULATOR_HOST", DEFAULT_EMULATOR_HOST))
    email, password = load_dev_user_credentials(arguments.env_file)

    uid, id_token = sign_up_or_sign_in(emulator_host, email, password)
    now = datetime.datetime.now(datetime.timezone.utc)
    added = seed_demo_data(ApiClient(api_base, id_token), datetime.date.today(), now)
    print(f"dev user uid={uid} email={email}")
    print("seeded: " + ", ".join(f"{name}={count}" for name, count in added.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
