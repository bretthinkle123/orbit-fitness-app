#!/usr/bin/env python3
"""Identifier-consistency gate for the iOS XCUITest suite (T16).

`Tests/UITests/*.swift`, `Tests/SmokeUITests.swift`, and
`Tests/AccessibilityTests.swift` all query the app's UI by string selector
(`app.buttons["some-id"]`, `matching(identifier: "some-id")`, …). A typo in
one of those strings — or a selector that no longer matches anything a real
Screens/Components file declares — is a silent, never-actually-exercised
test: XCUITest just times out waiting for an element that was never going to
appear, which reads as "the feature is broken" rather than "the test has a
typo." This script is the mechanical half of that check this Linux host CAN
actually run (no Swift toolchain — the Swift COMPILING is the other half,
Mac-execution-only, `.pipeline/implementation-progress.md`'s T11 entry).

Two identifier sources feed the comparison:

1. Every literal string passed to `.accessibilityIdentifier(...)` anywhere
   under `ios/Orbit/{App,Screens,Components,Figures}` — INCLUDING
   interpolated ones (`"train-set-\\(slug)-\\(index)"`), reduced to their
   static PREFIX (the text before the first `\\(`), since a test selector for
   an interpolated identifier can only ever be checked as a prefix match
   (the actual runtime value depends on seeded data the Swift source names
   verbatim in a doc comment, not on anything this script can evaluate).
2. Every element-query selector referenced in the three UI test files
   (`app.buttons["…"]`, `app.textFields["…"]`, `app.otherElements["…"]`,
   `matching(identifier: "…")`, etc.).

A referenced selector "passes" if it exactly matches a declared identifier,
OR starts with a declared interpolated-identifier's static prefix, OR is in
the small, explicitly-documented `KNOWN_NATIVE_LABEL_SELECTORS` allowlist
below (real UI copy a test legitimately looks up by its VISIBLE TEXT rather
than a custom identifier — native `TabView`/`Label` tab titles,
`SegmentedToggle` segment text, system alert/button copy, and the iOS
Settings app's own accessibility strings the Reduce-Motion helper drives).
That allowlist was verified against the actual source this session (see each
entry's comment) — it is not a self-updating mechanism, so a new UI test
selector that legitimately needs a new entry must add one explicitly, not
silently rely on this script staying quiet.

This is a ONE-DIRECTION check (every test selector must resolve to something
real) — it does NOT flag a declared identifier that no test currently
references; an unused identifier is not, by itself, a bug.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IOS_ROOT = REPO_ROOT / "ios" / "Orbit"

SOURCE_DIRS = ["App", "Screens", "Components", "Figures"]
TEST_FILES = [
    IOS_ROOT / "Tests" / "SmokeUITests.swift",
    IOS_ROOT / "Tests" / "AccessibilityTests.swift",
    IOS_ROOT / "Tests" / "UITests" / "AuthFlowUITests.swift",
    IOS_ROOT / "Tests" / "UITests" / "AccountLifecycleUITests.swift",
]

DECLARED_IDENTIFIER_PATTERNS = (
    # `.accessibilityIdentifier("literal")` — the modifier call.
    re.compile(r'\.accessibilityIdentifier\(\s*"([^"]*)"\s*\)'),
    # `accessibilityIdentifier: "literal"` — a labeled constructor argument
    # (e.g. `SignInView.swift`'s `OrbitTextFieldRow(..., accessibilityIdentifier:
    # "signin-email")`, which applies the modifier INTERNALLY to a variable,
    # not a literal, at the point this script's other pattern would look).
    re.compile(r'\baccessibilityIdentifier:\s*"([^"]*)"'),
)
ELEMENT_QUERY_PATTERN = re.compile(
    r"\.(?:buttons|textFields|secureTextFields|staticTexts|otherElements|switches|alerts)"
    r'\[\s*"([^"]+)"\s*\]'
)
MATCHING_IDENTIFIER_PATTERN = re.compile(r'matching\(identifier:\s*"([^"]+)"\)')

# Verified against the actual source this session (T16) — each entry names
# the real Swift literal it maps to, so a future reviewer can re-grep and
# confirm it's still accurate rather than trusting this comment blindly.
KNOWN_NATIVE_LABEL_SELECTORS = {
    # T17: `App/RootTabView.swift`'s native `TabView`/`.tabItem` chrome was
    # REPLACED by `Components/GlassTabBar` (the fidelity-debt closure this
    # task's own scope names) — every tab-switch selector now queries a real
    # `accessibilityIdentifier` (`"tab-home"`/`"tab-fuel"`/`"tab-train"`/
    # `"tab-body"`, `GlassTabBar.swift`'s own `tabButton(for:)`), so this
    # allowlist needs no native-tab-label entry anymore. Kept as a comment,
    # not silently deleted, so a future reader can see WHY there's no
    # "Home"/"Fuel"/"Train"/"Body" entry here despite those being exactly
    # the kind of native-control label this allowlist otherwise documents.
    #
    # `Components/SegmentedToggle.swift` segment `Text` labels (Settings'
    # Units row, Fuel's Meals/By-hour paging toggle).
    "Metric": 'SettingsSheet.swift unitsRow: SegmentedToggle(options: ["metric", "imperial"], ...)',
    "Imperial": 'SettingsSheet.swift unitsRow: SegmentedToggle(options: ["metric", "imperial"], ...)',
    "Meals": "FuelView.swift foodLogHeader: SegmentedToggle(options: [.meals, .byHour], ...)",
    "By hour": "FuelView.swift foodLogHeader: SegmentedToggle(options: [.meals, .byHour], ...)",
    # `Screens/BodyView.swift` figure captions — plain `Text`, not a custom
    # identifier (the figures themselves are `.accessibilityHidden(true)`).
    "Front": 'BodyView.swift muscleLevelsCard: Text("Front")',
    "Back": 'BodyView.swift muscleLevelsCard: Text("Back")',
    # System alert title/button copy (`SettingsSheet.swift`'s
    # `.alert("Delete account?", ...)`) — SwiftUI's native alert chrome, not
    # an app-declared accessibility identifier.
    "Delete account?": 'SettingsSheet.swift: .alert("Delete account?", ...)',
    "Delete": 'SettingsSheet.swift: Button("Delete", role: .destructive) { ... } (alert action)',
    # The iOS Settings app's own accessibility strings, driven by
    # `AccessibilityTests.swift`'s `toggleSystemReduceMotion` helper — not
    # part of this app's bundle at all.
    "Accessibility": "AccessibilityTests.swift toggleSystemReduceMotion: iOS Settings app cell",
    "Motion": "AccessibilityTests.swift toggleSystemReduceMotion: iOS Settings app cell",
    "Reduce Motion": "AccessibilityTests.swift toggleSystemReduceMotion: iOS Settings app switch",
}


def find_swift_files(directory: Path) -> list[Path]:
    """Returns every `.swift` file under `directory`, recursively."""
    return sorted(directory.rglob("*.swift"))


def declared_identifier_prefixes() -> set[str]:
    """Collects every literal `.accessibilityIdentifier(...)` argument from
    the app's own source, reduced to its static (pre-interpolation) prefix."""
    prefixes: set[str] = set()
    for directory_name in SOURCE_DIRS:
        directory = IOS_ROOT / directory_name
        if not directory.is_dir():
            continue
        for swift_file in find_swift_files(directory):
            text = swift_file.read_text(encoding="utf-8")
            for pattern in DECLARED_IDENTIFIER_PATTERNS:
                for match in pattern.finditer(text):
                    literal = match.group(1)
                    static_prefix = literal.split("\\(", 1)[0]
                    prefixes.add(static_prefix)
    return prefixes


