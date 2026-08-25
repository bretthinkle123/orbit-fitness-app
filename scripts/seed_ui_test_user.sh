#!/usr/bin/env bash
# Seed the Firebase Auth emulator account the iOS XCUITest suite signs in as.
#
# Why this exists: `AuthFlowUITests.testSignInWithExistingAccountReachesThe
# SignedInTabShell` and `AccountLifecycleUITests.testSignOutReturnsToSignIn
# AndAFreshSignInWorksAfterward` both sign in as a PRE-EXISTING account. Until
# this script, nothing in the repo created it — it was seeded by hand on the
# operator's Mac, so the two tests passed there and failed on any other machine
# (or after an emulator wipe/restart) with a symptom that reads like a UI
# regression rather than missing fixture data. On 2026-08-24 clearing the
# emulator's accounts to unblock the backend suite broke exactly these two
# tests; that is the failure mode this closes.
#
# The Swift test file is the SINGLE SOURCE OF TRUTH for the credentials — they
# are parsed out of it below rather than duplicated here, so renaming the
# constant in Swift can never silently desync the seeder (the same
# "no second copy" rule `scripts/check_ui_test_identifier_consistency.py`
# enforces for selectors).
#
# Idempotent, like `seed_dast_user.py`: a re-run against an emulator that
# already has the account verifies the password still signs in rather than
# erroring on the duplicate — so it is safe to call before every UI run.
#
# Emulator-only by construction: it talks plain HTTP to
# `FIREBASE_AUTH_EMULATOR_HOST` and refuses to run without one, so it can never
# touch a real Firebase project.
#
# macOS portability, per `check_simulator_storage.sh`: bash 3.2 compatible — no
# `mapfile`, no `declare -A`; and no GNU-only tools.
#
# Usage:
#     scripts/seed_ui_test_user.sh
#     FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 scripts/seed_ui_test_user.sh
#
# Exit codes: 0 = account ready (created or already valid), 1 = emulator
# unreachable, 2 = the account exists but its password no longer matches the
# Swift constant (drift a re-run cannot fix — delete the account, or reconcile).
set -euo pipefail

EMULATOR_HOST="${FIREBASE_AUTH_EMULATOR_HOST:-localhost:9099}"
# The emulator ignores this value entirely; mirrors `tests/conftest.py`'s
# `_EMULATOR_API_KEY`. A real project would need the genuine Web API key, which
# is exactly why this script is emulator-only.
API_KEY="fake-api-key"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_FIXTURES="$REPO_ROOT/ios/Orbit/Tests/UITests/AuthFlowUITests.swift"

if [ ! -f "$SWIFT_FIXTURES" ]; then
  echo "seed_ui_test_user: cannot find $SWIFT_FIXTURES" >&2
  exit 1
fi

# Pull `static let <name> = "<value>"` out of the Swift fixtures block.
extract_swift_constant() {
  sed -n "s/^[[:space:]]*static let $1 = \"\\(.*\\)\"[[:space:]]*\$/\\1/p" "$SWIFT_FIXTURES"
}

EMAIL="$(extract_swift_constant seededTestEmail)"
PASSWORD="$(extract_swift_constant testPassword)"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "seed_ui_test_user: could not parse seededTestEmail/testPassword from" >&2
  echo "  $SWIFT_FIXTURES" >&2
  echo "  (were the constants renamed? this script must be updated with them)" >&2
  exit 1
fi

identity_toolkit_url() {
  echo "http://$EMULATOR_HOST/identitytoolkit.googleapis.com/v1/$1?key=$API_KEY"
}

post_json() {
  curl -s -X POST "$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null || true
}

CREDENTIALS_JSON="{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"returnSecureToken\":true}"

if ! curl -s -o /dev/null --max-time 5 "http://$EMULATOR_HOST/" 2>/dev/null; then
  echo "seed_ui_test_user: no Firebase Auth emulator reachable at $EMULATOR_HOST" >&2
  echo "  start one with: firebase emulators:start --only auth --project demo-orbit-test" >&2
  exit 1
fi

SIGNUP_RESPONSE="$(post_json "$(identity_toolkit_url accounts:signUp)" "$CREDENTIALS_JSON")"

case "$SIGNUP_RESPONSE" in
  *'"idToken"'*)
    echo "seed_ui_test_user: created $EMAIL on $EMULATOR_HOST"
    exit 0
    ;;
  *EMAIL_EXISTS*)
    # Already seeded. Prove the stored password still matches the Swift
    # constant — otherwise the UI tests would fail with a sign-in error that
    # looks like an app bug.
    SIGNIN_RESPONSE="$(post_json "$(identity_toolkit_url accounts:signInWithPassword)" "$CREDENTIALS_JSON")"
    case "$SIGNIN_RESPONSE" in
      *'"idToken"'*)
        echo "seed_ui_test_user: $EMAIL already present on $EMULATOR_HOST and signs in"
        exit 0
        ;;
      *)
        echo "seed_ui_test_user: $EMAIL exists but will NOT sign in with the password in" >&2
        echo "  $SWIFT_FIXTURES" >&2
        echo "  delete the account (or wipe the emulator) and re-run this script." >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "seed_ui_test_user: unexpected signUp response from $EMULATOR_HOST:" >&2
    echo "  $SIGNUP_RESPONSE" >&2
    exit 1
    ;;
esac
