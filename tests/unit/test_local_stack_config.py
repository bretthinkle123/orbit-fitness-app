"""Static checks over the local-stack configuration files (no containers needed)."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_CONFIG = REPO_ROOT / "infra" / "envs" / "local" / "backend.moto.hcl"


def test_backend_uses_lockfile():
    """The moto state backend locks through S3 conditional writes, not a DynamoDB table."""
    settings = "\n".join(
        line for line in BACKEND_CONFIG.read_text(encoding="utf-8").splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"^use_lockfile\s*=\s*true\s*$", settings, re.MULTILINE)
    assert "dynamodb" not in settings.lower()


def test_backend_state_endpoint_is_loopback_only():
    text = BACKEND_CONFIG.read_text(encoding="utf-8")
    endpoints = re.findall(r'"(https?://[^"]+)"', text)
    assert endpoints and all(re.fullmatch(r"http://(localhost|127\.0\.0\.1):[0-9]{2,5}", url) for url in endpoints)


def test_gitignore_covers_local_secrets():
    """Env file, Terraform working dirs, state backups and the guard-probe scratch file stay untracked."""
    for ignored_path in (
        ".env.local",
        "infra/envs/local/.terraform/providers",
        "infra/envs/local/terraform.tfstate.backup",
        ".local/anything",
        "infra/envs/local/zz_probe_override.tf",
    ):
        result = subprocess.run(
            ["git", "check-ignore", "-q", ignored_path], cwd=REPO_ROOT, check=False
        )
        assert result.returncode == 0, f"{ignored_path} is not gitignored"


DOCKERFILE = REPO_ROOT / "Dockerfile"
DOCKERIGNORE = REPO_ROOT / ".dockerignore"
BUILD_PROVENANCE = REPO_ROOT / ".github" / "workflows" / "build-provenance.yml"

_FROM_LINE = re.compile(r"^FROM\s+(?P<image>\S+)(?:\s+AS\s+(?P<stage>\S+))?\s*$", re.MULTILINE | re.IGNORECASE)
_DIGEST_PINNED_IMAGE = re.compile(r"^[a-z0-9./_-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$")


def _dockerfile_instructions() -> list[str]:
    """Dockerfile lines with comments and blanks removed (continuations joined)."""
    joined = DOCKERFILE.read_text(encoding="utf-8").replace("\\\n", " ")
    return [line.strip() for line in joined.splitlines() if line.strip() and not line.strip().startswith("#")]


def test_dockerfile_has_two_digest_pinned_stages_on_the_same_base():
    froms = _FROM_LINE.findall(DOCKERFILE.read_text(encoding="utf-8"))
    assert [stage for _, stage in froms] == ["builder", "runtime"]
    images = [image for image, _ in froms]
    assert all(_DIGEST_PINNED_IMAGE.fullmatch(image) for image in images), images
    assert images[0] == images[1]


def test_dockerfile_runs_as_the_unprivileged_user():
    instructions = _dockerfile_instructions()
    user_lines = [line for line in instructions if line.startswith("USER ")]
    assert user_lines and user_lines[-1] == "USER 10001:10001"
    runtime_start = max(index for index, line in enumerate(instructions) if line.startswith("FROM "))
    assert instructions.index(user_lines[-1]) > runtime_start


def test_dockerfile_has_a_stdlib_healthcheck_on_health():
    healthchecks = [line for line in _dockerfile_instructions() if line.startswith("HEALTHCHECK")]
    assert len(healthchecks) == 1
    assert "/health" in healthchecks[0] and "urllib" in healthchecks[0]
    assert "curl" not in healthchecks[0]


def test_dockerfile_bakes_no_emulator_or_endpoint_env():
    """The image defaults to real Firebase and real AWS; only compose supplies local overrides."""
    forbidden = re.compile(
        r"FIREBASE_AUTH_EMULATOR_HOST|AWS_ENDPOINT_URL|DATABASE_URL|PASSWORD|SECRET|TOKEN|localstack|moto",
        re.IGNORECASE,
    )
    for line in _dockerfile_instructions():
        if line.startswith(("ENV ", "ARG ")):
            assert not forbidden.search(line), line


def test_dockerfile_runtime_stage_has_no_poetry():
    instructions = _dockerfile_instructions()
    runtime_start = max(index for index, line in enumerate(instructions) if line.startswith("FROM "))
    assert not any("poetry" in line.lower() for line in instructions[runtime_start:])


def test_dockerfile_serves_uvicorn_on_all_interfaces_port_8000():
    commands = [line for line in _dockerfile_instructions() if line.startswith("CMD ")]
    assert commands == ['CMD ["uvicorn", "orbit.main:app", "--host", "0.0.0.0", "--port", "8000"]']


def test_dockerignore_is_allowlist():
    """A denylist fails open for every new sensitive file; an allowlist fails closed."""
    rules = [line.strip() for line in DOCKERIGNORE.read_text(encoding="utf-8").splitlines()]
    rules = [rule for rule in rules if rule and not rule.startswith("#")]
    assert rules[0] == "*"
    included = {rule[1:] for rule in rules if rule.startswith("!")}
    assert included == {"pyproject.toml", "poetry.lock", "README.md", "src/", "migrations/", "alembic.ini"}
    assert "**/__pycache__" in rules


def test_build_provenance_is_inert_until_deploy_is_enabled():
    """A root Dockerfile alone must not make every merge to main try to push to a placeholder ECR."""
    text = BUILD_PROVENANCE.read_text(encoding="utf-8")
    gate = text[text.index("id: gate"):text.index("hadolint")]
    assert "vars.DEPLOY_ENABLED" in gate
    assert "inert until E1" in gate


EMULATOR_DIR = REPO_ROOT / "docker" / "firebase-emulator"
PIPELINE_CI = REPO_ROOT / ".github" / "workflows" / "pipeline-ci.yml"


def _emulator_instructions() -> list[str]:
    """Emulator Dockerfile lines with comments and blanks removed (continuations joined)."""
    joined = (EMULATOR_DIR / "Dockerfile").read_text(encoding="utf-8").replace("\\\n", " ")
    return [line.strip() for line in joined.splitlines() if line.strip() and not line.strip().startswith("#")]


def test_emulator_base_image_is_digest_pinned_node():
    """The emulator is built in-repo from an official, digest-pinned Node base (no community image)."""
    froms = [line for line in _emulator_instructions() if line.startswith("FROM ")]
    assert len(froms) == 1
    assert re.fullmatch(r"FROM node:24-trixie-slim@sha256:[0-9a-f]{64}|FROM node:24\.\d+\.\d+-trixie-slim@sha256:[0-9a-f]{64}", froms[0]), froms[0]


def test_firebase_tools_matches_ci():
    """The image installs the same firebase-tools version the CI test job pins."""
    ci_version = re.search(r"^\s*FIREBASE_TOOLS_VERSION:\s*([0-9.]+)\s*$", PIPELINE_CI.read_text(encoding="utf-8"), re.MULTILINE)
    image_version = re.search(r"^ARG FIREBASE_TOOLS_VERSION=([0-9.]+)$", "\n".join(_emulator_instructions()), re.MULTILINE)
    assert ci_version and image_version
    assert image_version.group(1) == ci_version.group(1)
    installs = [line for line in _emulator_instructions() if "npm install" in line]
    assert len(installs) == 1 and "firebase-tools@${FIREBASE_TOOLS_VERSION}" in installs[0]


def test_emulator_runs_unprivileged_with_a_fetch_healthcheck():
    instructions = _emulator_instructions()
    assert [line for line in instructions if line.startswith("USER ")][-1] == "USER node"
    healthchecks = [line for line in instructions if line.startswith("HEALTHCHECK")]
    assert len(healthchecks) == 1 and "fetch(" in healthchecks[0] and "/emulator/v1/projects/demo-orbit-test/config" in healthchecks[0]
    assert "EXPOSE 9099" in instructions


def test_emulator_installs_no_jre_unless_justified():
    """JDK decision: the Auth emulator runs inside the Node CLI, so no Java is installed."""
    text = (EMULATOR_DIR / "Dockerfile").read_text(encoding="utf-8").lower()
    assert "openjdk" not in text and "default-jre" not in text and "java_tool_options" not in text


def test_emulator_entrypoint_runs_auth_only_for_the_demo_project():
    script = (EMULATOR_DIR / "entrypoint.sh").read_text(encoding="utf-8")
    assert script.startswith("#!/bin/sh\n") and "set -eu" in script
    assert "exec firebase emulators:start --only auth --project demo-orbit-test" in script
    assert "state_dir=/data/state" in script  # never the volume root: the CLI cannot replace a mount point
    assert "--export-on-exit=$state_dir" in script
    assert "$state_dir/firebase-export-metadata.json" in script  # --import only when an export exists


def test_emulator_config_listens_on_container_port_9099_without_ui():
    import json

    config = json.loads((EMULATOR_DIR / "firebase.json").read_text(encoding="utf-8"))
    assert config["emulators"]["auth"] == {"port": 9099, "host": "0.0.0.0"}
    assert config["emulators"]["ui"]["enabled"] is False
    assert set(config["emulators"]) == {"auth", "ui"}


COMPOSE_FILE = REPO_ROOT / "docker-compose.yml"
EXPECTED_HOST_PORTS = {
    "api": "127.0.0.1:8080:8000",
    "postgres": "127.0.0.1:5433:5432",
    "redis": "127.0.0.1:6380:6379",
    "firebase-emulator": "127.0.0.1:9100:9099",
    "moto": "127.0.0.1:5001:5000",
}


def _compose_lines() -> list[str]:
    """Compose file lines with full-line comments removed (text-only parsing; no YAML library)."""
    return [line for line in COMPOSE_FILE.read_text(encoding="utf-8").splitlines() if not line.lstrip().startswith("#")]


def _compose_services() -> dict[str, list[str]]:
    """Map each top-level service name to the lines of its block, split on 2-space-indented keys."""
    services: dict[str, list[str]] = {}
    current: str | None = None
    in_services = False
    for line in _compose_lines():
        if re.match(r"^\S", line):
            in_services = line.startswith("services:")
            current = None
            continue
        header = re.match(r"^  ([a-z][a-z0-9-]*):\s*$", line)
        if in_services and header:
            current = header.group(1)
            services[current] = []
        elif in_services and current:
            services[current].append(line)
    return services


def test_compose_defines_the_expected_services():
    assert set(_compose_services()) == {"api", "migrate", "postgres", "redis", "firebase-emulator", "moto"}


def test_ports_loopback_and_mapped():
    """Every published port binds loopback and uses the shifted host ports; 9099 and 8000 stay free."""
    published: dict[str, list[str]] = {}
    for name, block in _compose_services().items():
        in_ports = False
        for line in block:
            if re.match(r"^    ports:\s*$", line):
                in_ports = True
            elif re.match(r"^    \S", line):
                in_ports = False
            elif in_ports and (entry := re.match(r'^      - "?([^"\s]+)"?\s*$', line)):
                published.setdefault(name, []).append(entry.group(1))
    assert {name: ports[0] for name, ports in published.items()} == EXPECTED_HOST_PORTS
    assert all(len(ports) == 1 for ports in published.values())
    for mapping in EXPECTED_HOST_PORTS.values():
        host_port = mapping.split(":")[1]
        assert host_port not in {"9099", "8000"}


def test_images_digest_pinned():
    """Every registry image (compose `image:` without a build) and every Dockerfile FROM is tag@sha256."""
    for name, block in _compose_services().items():
        text = "\n".join(block)
        image = re.search(r"^    image:\s*(\S+)\s*$", text, re.MULTILINE)
        assert image, name
        if re.search(r"^    build:", text, re.MULTILINE) or image.group(1).endswith(":local"):
            continue  # built locally (here or by a sibling service); its Dockerfile FROM is checked below
        assert _DIGEST_PINNED_IMAGE.fullmatch(image.group(1)), f"{name}: {image.group(1)}"
    for dockerfile in (DOCKERFILE, EMULATOR_DIR / "Dockerfile"):
        for image in re.findall(r"^FROM\s+(\S+)", dockerfile.read_text(encoding="utf-8"), re.MULTILINE | re.IGNORECASE):
            assert _DIGEST_PINNED_IMAGE.fullmatch(image), f"{dockerfile.name}: {image}"


def test_postgres_major_matches_rds_engine_major():
    """Local Postgres tracks the major RDS runs; the minor is deliberately not compared."""
    postgres_image = re.search(r"image:\s*postgres:(\d+)\.\d+-alpine@sha256:", "\n".join(_compose_services()["postgres"]))
    engine_version = re.search(
        r'engine_version\s*=\s*"(\d+)\.\d+"',
        (REPO_ROOT / "infra" / "modules" / "data" / "main.tf").read_text(encoding="utf-8").split("aws_db_instance")[1],
    )
    assert postgres_image and engine_version
    assert postgres_image.group(1) == engine_version.group(1)


def test_api_service_has_no_database_url():
    """DATABASE_URL must be absent so the app resolves its DSN through the secrets facade (moto)."""
    assert not any("DATABASE_URL" in line for line in _compose_lines())


def test_api_is_hardened_and_waits_for_healthy_dependencies():
    block = "\n".join(_compose_services()["api"])
    assert re.search(r"^    read_only: true\s*$", block, re.MULTILINE)
    assert re.search(r"cap_drop:\s*\n\s+- ALL", block)
    assert "no-new-privileges:true" in block
    for dependency in ("postgres", "redis", "moto", "firebase-emulator"):
        assert re.search(rf"^      {dependency}:\s*\n\s+condition: service_healthy", block, re.MULTILINE), dependency


def test_every_service_has_a_memory_limit():
    for name, block in _compose_services().items():
        assert re.search(r"^    mem_limit: \d+m\s*$", "\n".join(block), re.MULTILINE), name


def test_compose_env_file_single_mechanism():
    """Compose half: each POSTGRES_* reference uses the required-variable form, so a missing env file aborts."""
    references = re.findall(r"(?<!\$)\$\{(POSTGRES_[A-Z]+)([^}]*)\}", "\n".join(_compose_lines()))
    assert {name for name, _ in references} == {"POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB"}
    for name, suffix in references:
        assert suffix.startswith(":?"), f"{name} must use ${{{name}:?...}}"
    # The scripts half (dev-up.sh / dev-down.sh only call compose via dc()) is added with those scripts.
    for script_name in ("dev-up.sh", "dev-down.sh"):
        script = REPO_ROOT / "scripts" / script_name
        if script.exists():
            others = [line for line in script.read_text(encoding="utf-8").splitlines()
                      if "docker compose" in line and not line.lstrip().startswith("#") and not line.startswith("dc()")]
            assert not others, f"{script_name}: compose called outside dc(): {others}"


def test_fbauth_volume_mounts_at_data_not_the_state_subdirectory():
    block = "\n".join(_compose_services()["firebase-emulator"])
    assert re.search(r"^\s+- fbauth:/data\s*$", block, re.MULTILINE)


def test_dev_scripts_exist_and_route_compose_through_dc():
    """Scripts half of the single-mechanism rule: dc() is defined once, with --env-file, and used everywhere."""
    for script_name in ("dev-up.sh", "dev-down.sh"):
        text = (REPO_ROOT / "scripts" / script_name).read_text(encoding="utf-8")
        definitions = [line for line in text.splitlines() if line.startswith("dc()")]
        assert len(definitions) == 1 and '--env-file "$REPO_ROOT/.env.local"' in definitions[0], script_name
        assert text.startswith("#!/usr/bin/env bash\n") and "set -euo pipefail" in text


def test_dev_up_accepts_only_rebuild_and_dev_down_only_clean():
    dev_up = (REPO_ROOT / "scripts" / "dev-up.sh").read_text(encoding="utf-8")
    dev_down = (REPO_ROOT / "scripts" / "dev-down.sh").read_text(encoding="utf-8")
    assert re.search(r"--rebuild\)", dev_up) and re.search(r"\*\)\s*usage", dev_up.replace("\n", " "))
    assert re.search(r"--clean\)", dev_down) and re.search(r"\*\)\s*usage", dev_down.replace("\n", " "))


def test_dev_scripts_never_pass_secrets_on_a_command_line():
    """No script may embed or echo the Postgres password; they only hand the env file path around."""
    for script_name in ("dev-up.sh", "dev-down.sh"):
        text = (REPO_ROOT / "scripts" / script_name).read_text(encoding="utf-8")
        assert "POSTGRES_PASSWORD" not in text and "ORBIT_DEV_USER_PASSWORD" not in text


IOS_DIR = REPO_ROOT / "ios" / "Orbit"


def _xcconfig_settings(name: str) -> dict[str, str]:
    """Parse an xcconfig into {KEY: value}, ignoring comment lines (which start with //)."""
    settings = {}
    for line in (IOS_DIR / "Config" / name).read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("//"):
            key, _, value = line.partition("=")
            settings[key.strip()] = value.strip()
    return settings


def test_debug_xcconfig_points_at_the_compose_stack():
    settings = _xcconfig_settings("Debug.xcconfig")
    # `//` starts an xcconfig comment, so the scheme separator is written http:/$()/ to survive.
    assert settings["ORBIT_API_BASE_URL"] == "http:/$()/localhost:8080"
    assert settings["ORBIT_FIREBASE_AUTH_EMULATOR_HOST"] == "localhost:9100"


def test_release_xcconfig_keeps_todays_base_url_and_no_emulator():
    settings = _xcconfig_settings("Release.xcconfig")
    assert settings["ORBIT_API_BASE_URL"] == "http:/$()/localhost:8001"  # pre-existing literal, not a fix
    assert settings["ORBIT_FIREBASE_AUTH_EMULATOR_HOST"] == ""


def test_xcconfigs_are_attached_to_the_existing_configurations_only():
    project = (IOS_DIR / "project.yml").read_text(encoding="utf-8")
    assert re.search(r"configFiles:\s*\n\s+Debug: Config/Debug\.xcconfig\s*\n\s+Release: Config/Release\.xcconfig", project)
    assert "configs:" not in project  # no third configuration (doubles Firebase SDK DerivedData)


def test_info_plist_reads_the_xcconfig_values_and_adds_no_ats_exception():
    plist = (IOS_DIR / "Resources" / "Info.plist").read_text(encoding="utf-8")
    assert re.search(r"<key>OrbitAPIBaseURL</key>\s*<string>\$\(ORBIT_API_BASE_URL\)</string>", plist)
    assert re.search(r"<key>OrbitFirebaseAuthEmulatorHost</key>\s*<string>\$\(ORBIT_FIREBASE_AUTH_EMULATOR_HOST\)</string>", plist)
    assert "<key>NSAppTransportSecurity</key>" not in plist


def test_emulator_wiring_stays_debug_only():
    app = (IOS_DIR / "App" / "OrbitApp.swift").read_text(encoding="utf-8")
    body = app.split("private static func configureFirebaseAuthEmulatorIfConfigured()")[1]
    assert re.search(r"\n\s+#if DEBUG\n", body.split("\n    }\n")[0]) and "#endif" in body


def test_ui_test_launch_overrides_are_opt_in():
    """launchApp() must not hardcode a backend: with no TEST_RUNNER_ overrides a UI run uses the Debug xcconfig."""
    source = (IOS_DIR / "Tests" / "UITests" / "AuthFlowUITests.swift").read_text(encoding="utf-8")
    launch = source.split("static func launchApp()")[1].split("app.launch()")[0]
    assert "ORBIT_UITEST_API_BASE_URL" in launch and "ORBIT_UITEST_FIREBASE_AUTH_EMULATOR_HOST" in launch
    for line in launch.splitlines():
        if 'launchEnvironment["OrbitAPIBaseURL"] = "' in line or 'launchEnvironment["OrbitFirebaseAuthEmulatorHost"] = "' in line:
            raise AssertionError(f"hardcoded launch override: {line.strip()}")
