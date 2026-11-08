"""AC12: the app has no environment-conditional branches; local differences are config only.

The local stack works by supplying environment variables (AWS_ENDPOINT_URL, the Firebase
emulator host) that the app's libraries already honour. If app code ever starts testing for
"local" itself, the local stack stops exercising the production code path.
"""

from __future__ import annotations

import ast
import re
from pathlib import Path

SOURCE_ROOT = Path(__file__).resolve().parents[2] / "src" / "orbit"

FORBIDDEN_PATTERNS = [
    re.compile(pattern)
    for pattern in (
        r"AWS_ENDPOINT_URL",
        r"endpoint_url",
        r"localstack",
        r"moto",
        r"FIREBASE_AUTH_EMULATOR_HOST",
        r"environment\s*(==|!=|in)",
        r"is_local",
        r"if .*\blocal\b",
    )
]

# The one pre-existing occurrence: the Firebase SDK's own emulator toggle, which predates A1.
# Pinned by file AND exact line content, so any second occurrence (or a changed line) fails.
ALLOWED_OCCURRENCES = {
    ("auth/firebase.py", '    if os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"):'),
}


def _docstring_line_numbers(text: str) -> set[int]:
    """Line numbers (1-based) covered by module, class and function docstrings.

    Prose that merely mentions a forbidden name (for example in an explanation of why the
    Firebase toggle exists) is documentation, not a branch, so it is excluded from the scan.
    """
    covered: set[int] = set()
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            first = node.body[0] if node.body else None
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                covered.update(range(first.lineno, first.end_lineno + 1))
    return covered


def _violations(files: dict[str, str]) -> list[tuple[str, int, str]]:
    """Return (file, line number, line) for each forbidden-pattern hit not on the allowlist."""
    found = []
    for relative_path, text in files.items():
        docstring_lines = _docstring_line_numbers(text)
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line_number in docstring_lines or line.lstrip().startswith("#"):
                continue
            if (relative_path, line) in ALLOWED_OCCURRENCES:
                continue
            if any(pattern.search(line) for pattern in FORBIDDEN_PATTERNS):
                found.append((relative_path, line_number, line.strip()))
    return found


def _read_source_tree() -> dict[str, str]:
    """Read every Python file under src/orbit, keyed by path relative to it."""
    return {
        str(path.relative_to(SOURCE_ROOT)): path.read_text(encoding="utf-8")
        for path in SOURCE_ROOT.rglob("*.py")
    }


def test_app_source_has_no_environment_branches():
    assert _violations(_read_source_tree()) == []


def test_the_allowlisted_occurrence_still_exists_exactly_as_pinned():
    """If the pinned line moves or changes, the allowlist must be re-reviewed, not silently dropped."""
    source = _read_source_tree()
    for relative_path, pinned_line in ALLOWED_OCCURRENCES:
        assert pinned_line in source[relative_path].splitlines()


def test_a_second_occurrence_is_caught():
    """Self-test: the scan really fails on a synthetic second hit, including next to the allowed one."""
    source = _read_source_tree()
    source["auth/firebase.py"] += '\nif os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"):\n    pass\n'
    assert len(_violations(source)) == 1
    source["config/secrets.py"] = 'client = boto3.client("s3", endpoint_url="http://x")\n'
    assert len(_violations(source)) == 2
    source["main.py"] = 'if settings.environment == "local":\n    pass\n'
    assert len(_violations(source)) == 3
