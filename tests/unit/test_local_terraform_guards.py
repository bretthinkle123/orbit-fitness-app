"""Static, adversarial checks over the local Terraform root's guard layers (AC6/AC7/AC8/AC14).

The Terraform probes themselves (evidence under .pipeline/a1-evidence/) need a moto server and the
terraform binary. These tests pin the same guarantees at the source level so a regression in the HCL
fails the hermetic suite: the endpoint regex is extracted from variables.tf (not copied here) and
fed hostile inputs.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
LOCAL = REPO_ROOT / "infra" / "envs" / "local"
EXPECTED_ENDPOINTS = {"secretsmanager", "ssm", "kms", "logs", "iam", "s3", "sns", "dynamodb", "sts"}


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _endpoint_regex() -> re.Pattern[str]:
    """The moto_endpoint validation regex, lifted from variables.tf (HCL string -> RE2 pattern)."""
    block = re.search(r'variable "moto_endpoint".*?condition\s*=\s*can\(regex\("(.+?)",\s*var\.moto_endpoint', _read(LOCAL / "variables.tf"), re.S)
    assert block, "moto_endpoint validation condition not found"
    pattern = block.group(1).replace("\\\\", "\\")
    assert pattern.startswith("^") and pattern.endswith("$")
    # RE2 `$` (no multiline) matches only at end of text; Python's also matches before a trailing
    # newline, so anchor with \Z to reproduce Terraform's semantics.
    return re.compile(pattern[:-1] + r"\Z")


@pytest.mark.parametrize(
    "url",
    [
        "http://localhost:5001",
        "http://127.0.0.1:5001",
        "http://moto:5000",
        "http://localhost:80",
        "http://localhost:65535",
    ],
)
def test_moto_endpoint_regex_accepts_local_urls(url):
    assert _endpoint_regex().match(url)


@pytest.mark.parametrize(
    "url",
    [
        "https://example.com",
        "https://localhost:5001",  # wrong scheme
        "http://example.com:5001",
        "http://localhost.evil.com:5001",  # suffix-confusion
        "http://evil.com/localhost:5001",
        "http://localhost:5001@evil.com:80",  # userinfo trick
        "http://user@localhost:5001",
        "http://localhost@evil.com:5001",
        "http://127.0.0.1.evil.com:5001",
        "http://127x0y0z1:5001",  # unescaped-dot regression
        "http://localhost:5001/",  # trailing path
        "http://localhost:5001/path",
        "http://localhost:5001\n",  # trailing newline must not slip past `$`
        "http://localhost:5",  # port too short
        "http://localhost:123456",  # port too long
        "http://localhost",  # no port
        "http://LOCALHOST:5001",
        " http://localhost:5001",
        "http://s3.amazonaws.com:443",
        "",
    ],
)
def test_moto_endpoint_regex_rejects_hostile_urls(url):
    assert not _endpoint_regex().match(url)


def _provider_block() -> str:
    text = _read(LOCAL / "providers.tf")
    start = text.index('provider "aws"')
    return text[start:]


def test_every_service_endpoint_is_pinned_to_the_validated_variable():
    block = _provider_block()
    endpoints_body = re.search(r"endpoints\s*\{(.*?)\n\s*\}", block, re.S).group(1)
    assignments = dict(re.findall(r"^\s*(\w+)\s*=\s*(\S+)\s*$", endpoints_body, re.M))
    assert set(assignments) == EXPECTED_ENDPOINTS
    assert set(assignments.values()) == {"var.moto_endpoint"}


def test_provider_uses_static_dummy_credentials_not_ambient_ones():
    block = _provider_block()
    assert re.search(r'^\s*access_key\s*=\s*"test"\s*$', block, re.M)
    assert re.search(r'^\s*secret_key\s*=\s*"test"\s*$', block, re.M)
    assert not re.search(r"^\s*(profile|token|shared_config_files|shared_credentials_files|assume_role)\b", block, re.M)


def test_layer_b_account_check_is_not_disabled():
    """allowed_account_ids is only meaningful while credential/account lookups still run."""
    code = "\n".join(line for line in _provider_block().splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"allowed_account_ids\s*=\s*\[var\.aws_account_id\]", code)
    assert "skip_credentials_validation" not in code
    assert "skip_requesting_account_id" not in code


def test_no_environment_overrides_or_remote_endpoints_are_hardcoded_in_the_local_root():
    for path in LOCAL.glob("*.tf"):
        code = "\n".join(line for line in _read(path).splitlines() if not line.lstrip().startswith("#"))
        assert "amazonaws.com" not in code, path.name
        # string literals only: a remote URL may not be assigned anywhere in the root
        for literal in re.findall(r'"(https?://[^"]*)"', code):
            assert re.match(r"https?://(localhost|127\.0\.0\.1)\b", literal), (path.name, literal)


def test_local_root_composes_exactly_the_four_expected_modules_and_not_data_or_network():
    modules = re.findall(r'^module "(\w+)"', _read(LOCAL / "main.tf"), re.M)
    assert sorted(modules) == ["app_identity", "data_keys", "observability", "secrets"]
    sources = re.findall(r'source\s*=\s*"([^"]+)"', _read(LOCAL / "main.tf"))
    assert all("modules/data\"" not in s and not s.endswith("/network") and not s.endswith("/data") for s in sources)


def test_local_root_requires_terraform_with_s3_native_locking():
    versions = _read(LOCAL / "versions.tf")
    assert re.search(r'required_version\s*=\s*">=\s*1\.(1[1-9]|[2-9]\d)', versions)
    assert "dynamodb_table" not in _read(LOCAL / "backend.tf")


def test_secrets_module_recovery_window_contract():
    variables = _read(REPO_ROOT / "infra" / "modules" / "secrets" / "variables.tf")
    block = variables[variables.index('variable "recovery_window_in_days"') :]
    assert re.search(r"type\s*=\s*number", block)
    assert re.search(r"default\s*=\s*30\b", block)
    assert re.search(r"var\.recovery_window_in_days == 0 \|\| \(var\.recovery_window_in_days >= 7 && var\.recovery_window_in_days <= 30\)", block)


def test_recovery_window_applies_to_both_secrets_and_only_local_overrides_it():
    main = _read(REPO_ROOT / "infra" / "modules" / "secrets" / "main.tf")
    assert len(re.findall(r'resource "aws_secretsmanager_secret" ', main)) == 2
    assert main.count("recovery_window_in_days = var.recovery_window_in_days") == 2
    assert re.search(r"recovery_window_in_days\s*=\s*0\b", _read(LOCAL / "main.tf"))
    offenders = [
        str(p.relative_to(REPO_ROOT))
        for p in (REPO_ROOT / "infra").rglob("*.tf")
        if "recovery_window_in_days" in _read(p) and p.parts[-3:] not in {("modules", "secrets", "main.tf"), ("modules", "secrets", "variables.tf")}
        and p != LOCAL / "main.tf"
    ]
    assert offenders == [], f"prod root must not override the recovery window: {offenders}"


def test_secrets_resource_is_defined_in_exactly_one_module_file():
    files = [
        str(p.relative_to(REPO_ROOT))
        for p in (REPO_ROOT / "infra").rglob("*.tf")
        if 'resource "aws_secretsmanager_secret"' in _read(p)
    ]
    assert files == ["infra/modules/secrets/main.tf"]


def test_every_trivyignore_entry_is_dated_and_either_no_fix_or_in_the_owner_cooldown_section():
    """AC14: no-fix entries carry a dated revisit-by; fixable ones live only in the owner-accepted,
    temporary cooldown section (operator-kickoff 'Cooldown decision') with an eligibility date and a
    delete-this-line instruction."""
    text = _read(REPO_ROOT / ".trivyignore")
    lines = text.splitlines()
    marker = next((i for i, line in enumerate(lines) if "FIX EXISTS" in line and "cooldown" in line), None)
    assert marker is not None, "cooldown section header missing"
    for i, line in enumerate(lines):
        if not re.fullmatch(r"CVE-\d{4}-\d+", line.strip()):
            continue
        comment = " ".join(lines[i - 1 : i])
        if i < marker:
            assert "no fixed version available" in comment, f"{line}: missing 'no fixed version' note"
            assert re.search(r"revisit-by 20\d\d-\d\d-\d\d", comment, re.I), f"{line}: missing dated revisit-by"
        else:
            assert re.search(r"eligible 20\d\d-\d\d-\d\d", comment), f"{line}: cooldown entry lacks eligibility date"
            assert "delete this line" in comment, f"{line}: cooldown entry lacks removal instruction"
