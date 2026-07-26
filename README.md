# Orbit Fitness & Diet Tracking

Space-themed diet + fitness tracker: native SwiftUI iOS app over a Python 3.12 / FastAPI
backend, PostgreSQL storage, Firebase email/password auth, on an AWS deploy path.
"Orbit" is the short brand name / home-screen icon label; **"Orbit Fitness & Diet
Tracking"** is the full App Store product name.

This is the **greenfield run**: the full feature set depicted in the Claude Design
export (`design/design_handoff_orbit_swiftui/`), end-to-end — real auth, real
persistence, CI gate, deploy path.

- Product scope: `PROJECT.md`
- Authoritative brief: `.pipeline/requirements.md`
- Full plan + threat model: `.pipeline/plan.md` (retained for this branch at
  `docs/decisions/feature/greenfield/plan.md`)
- Future-runs roadmap: `docs/roadmap.md`; per-run briefs: `plans/`
- System architecture + diagrams: `docs/system_architecture.md`

## Reduced assurance — read this first

**Native iOS (SwiftUI) is a reduced-assurance target.** The pipeline's deterministic
security/coverage gates (Semgrep, OSV, Trivy, Checkov, pytest coverage) analyze almost no
Swift. `ios/Orbit/` was authored on a Linux host with no Swift toolchain — nothing there
has been compiled, run, or snapshot-reviewed yet. It is verified by authored
XCTest/Swift Testing/XCUITest/snapshot suites plus human review, on the operator's Mac
(`plans/00-mac-pipeline-readiness.md` Phase 5). Never read an iOS claim in this repo as
"gate-verified" the way the backend is — the backend carries full deterministic gate
coverage.

## Stack

- **Backend:** Python 3.12, FastAPI, PostgreSQL (SQLAlchemy 2.0 async + Alembic
  migrations), Firebase Auth (email/password) behind a `require_auth` facade, structlog +
  CloudWatch/X-Ray + Sentry, ElastiCache Redis (rate-limit store).
- **iOS:** SwiftUI (iOS 17+), `@Observable` + MV architecture, SceneKit (3D hero scenes).
- **Infra:** AWS via Terraform (`infra/`) — this run provisions the **data-security
  baseline** (RDS, ElastiCache, Secrets Manager, CloudWatch log groups, VPC/security
  groups); compute (ECS/ALB/autoscaling) is a deferred follow-on (`plans/01-production-deploy-path.md`).

## Repository layout

| Path | What's there |
|---|---|
| `src/orbit/` | FastAPI backend package — see `src/orbit/README.md` |
| `migrations/` | Alembic schema + seed migrations — see `migrations/README.md` |
| `infra/` | Terraform AWS infrastructure — see `infra/README.md` |
| `ios/Orbit/` | Native SwiftUI client — see `ios/Orbit/README.md` |
| `tests/` | Backend pytest suite (unit/integration/perf) — see `tests/README.md` |
| `scripts/` | Operational + CI helper scripts — see `scripts/README.md` |
| `design/design_handoff_orbit_swiftui/` | Vendored Claude Design export (reference only; never built into the app) |
| `docs/` | `system_architecture.md`, `roadmap.md`, `finding-ledger.md` |
| `plans/` | Per-future-run planning briefs |
| `.github/workflows/` | CI merge gate, deploy pipeline, DAST/provenance workflows |

## How to run locally (backend)

```sh
poetry install
python -m uvicorn src.orbit.main:app --port 8000
```

`GET http://localhost:8000/health` must return `200` with **no external dependencies**
reachable (no DB/Firebase required) — this is the smoke check's own contract.

Backend config/secrets are read through `src/orbit/config/` (env vars locally; AWS
Secrets Manager/SSM in deploy) — never hardcode a credential.

## How to build (iOS)

```sh
brew install xcodegen   # once, on the operator's Mac
cd ios/Orbit
xcodegen generate       # writes Orbit.xcodeproj from the checked-in project.yml
open Orbit.xcodeproj
```

See `ios/Orbit/README.md` for the module layout and the fonts/XcodeGen notes.

## How to test

```sh
# Backend — coverage floor 80% (mirrored in .github/workflows/pipeline-ci.yml)
poetry run pytest --cov=src --cov-fail-under=80

# Migrations
poetry run alembic upgrade head

# Performance (k6, out-of-process; see tests/README.md)
tests/perf/run_perf.sh
```

iOS tests (`ios/Orbit/Tests/`) are Swift Testing / XCUITest / snapshot suites, authored
but **only executable on a Mac with the Swift toolchain** — see the Reduced assurance
note above and `ios/Orbit/README.md`.

## How to deploy

CI is scaffolded in `.github/workflows/`:

- `pipeline-ci.yml` — the merge gate; re-runs every deterministic check against the
  merge commit (never trusts `.pipeline/` artifacts, which are the author's own claims).
- `deploy.yml` — inert until the operator sets the `DEPLOY_ENABLED` repo variable;
  verifies a signed build (cosign), then `terraform apply` + migrate + canary rollout.
  The compute topology (ECS/ALB/autoscaling) it targets is not yet provisioned in
  `infra/` this run — see `docs/system_architecture.md` §Deployment topology and
  `plans/01-production-deploy-path.md`.
- `terraform apply` never runs inside this pipeline; only in CI, after merge.

**Outstanding deploy-time obligation:** enable the Firebase Authentication password
policy for the project (ASVS `6.2.x`, waived conditionally this run — see
`.pipeline/security-report.md` / `docs/decisions/feature/greenfield/security-report.md`
and `plans/01-production-deploy-path.md`).

## How to contribute

- Backend code lives in `src/orbit/`; tests in `tests/` as `test_*.py`.
- Every domain row is owner-scoped (`owner_uid` = Firebase UID); every collection query
  is day-/window-bounded with a hard `LIMIT`. See `src/orbit/README.md`.
- iOS follows the module decomposition in `ios/Orbit/README.md`; theme colors always
  route through `DesignSystem/Theme.swift` — never a second hex literal.
- Facades only for auth/logging/secrets/crypto — no direct SDK calls elsewhere.
- Read `.pipeline/plan.md` (retained at
  `docs/decisions/feature/greenfield/plan.md`) before extending the API surface; it
  carries the STRIDE threat model and the ASVS reconciliation this build is held to.
