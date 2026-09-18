# Orbit greenfield — full depicted app, end-to-end

> Plan + threat model: `.pipeline/plan.md` (retained on this branch at
> `docs/decisions/feature/greenfield/plan.md`). Acceptance criteria:
> `.pipeline/acceptance.md` (retained alongside it).

## Assurance

**This run's overall assurance is `reduced (swift adapters absent)`** per
`.pipeline/run-summary.json`. The native-iOS (Swift/SwiftUI) portion is the reason: the
pipeline's deterministic gates (Semgrep, OSV, Trivy, Checkov, pytest coverage) have no
Swift adapter and analyze essentially no Swift. **Do not read this run as
"gate-verified" for `ios/Orbit/`** — every file there was authored on a Linux host with
no Swift toolchain (confirmed absent every iOS task session) and is verified only by
authored Swift Testing / XCUITest / snapshot suites plus human review, first compiled
and run on the operator's Mac (`plans/00-mac-pipeline-readiness.md` Phase 5). The
**backend carries full deterministic gate coverage** — this reduced-assurance stamp
applies only to the iOS half.

## Summary

Builds the full depicted Orbit app end-to-end: a native SwiftUI iOS client replicating
the approved Claude Design export over a new Python 3.12/FastAPI/PostgreSQL backend,
Firebase email/password auth behind a `require_auth` facade, and an AWS data-security
Terraform baseline. Backend: owner-scoped REST API (18 tasks, T1–T10), every domain row
keyed by Firebase UID, every collection query day-/window-bounded with a hard `LIMIT`.
iOS: 4 tabs + Settings + 25 components + starfield + SceneKit hero scenes (T11–T18),
staged so visual fidelity landed last. Full plan + STRIDE threat model:
`.pipeline/plan.md` (`docs/decisions/feature/greenfield/plan.md`).

## Changes

- **Backend (`src/orbit/`):** app + edge-middleware stack, auth facade, 9-table schema
  (`migrations/`) + seeds, 7 domain routers (profile/fuel/train/body/weight/me/health),
  owner-scoped bounded repositories, structlog + Sentry, account-deletion cascade.
- **Infra (`infra/`):** AWS data-security baseline — RDS (SSE, multi-AZ), ElastiCache
  Redis, Secrets Manager/SSM, CloudWatch (delete-deny audit group), VPC/security groups.
  Compute (ALB/ECS/`envs/` split) deliberately deferred — see
  `docs/system_architecture.md` §Deployment topology.
- **iOS (`ios/Orbit/`):** DesignSystem/Theme, Core (APIClient/AuthService/AppStore),
  App composition root, 25 components, 5 screens + 3 editor sheets, verbatim muscle
  figures, starfield + SceneKit heroes, accessibility pass.
- **Tests (`tests/`, `ios/Orbit/Tests/`):** 142 backend tests (unit + integration +
  perf); iOS Swift Testing/XCUITest/snapshot suites authored, Mac-execution-only.
- **CI (`.github/workflows/`):** merge-gate + deploy + DAST/provenance workflows filled
  in (`pipeline-ci.yml` install/build/test/coverage-floor placeholders).
- **Docs:** this PR description, `docs/system_architecture.md` (new), directory
  READMEs (`src/orbit/`, `migrations/`, `infra/`, `ios/Orbit/` updated, `tests/`,
  `scripts/`), root `README.md` (new), `docs/decisions/feature/greenfield/` (design
  record retention — plan/acceptance/plan-audit/security-report/design-spec/
  run-summary copied out of gitignored `.pipeline/`).

## Decisions & tradeoffs

- **Thin owner-scoped REST over an aggregate `GET /home`** — each endpoint
  independently bounded/rate-limited/perf-measured; the client composes Home via 4
  parallel `async let` calls instead.
- **Infra depth this run = data-security baseline only** (RDS/Redis/Secrets/logs/state);
  compute topology deferred to `plans/01-production-deploy-path.md` so it can be
  Checkov-scannable and real rather than a stack of waivers.
