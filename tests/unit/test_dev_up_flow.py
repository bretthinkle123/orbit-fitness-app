"""scripts/dev-up.sh step order, run end to end against stub commands (no Docker, no Terraform).

The real script is copied into a temporary repo root (it derives REPO_ROOT from its own path)
and runs with stub `docker`, `terraform`, `lsof`, `curl`, `.venv/bin/python` and
`seed_ui_test_user.sh`. Each stub appends its argv to calls.log. The docker stub models the
compose behaviour the code-review findings turn on: `compose run migrate` needs the
orbit-api:local image to exist, because that service only names the image (no `build:`), and
compose would otherwise try to pull it.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

_DOCKER_STUB = r"""#!/usr/bin/env bash
echo "docker $*" >> "$STUB_STATE/calls.log"
if [ "$1" = compose ]; then
  shift
  while [ "$#" -gt 0 ]; do case "$1" in --env-file|-f) shift 2 ;; *) break ;; esac; done
  case "$1" in
    build) case " $* " in *" api "*) touch "$STUB_STATE/image-orbit-api" ;; esac ;;
    up) touch "$STUB_STATE/stack-up" ;;
    run) [ -f "$STUB_STATE/image-orbit-api" ] || { echo "pull access denied for orbit-api" >&2; exit 1; } ;;
    ps) if [ "$*" = "ps -q api" ] && [ -f "$STUB_STATE/api-was-present" ]; then echo api-container-id; fi ;;
  esac
  exit 0
fi
if [ "$1" = images ] && [ -f "$STUB_STATE/image-orbit-api" ]; then echo image-id; fi
exit 0
"""

# Listens (on loopback) only once the stack is "up", so the preflight port check sees free ports.
_LSOF_STUB = r"""#!/usr/bin/env bash
[ -f "$STUB_STATE/stack-up" ] || exit 1
port="$(printf '%s\n' "$@" | sed -n 's/^-iTCP://p')"
echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
echo "ssh 4242 dev 3u IPv4 0x0 0t0 TCP 127.0.0.1:$port (LISTEN)"
"""

_TERRAFORM_STUB = r"""#!/usr/bin/env bash
echo "terraform $*" >> "$STUB_STATE/calls.log"
if [ "$1" = version ]; then echo "Terraform v1.15.9"; fi
exit 0
"""

_LOGGING_STUB = r"""#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB_STATE/calls.log"
exit 0
"""

# The human summary deliberately does NOT use the real helper's wording ("created bucket"):
# dev-up must act on the machine-readable --report line alone.
_PYTHON_STUB = r"""#!/usr/bin/env bash
echo "python $*" >> "$STUB_STATE/calls.log"
case " $* " in
  *" ensure-state-backend "*)
    echo "state bucket orbit-local-tfstate: stub summary, wording deliberately arbitrary" >&2
    case " $* " in *" --report "*) printf '%s\n' "$STUB_ENSURE_REPORT" ;; esac ;;
esac
exit 0
"""


@pytest.fixture
def dev_up(tmp_path):
    """Return run(*args, image_present=False, api_present=False, report=...) -> (CompletedProcess, calls)."""
    root = tmp_path / "repo"
    (root / "scripts").mkdir(parents=True)
    (root / ".venv" / "bin").mkdir(parents=True)
    stub_bin = tmp_path / "bin"
    stub_bin.mkdir()
    state = tmp_path / "state"
    state.mkdir()
    shutil.copy(REPO_ROOT / "scripts" / "dev-up.sh", root / "scripts" / "dev-up.sh")
    (root / ".env.local").write_text("# contents are irrelevant: validate-env is stubbed\n", encoding="utf-8")
    stubs = {
        stub_bin / "docker": _DOCKER_STUB,
        stub_bin / "lsof": _LSOF_STUB,
        stub_bin / "terraform": _TERRAFORM_STUB,
        stub_bin / "curl": _LOGGING_STUB,
        root / "scripts" / "seed_ui_test_user.sh": _LOGGING_STUB,
        root / ".venv" / "bin" / "python": _PYTHON_STUB,
    }
    for path, text in stubs.items():
        path.write_text(text, encoding="utf-8")
        path.chmod(0o755)

    def run(*args, image_present=False, api_present=False, report="state_bucket_created=0"):
        if image_present:
            (state / "image-orbit-api").touch()
        if api_present:
            (state / "api-was-present").touch()
        environment = {
            **os.environ,
            "PATH": f"{stub_bin}{os.pathsep}{os.environ['PATH']}",
            "STUB_STATE": str(state),
            "STUB_ENSURE_REPORT": report,
        }
        completed = subprocess.run(
            ["bash", str(root / "scripts" / "dev-up.sh"), *args],
            env=environment,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        log = state / "calls.log"
        calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
        return completed, calls

    return run


def _compose(calls: list[str], *words: str) -> list[int]:
    """Indexes of `docker compose ...` calls whose subcommand words (after the dc() flags) start with words."""
    prefix = " ".join(words)
    indexes = []
    for index, call in enumerate(calls):
        if call.startswith("docker compose "):
            subcommand = call.split(" -f ", 1)[1].split(" ", 1)[1]
            if subcommand == prefix or subcommand.startswith(prefix + " "):
                indexes.append(index)
    return indexes


def test_an_image_less_machine_builds_the_api_image_before_migrate(dev_up):
    """Code-review #1: on a machine without orbit-api:local, migrate must not run before the build."""
    completed, calls = dev_up(image_present=False)
    assert completed.returncode == 0, completed.stderr
    builds, migrates = _compose(calls, "build", "api"), _compose(calls, "run", "--rm", "migrate")
    assert builds and migrates and builds[0] < migrates[0]


def test_a_rerun_with_the_image_present_still_rebuilds_api_before_migrate(dev_up):
    """Code-review #4: a cached image must not hide source or migration edits."""
    completed, calls = dev_up(image_present=True)
    assert completed.returncode == 0, completed.stderr
    builds, migrates = _compose(calls, "build", "api"), _compose(calls, "run", "--rm", "migrate")
    assert builds and migrates and builds[0] < migrates[0]
    assert _compose(calls, "build", "--no-cache") == []  # a plain run keeps the layer cache


def test_rebuild_builds_both_images_without_the_layer_cache(dev_up):
    completed, calls = dev_up("--rebuild", image_present=True)
    assert completed.returncode == 0, completed.stderr
    assert _compose(calls, "build", "--no-cache", "firebase-emulator")
    no_cache_api, migrates = _compose(calls, "build", "--no-cache", "api"), _compose(calls, "run", "--rm", "migrate")
    assert no_cache_api and no_cache_api[0] < migrates[0]


def test_moto_reset_is_read_from_the_helper_report_not_its_wording(dev_up):
    """Code-review #9: a recreated state bucket restarts a running api, signalled by --report alone."""
    completed, calls = dev_up(image_present=True, api_present=True, report="state_bucket_created=1")
    assert completed.returncode == 0, completed.stderr
    assert any("ensure-state-backend --report" in call for call in calls)
    assert _compose(calls, "restart", "api")


def test_no_api_restart_when_the_state_bucket_already_existed(dev_up):
    completed, calls = dev_up(image_present=True, api_present=True, report="state_bucket_created=0")
    assert completed.returncode == 0, completed.stderr
    assert _compose(calls, "restart", "api") == []


def test_an_unrecognised_helper_report_fails_the_run(dev_up):
    completed, calls = dev_up(image_present=True, report="created bucket")
    assert completed.returncode != 0
    assert "step=tf-state status=fail" in completed.stderr
    assert _compose(calls, "run", "--rm", "migrate") == []
