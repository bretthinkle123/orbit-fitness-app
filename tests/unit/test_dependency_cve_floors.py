"""Pin guards: every locked (and installed) dependency stays at or above its CVE-clearing floor.

A floor is added when a gating advisory (unwaived, CVSS >= 7.0) is fixed by a dependency bump, so a
later lock regeneration or a stale venv cannot silently reintroduce the vulnerable version.
"""

from __future__ import annotations

import tomllib
from importlib.metadata import version as installed_version
from pathlib import Path

import pytest
from packaging.version import Version

POETRY_LOCK = Path(__file__).resolve().parents[2] / "poetry.lock"

_PYASN1_COOLDOWN = (
    "pyasn1 0.6.5 (the only fixed release) was published 2026-10-27 and is inside the 14-day "
    "dependency cooldown until 2026-11-10. Once it is bumped this XPASSes: delete the xfail mark."
)

CVE_FLOORS = [
    pytest.param("certifi", "2026.10.18", id="certifi-GHSA-6q48-6c7w-9gw2"),
    pytest.param("msgpack", "1.2.3", id="msgpack-GHSA-j586-36cw-2gc2"),
    pytest.param(
        "pyasn1",
        "0.6.5",
        id="pyasn1-GHSA-2qm8-x737-gmw5,9m75-vc3g-4x39,fm9c-5rcf-2q5p,mm57-4v3p-rchx",
        marks=pytest.mark.xfail(strict=True, reason=_PYASN1_COOLDOWN),
    ),
]


def _locked_versions() -> dict[str, str]:
    lock = tomllib.loads(POETRY_LOCK.read_text(encoding="utf-8"))
    return {package["name"]: package["version"] for package in lock["package"]}


@pytest.mark.parametrize(("package", "floor"), CVE_FLOORS)
def test_locked_version_is_at_or_above_cve_floor(package: str, floor: str) -> None:
    locked = _locked_versions()
    assert package in locked, f"{package} is no longer in poetry.lock; drop its floor"
    assert Version(locked[package]) >= Version(floor), f"poetry.lock pins {package} {locked[package]} < {floor}"


@pytest.mark.parametrize(("package", "floor"), CVE_FLOORS)
def test_installed_version_is_at_or_above_cve_floor(package: str, floor: str) -> None:
    have = installed_version(package)
    assert Version(have) >= Version(floor), f"venv has {package} {have} < {floor}; run `poetry sync`"