- **`day_key` = user's device-tz local date**, client-sent; timestamps backdatable,
  future (> server now) rejected 422.
- **Gram macro targets are canonical** (2,350 kcal · P185/C240/F72 g); the Settings
  "40/35/25" copy is a prototype defect — the split row displays the **derived** %
  (≈31/41/28).
- **XcodeGen `project.yml`, not a hand-authored `.xcodeproj`** — a hand-edited
  `project.pbxproj` on a host with no Xcode to validate it risks silently failing to
  open; `project.yml` is plain-diffable YAML the Mac-phase generates from.
- **`muscle_level_templates`** — a 4th global seed table beyond the plan's literal
  9-table list, holding the per-user defaults `POST /me/bootstrap` copies, so seeding
  isn't duplicated inline in app code.
- **`.coveragerc`** — added `concurrency = greenlet,thread` (T4) so async-session
  coverage is measured correctly; benefits every later task.
- **Fonts (Space Grotesk/DM Sans) not yet bundled** — `Resources/Fonts/FONTS-TODO.md`
  names the exact files/URLs; `Font+Theme.swift` falls back to SF Pro Rounded/SF Pro
  at runtime until they land, no other code changes needed then.
- **Full judgment-call/deviation list** (each also flagged at its own task in
  `.pipeline/implementation-progress.md`):
  1. Profile display-only defaults (`tier_label="Beginner"`, etc.) for a brand-new
     account, not the design's mid-progression demo copy.
  2. Static coach-message string (adaptive TDEE engine deferred, `docs/roadmap.md`).
  3. Train/Body "today"/"this week" computed off the **client's** `day_key`, not the
     server clock — consistent with the day-keyed architecture.
  4. `SignInView`/`RegisterView` are minimal undepicted-screen builds per the design
     README's "Extending the UI" conventions (no onboarding carousel, no social login).
  5. `GlassTabBar`/`RootTabView` wiring deliberately deferred from T16 to T17's session.
  6. Sign-in/register starfield seeds (9/10) are simply the next two integers in the
     same seeded sequence — the design names no starfield for these undepicted screens.
  7. T18 SceneKit scope simplifications (all named in the README's own 3D-spec bullets,
     not silently dropped): Home's cruiser-ship → a simple emissive moonlet; Fuel's
     food-shaped moons → plain tinted spheres; Train's tethered-astronaut collision
     choreography → omitted; Fuel's "pulse on quick-add" moon-scale bump → deferred
     (parameter present, defaults to `0`); Train's heat denominator → derived from the
     live program's actual set count, not the design's hardcoded `16`.

## Testing

**33 test-covered + 1 delegated to security** (`AC33` — ASVS 5.0 L1/L2 reconciliation,
`.pipeline/test-results.json` `criteria_covered.by_id`, `"delegated": "security"`) — of
**34 total acceptance criteria**. None are neither covered nor delegated.

- **142/142 tests pass** (36 unit, 106 integration, 0 e2e — realized shape leans
  integration-heavy vs. the declared `pyramid`, an honest divergence: most criteria
  (ownership, bounded queries, rate limiting, migrations, atomic rollback) are only
  truthfully provable against a real testcontainers Postgres + Firebase emulator).
- **Coverage: 97.07% lines / 91.51% branches** (combined), well above the 80% floor.
- **Performance:** p95 20.89 ms (`GET /fuel`) / 25.26 ms (`GET /train`) / 27.22 ms
  (`POST /fuel/entries`) @ constant-arrival-rate 10 req/s — all well under the 300 ms
  budget (`AC23`), measured out-of-process (uvicorn + testcontainers Postgres/Redis +
  real Firebase emulator), true nearest-rank k6 percentile.