def referenced_selectors() -> list[tuple[str, int, str]]:
    """Collects every `(file, line_number, selector)` the UI test files
    reference via an element-query subscript or `matching(identifier:)`."""
    references: list[tuple[str, int, str]] = []
    for test_file in TEST_FILES:
        if not test_file.is_file():
            continue
        for line_number, line in enumerate(test_file.read_text(encoding="utf-8").splitlines(), start=1):
            for pattern in (ELEMENT_QUERY_PATTERN, MATCHING_IDENTIFIER_PATTERN):
                for match in pattern.finditer(line):
                    references.append((str(test_file.relative_to(REPO_ROOT)), line_number, match.group(1)))
    return references


def selector_resolves(selector: str, declared_prefixes: set[str]) -> bool:
    """A selector is consistent if it exactly matches a declared identifier,
    starts with a declared interpolated identifier's static prefix, or is a
    documented native-control/UI-copy exception."""
    if selector in declared_prefixes:
        return True
    if selector in KNOWN_NATIVE_LABEL_SELECTORS:
        return True
    return any(prefix and selector.startswith(prefix) for prefix in declared_prefixes)


def main() -> int:
    """Runs the consistency check and prints a summary; exits 1 on any
    unresolved selector."""
    if not IOS_ROOT.is_dir():
        print("check_ui_test_identifier_consistency: no ios/Orbit directory yet — nothing to check, exiting clean.")
        return 0

    declared_prefixes = declared_identifier_prefixes()
    references = referenced_selectors()

    mismatches = [
        (file_path, line_number, selector)
        for file_path, line_number, selector in references
        if not selector_resolves(selector, declared_prefixes)
    ]

    print(f"check_ui_test_identifier_consistency: {len(references)} selector reference(s) checked "
          f"against {len(declared_prefixes)} declared identifier prefix(es).")

    if mismatches:
        print("check_ui_test_identifier_consistency: UNRESOLVED selector(s) found:", file=sys.stderr)
        for file_path, line_number, selector in mismatches:
            print(f"  {file_path}:{line_number}: \"{selector}\" matches no declared accessibilityIdentifier "
                  f"and is not in KNOWN_NATIVE_LABEL_SELECTORS", file=sys.stderr)
        return 1

    print("check_ui_test_identifier_consistency: clean — every UI test selector resolves.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
