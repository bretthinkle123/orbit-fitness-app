# Orbit Fitness & Diet Tracking

Space-themed diet + fitness tracker: SwiftUI iOS app over a Python/FastAPI backend.
Official product / App Store name: **"Orbit Fitness & Diet Tracking"** (29 chars, within
Apple's 30-char name limit). "Orbit" stays the short brand name, the home-screen icon
label (CFBundleDisplayName — long names truncate on device), and the internal identifier
(`src/orbit/` package, bundle-id stem, design-export paths).
Greenfield run = the full feature set depicted in the Claude Design export, end-to-end.
Authoritative brief: `.pipeline/requirements.md`; design scope audit:
`.pipeline/design-audit.md`; scope summary: `PROJECT.md`; future-runs roadmap:
`docs/roadmap.md` (ordered run list; per-run planning briefs in `plans/`, read by
requirements-elicitation/planning at the start of each future run).

## Stack
- Cloud environment: AWS (infra as/if deploy path requires).
- Language/runtime: Python 3.12 (backend); Swift / SwiftUI (iOS).
- Framework(s): FastAPI (backend); SwiftUI + SceneKit (iOS).
- Data stores: PostgreSQL. Migration tool: Alembic.
- Auth provider: Firebase Auth (email/password); backend verifies Firebase ID tokens
  behind a `require_auth` facade.
- Observability: CloudWatch + X-Ray + Sentry; structlog structured logs.
- Packaging / runtime: direct process (backend).

## Stack notes
- **Native iOS (SwiftUI) is reduced-assurance** for the pipeline's deterministic gates —
  they analyze little Swift. Never claim the Swift portion "gate-verified"; the backend
  keeps full gate coverage.
- iOS UI is a high-fidelity replication of `design/design_handoff_orbit_swiftui/`
  (Claude Design export). Adopt the README's suggested decomposition (Theme / AppStore /
  Screens / Components / Space / Figures); undepicted screens follow its
  "Extending the UI" conventions. Muscle-figure geometry comes verbatim from
  `design/design_handoff_orbit_swiftui/figure-paths.md`.

## How to run / build / test
- Start (backend): `python -m uvicorn src.orbit.main:app --port 8000`
  (smoke check expects HTTP 200 at `http://localhost:8000/health`)
- Test (backend): `pytest --cov=src` (threshold >= 80%)
- Migrate: `alembic upgrade head`
- iOS: Swift toolchain + XCTest (reduced assurance; see Stack notes).
- Deploy: CI on merge — `.github/workflows/`; ci-conventions + delivery-conventions.

## Frontend design source
- Design source: see design/design_handoff_orbit_swiftui/ (Claude Design export)
- Target: native iOS (SwiftUI)
- Notes: prototype is client-only ("No networking") — the API/backend is planned, not in
  the bundle. High-fidelity intent; visual system (starfield/3D) staged as the LAST tasks.

## Conventions
- Backend layout: `src/orbit/` package; tests in `tests/` as `test_*.py`.
- `/health` returns 200 with **no external dependencies** (no DB/Firebase required) —
  the smoke check depends on it; readiness beyond liveness is a separate concern.
- **Row-level ownership** (owner key = Firebase UID) on every domain row; no local PII
  beyond the UID (email/display name stay in Firebase).
- **Every collection query bounded**: day-/window-scoped + hard LIMIT (entries/day ≤ 200,
  weights 30-day window). No pagination this run.
- Timestamps client-provided; backdating ok; reject future (> server now).
- Domain data is **day-keyed** (user's device-tz local date; client sends tz).
- Weight stored canonical metric (kg); display converts per units setting (round 0.1).
- Seed data (quick-food catalog w/ macros, Push Day program, muscle base levels, profile
  defaults) via migrations/fixtures; **new users start empty** — the prototype's demo day
  exists only in previews/tests.
- Facade modules for auth, logging, secrets, crypto per code-standards; input validation
  + output encoding on every endpoint.
- iOS: theme = `Theme` struct computed from the 3-color palette (never hardcode hues);
  hit targets ≥ 44pt; Reduce Motion + VoiceOver behaviors from the design README are
  acceptance criteria.

## What "done" means
- Smoke passes; security clean; backend tests ≥ 80% coverage; perf p95 < 300 ms @ ~10
  concurrent measured; register → log food → toggle sets → weight → theme-switch →
  delete-account all work against the real API; docs updated; PR description written;
  reduced-assurance stamp surfaced.