- **Test quality (advisory — `.pipeline/test-quality.json`): `quality_ok: false`.** No
  mutation score exists this run — `mutmut` is not a project dependency; an ad-hoc
  install/run failed (`BadTestExecutionCommandsException`) before producing a
  kill/survive report, and the half-working scaffolding was deliberately reverted
  rather than left polluting the tracked tree. **6 falsifiability probes ran instead**
  as the deterministic substitute for the highest-value security-property tests this
  session (each: break the mechanism → confirm the test goes RED → restore → GREEN):
  redaction stripping, safe-error no-leak, cross-owner weight-window isolation,
  sign-out token revocation, and the two new read-side `LIMIT` backstops (food/weight).
  Notable adversarial gaps the reviewer should weigh: no test enumerates all five named
  audit categories by an explicit label (coverage is by mechanism, not taxonomy); the
  single **chained** AC27 smoke walkthrough exists only as an authored, not-yet-executed
  iOS XCUITest; all snapshot-based fidelity evidence has **no reference images recorded
  yet** (first Mac-phase run creates them); the broader business-logic surface
  (score/week-strip/macro-split/day-key math) has not been mutation-tested despite high
  line/branch coverage.
- **Known XCTSkips / advisory-only iOS items** (all authored, none gate-backed on this
  host): `ComponentSnapshotTests`/`ScreenSnapshotTests`/`StarfieldSnapshotTests`/
  `HeroSceneSnapshotTests` are advisory per `swift-conventions` and have no reference
  images yet; `AccessibilityTests.swift`'s Reduce-Motion UI test is flagged
  best-effort/iOS-version-fragile in its own header; `ScreenSnapshotTests.swift` flags
  an unverified-without-a-device uncertainty about `ErrorStateView`'s accessibility
  flattening; `HeroSceneSnapshotTests.swift` cannot snapshot the live `HeroSceneView` at
  all (idle spin is deliberately left unfrozen under Reduce Motion, unlike Starfield's
  full freeze) — only `HeroSceneState` directly; iOS coverage % is not auto-collected
  (no `xccov` adapter yet).

## Security

