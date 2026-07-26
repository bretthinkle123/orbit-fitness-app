#!/usr/bin/env bash
# Machine-checked half of AC28's "no hardcoded hues outside the palette
# definitions" rule (CLAUDE.md: "iOS: theme = `Theme` struct computed from the
# 3-color palette (never hardcode hues)"). Every hex color literal in the iOS
# Swift sources must live inside `ios/Orbit/DesignSystem/` — that is where the
# palette presets, derived tints, and neutrals are declared once; every other
# file must go through `Theme`/`Metrics` rather than writing a second hex
# literal of its own.
#
# This is a grep-based, structural check — it cannot tell whether a hex value
# is "the same color as the theme" (that's what `ThemeTests.swift`'s blend-math
# assertions verify), only whether one appears at all outside the one directory
# allowed to define them. Run on the operator's Mac alongside the Swift test
# suite (`.pipeline/implementation-progress.md` T11 entry: authored, not run,
# on this Linux host — no Swift files exist to violate the rule yet beyond
# DesignSystem itself, so this script is the only part of AC28's grep clause
# actually exercised here).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_ROOT="${REPO_ROOT}/ios/Orbit"
DESIGN_SYSTEM_DIR="${IOS_ROOT}/DesignSystem"
# Tests/ gets the same pass: `ThemeTests.swift` asserts the blend math against
# independently-computed expected-value literals (fixture data proving
# DesignSystem is correct), never a color an app screen actually renders with —
# the same "documented test-only exception" shape the backend's own
# hardcoded-secret grep already carries for emulator-only constants.
TESTS_DIR="${IOS_ROOT}/Tests"

if [ ! -d "${IOS_ROOT}" ]; then
  echo "check_no_inline_hex: no ios/Orbit directory yet — nothing to check, exiting clean." >&2
  exit 0
fi

# Matches a `#` followed by exactly 3, 6, or 8 hex digits inside a Swift string
# literal or comment — anchored to the hex shapes Color(hex:) actually accepts
# (plus the CSS 3-digit shorthand, in case one is ever pasted in verbatim).
HEX_PATTERN='#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3}([0-9A-Fa-f]{2})?)?'

violations="$(
  find "${IOS_ROOT}" -type f -name '*.swift' \
    -not -path "${DESIGN_SYSTEM_DIR}/*" \
    -not -path "${TESTS_DIR}/*" \
    -print0 \
  | xargs -0 -r grep -nEo "${HEX_PATTERN}" /dev/null \
  || true
)"

if [ -n "${violations}" ]; then
  echo "check_no_inline_hex: hardcoded hex color literal(s) found outside DesignSystem/:" >&2
  echo "${violations}" >&2
  echo "Route new colors through Theme/Metrics instead of a new hex literal." >&2
  exit 1
fi

echo "check_no_inline_hex: clean — no hex color literals outside ios/Orbit/DesignSystem/."
exit 0
