# `scripts/` — operational + CI helper scripts

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

Standalone scripts that support the app or the pipeline but aren't part of the served
API: a DAST test-user seeder, two mechanical consistency checkers for the iOS build, and
the CI re-run scripts under `ci/` that `pipeline-ci.yml` invokes on the merge commit.

## Modules

| File | Responsibility |
|---|---|
| `seed_dast_user.py` | Seeds a non-production, low-privilege Firebase test user for the DAST scanner to authenticate as (`dast-conventions` DAST-2/DAST-3); idempotent (reuses the account if it already exists); refuses to run when `ENVIRONMENT` is `production`/`prod`. |
| `check_ui_test_identifier_consistency.py` | Verifies every string selector the iOS XCUITest suite queries by (`Tests/UITests/*.swift`, `SmokeUITests.swift`, `AccessibilityTests.swift`) actually matches a declared accessibility identifier in `Screens/`/`Components/` — catches a typo'd or stale selector that would otherwise silently never exercise anything. |
| `check_no_inline_hex.sh` | Enforces AC28's "no hardcoded hues" rule: every hex color literal in the iOS Swift sources must live inside `ios/Orbit/DesignSystem/`. |
| `ci/store-compliance.sh` | Deterministic Apple App Store submission checks (Tier-1) — writes `.pipeline/store-compliance.json`; deployment gate blocks on `critical > 0`. |
| `ci/dast-review.sh` | Compares a captured OWASP ZAP passive-baseline report against a per-severity budget; writes the advisory `.pipeline/dast-review.json`. Requires a prior capture (`dast-capture.sh`, run separately) — not exercised this run (`dast.env` not opted in). |
| `ci/lockfile-check.sh` | Supply-chain integrity: flags a manifest changed without its lockfile, unpinned version specifiers, or a lockfile-only re-lock. |
| `ci/asvs-sast.sh` | Deterministic subset of ASVS 5.0.0 checks promoted to a grep scan over the diff-scoped change set (cross-language). |
| `ci/guard-source-markers.sh` | Blocks a changed file that still carries an experimental/reverted-fix marker from shipping. |

## Relationships

`seed_dast_user.py` and the two `check_*` scripts are run ad hoc (by implementation/CI,
respectively) against the working tree. Everything under `ci/` is the same script CI
re-runs against the merge commit that ran pre-merge locally — they read only the
diff-scoped change set (`SCAN_BASE`), never the whole repo, and never trust
`.pipeline/` artifacts as their own input.

## Notes

- `ci/` scripts are copied into the repo at bootstrap (committed, human-reviewed,
  pinned) so CI never fetches remote script content at run time.
- Waivers CI honors are **only** committed, tool-native ignore files
  (`.trivyignore`, `.semgrepignore`, `osv-scanner.toml`) — `.pipeline/waivers.json` is
  local-only and never reaches CI.