**Status: clean.** Scope = the whole working tree (diff, since the initial commit is a
bare skeleton; 106 code-shaped files). 0 critical findings remain; **33 total findings**
inventoried (`.pipeline/security-report.md`): **4 fixed** (blocking SDK calls on the
event loop — exploitable; request-size-limit middleware absent — exploitable; Sentry PII
suppression made explicit; `tests/` was silently excluded from every Semgrep scan — a
scan-coverage hole, now closed via a committed `.semgrepignore`), **1 latent/deliberately
not fixed** (`ProxyHeadersMiddleware` XFF trust — no ALB exists yet to trust a CIDR
from; configuring it now would let any client spoof `X-Forwarded-For`), **3 accepted-risk
reclassifications** (Trivy `AWS-0104` unrestricted egress ×3 — ingress is fully
restricted; narrowing egress needs a NAT/VPC-endpoint topology that doesn't exist until
compute lands; recorded in a committed `.trivyignore` so CI can't merge them red), and
**2 human-recorded waivers** (below). Checkov: **166 passed / 0 failed / 26 documented
skips** on `infra/`. Apple store-compliance: **0 critical / 0 warning / 0 findings**.
ASVS 5.0 reconciliation: **41 requirements verified** across 13 triggered chapters,
`reconciled: true`.

### ASVS waivers — human-recorded (`.pipeline/waivers.json`, approved_by Brett)

- **`6.3.3`** (MFA/combination of single factors) — out of scope for this run
  (requirements); single-factor email/password via Firebase. Deferral tracked in
  `docs/roadmap.md`. Nothing further owed this run.
- **`6.2.x`** (password composition/breach/length policy) — waived as **delegated to
  Firebase, not as already enforced**. **No password-strength policy is active in any
  environment today.**
  > ⚠ **Open follow-up, carried into roadmap run 1
  > (`plans/01-production-deploy-path.md`): enable the Firebase Authentication
  > password policy at deploy**, then re-verify ASVS `6.2.x` against a real
  > (non-emulator) Firebase project. Until then, password strength is whatever
  > Firebase's default allows.

## Supply chain

- **Lockfile integrity:** clean — dependency manifests (`pyproject.toml`) and their
  lockfile (`poetry.lock`) are in sync; no unpinned-dependency warnings
  (`.pipeline/security-report.md` "Lockfile integrity | change set | clean"). OSV
  Scanner: 0 vulnerabilities across 73 packages.
- **SBOM:** `.pipeline/sbom.cdx.json` was **not generated this run** — no CycloneDX SBOM
  artifact is present. The deployment gate checks for this file before allowing a
  deploy; it will need to be produced before this branch can deploy.

## Design review (FE Layer 4)

**Design review (FE Layer 4): skipped — ui.env not wired.** This run used a design source
(`.pipeline/design-approved` + `.pipeline/design-spec.md` are both present), but
`.pipeline/design-review.json` does not exist — the `ui.env`-gated design-review stage
never ran. The built iOS UI's visual fidelity to the approved design spec has been
**machine-checked by nothing** this run; the only fidelity evidence is the (as-yet
reference-image-less) advisory snapshot suites above and human diff-review, which has
not yet occurred at this pipeline stage.

## DAST (runtime)

**Not opted in this run** (`dast.env` absent) — `.pipeline/dast-review.json` does not
exist, so no OWASP ZAP passive-baseline pass ran against this build. DAST-**readiness**
artifacts DO exist per `AC26`: the served OpenAPI schema matches the implemented routes
exactly, and `scripts/seed_dast_user.py` (a non-production, low-privilege Firebase test
user, refuses to run against `production`/`prod`) is present and tested. The gating DAST
layers run in CI against staging (`.github/workflows/dast-staging.yml`), not in this
pipeline run.

## Threat model

Full STRIDE table + Mermaid DFD: `.pipeline/plan.md` §Threat Model
(`docs/decisions/feature/greenfield/plan.md`). **18 of 18 STRIDE mechanisms verified**,
0 missing, 0 new attack surface introduced beyond the plan's text
(`stride_new_threats: 0`). High-severity threats and their mitigations: forged/expired
ID token → `require_auth` + `verify_id_token(check_revoked=True)`; SQL injection →
SQLAlchemy parameterized/ORM only; mass assignment → `owner_uid` always from the token,
never the body, `PATCH /profile` allowlists fields; secret leak → Secrets Manager +
`get_secret()` facade, never in source/env/`.tfvars`/logs; over-broad response → owner-
scoped queries + response-schema allowlists; IDOR/BOLA → every repository query scoped
by `(id AND owner_uid)`, cross-owner → 404 (no route even takes an id path parameter).

## Verification coverage — what was and was NOT verified

### VERIFIED

- **Backend tests:** 142/142 passed; 97.07% line / **91.51% branch** coverage;
  34 acceptance criteria — 33 covered by name-cited tests, 1 (`AC33`) delegated to and
  reconciled by security (`test-results.json` `criteria_covered.by_id`).
- **Performance:** p95 20.89/25.26/27.22 ms vs. the 300 ms budget, measured fresh this
  session (`test-results.json.perf`).
- **Security scanners, this pass** (`security-status.json` + `scan-log.jsonl` stamps):
  Semgrep (654 rules, 233 files), OSV Scanner (73 packages), Gitleaks (full tree),
  Trivy fs (vuln+secret+misconfig, full tree), Checkov (`infra/`, 166/0/26), ASVS Tier-1
  SAST (`.pipeline/asvs-sast.json`, 0 critical, ran `2026-07-26T00:35:38Z`), Apple
  store-compliance (`.pipeline/store-compliance.json`, 0 critical/0 warning, ran
  `2026-07-26T00:35:37Z`), ast-grep (advisory, 4 hits → all fixed), lockfile integrity
  (clean). All confirmed via `scan-log.jsonl` execution stamps this pass, not carried
  over from a stale run.
- **Smoke:** `smoke-status.json` → `pass` (`2026-07-25T19:17:26Z`).
- **ASVS reconciliation:** 41 requirements verified across 13 triggered chapters,
  both missing-lists empty, reached via 2 honored human waivers (not by emptying a list).
- **Criteria delegated to security, reconciled:** `AC33` — `security-status.json`
  `asvs.reconciled: true`.

### NOT VERIFIED

- **iOS/Swift (`.assurance: "reduced (swift adapters absent)"`):** no Swift compilation,
  `swift test`, XCUITest execution, or snapshot review has happened anywhere in this
  pipeline run. Every claim about `ios/Orbit/` (theme math, screen composition,
  accessibility traits, hero-scene geometry, the full AC27 smoke chain) rests on
  authored-but-unexecuted test source and manual brace/paren-balance checks, not a
  passing test run. First real execution happens on the operator's Mac
  (`plans/00-mac-pipeline-readiness.md` Phase 5).
- **Mutation testing:** not run (`test-quality.json` `quality_ok: false`, `mutation.tool:
  "none"`) — no mutation score exists for any changed module. 6 falsifiability probes
  substituted for the highest-value security-property assertions only; the broader
  business-logic surface (score/week-strip/macro-split/day-key math) is unassessed by
  mutation.
- **Design review (FE Layer 4):** skipped — `ui.env` not wired, `design-review.json`
  absent despite a design source being present this run (see above). No visual-fidelity
  diff of any kind has run against the approved design spec.
- **DAST runtime scan:** not opted in (`dast.env` absent, `dast-review.json` absent).
  No OWASP ZAP pass has been run against this build in this pipeline; only run in CI
  against staging.
- **SBOM:** not generated this run (`sbom.cdx.json` absent) — component inventory is
  unverified beyond the lockfile-integrity check above.
- **Per-file coverage:** **not preserved — aggregate only.** No `coverage.xml`/
  `.coverage`/lcov artifact was retained alongside `test-results.json`'s combined
  97.07%/91.51% figures, so no diff-touched file's individual coverage can be cited by
  name here.
- **`ProxyHeadersMiddleware` / XFF trust:** deliberately unconfigured (security-report
  row 30) — latent until an ALB exists; not exercised because the mechanism it would
  configure has no target yet.
- **Acceptance criteria neither covered nor delegated:** none — all 34 are either
  covered (33) or delegated-and-reconciled (`AC33`); the gate blocks otherwise.
- **iOS coverage percentage:** not auto-collected (no `xccov` adapter in this pipeline
  yet) — reported manually once the Mac-phase run produces a number.
- **Fonts:** Space Grotesk/DM Sans not yet bundled (`Resources/Fonts/FONTS-TODO.md`);
  the app currently renders with the SF Pro fallback until they're added.
- **`terraform apply` / live AWS account:** this run validated `infra/` credential-less
  (`offline_validate = true`); no real AWS account exists yet, so nothing in `infra/`
  has been applied or observed running.

## Post-review CI fix

`build-and-test` failed on the CI runner because `poetry config virtualenvs.create false`
installed into the runner's system Python, colliding with a root-owned `botocore`
(pre-installed on `ubuntu-latest`, transitively required by our pinned `boto3`). Fixed by
letting Poetry manage its own venv and routing every dependent step through `poetry run`
(`.github/workflows/pipeline-ci.yml`) — root-caused and container-proven; see
`.pipeline/debug-notes.md`.

**Blocker #2 (same file):** with that fixed, `build-and-test` still failed because
`tests/conftest.py`'s session-scoped fixture boots a real Firebase Auth emulator and
`ubuntu-latest` doesn't ship `firebase-tools`. Fixed by exact-pinning and installing
`firebase-tools@15.18.0` plus a SHA-pinned cache step for the emulator JAR; a sweep of
the workflow confirmed no third missing binary.
