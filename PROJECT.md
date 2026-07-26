# Orbit Fitness & Diet Tracking

## What this is
**Orbit Fitness & Diet Tracking** (official product / App Store name, 29 chars — fits
Apple's 30-char limit; "Orbit" remains the short brand name, home-screen icon label, and
internal identifier) is a space-themed diet + fitness tracker: a strength-training tracker (set logging,
strength score, muscle-level body map) fused with a diet coach (calorie/macro budget, fast
food logging), native iOS (SwiftUI) over a Python backend. This build is the **greenfield
run**: the full feature set depicted in the Claude Design export, end-to-end — real auth,
real persistence, CI gate, deploy path — so future feature-runs extend a working app.

Authoritative brief: `.pipeline/requirements.md` (operator-revised 2026-07-14).
Scope audit of the design: `.pipeline/design-audit.md`. Planning treats requirements.md
as source of truth and must emit `.pipeline/tasks.md` (this is well over the 8-file
threshold), staging visual fidelity (starfield/3D) after core function.

## This build (greenfield scope)
1. **Foundation** — Firebase email/password auth (verify ID token, `require_auth`),
   sign-out, **account deletion** (App Store 5.1.1(v); full erasure cascade), `/health`,
   CI gate, deploy path, structlog, test scaffolding.
2. **Nutrition (Fuel)** — per-user kcal budget + macro targets (editable, seeded
   2,350 kcal · P185/C240/F72 g — gram targets canonical); food entries via quick-add
   from a seeded catalog; meal groups
   (Breakfast/Lunch/Snacks/Dinner); Meals ⇄ By-hour views; coach banner (server message,
   static default).
3. **Training (Train)** — seeded "Push Day" program (5 exercises); tap-to-toggle set
   completion (day-keyed); 120s rest timer (client); score = base 512 + today's sets;
   week strip; tier/percentile from stored defaults.
4. **Body** — muscle map (front+back, M/W, geometry from `figure-paths.md`), 13 groups ×
   6 levels (seeded base levels), trained-today glow from today's sets; by-muscle list.
5. **Weight** — entries (canonical metric), 30-day trend + weekly delta; minimal entry
   sheet.
6. **Home** — dashboard aggregating all of the above per the design.
7. **Settings** — palette (4 presets), units, gender, planet picker (persisted cosmetic),
   budget/split editors, sign-out, delete-account.
8. **Visual system** — theme math, starfield, 3D SceneKit heroes, scroll-driven cameras —
   **last tasks in the run**; Reduce Motion + VoiceOver per the design README.
9. **Onboarding UI** — undepicted; minimal sign-in/register per the design's
   "Extending the UI" conventions.

## Explicitly out of scope (named future runs — see docs/roadmap.md)
- Functional Scan / Photo / Search / Label food logging (buttons stubbed).
- Adaptive TDEE coach engine; muscle-levels-from-history; tier/percentile computation;
  program builder / periodization; rank-progression mechanics.
- Wearables / Apple Health (any burned-kcal source); social; reminders; payments;
  MFA/social login; offline sync; pagination; per-entry edit/delete; export-my-data;
  Android/web.

## Stack
- Backend: Python 3.12, FastAPI, PostgreSQL (Alembic), structlog.
- Frontend: **native iOS, SwiftUI** — replicate the design high-fidelity
  (claude-design-to-swiftui). **Reduced-assurance target** for deterministic gates.
- Auth: Firebase Auth (email/password). Observability: CloudWatch/X-Ray + Sentry.
- Cloud/IaC: AWS + Terraform as/if the deploy path requires (planning decides depth).

## Frontend design source
- Design source: see design/design_handoff_orbit_swiftui/ (Claude Design export)
- Target: native iOS (SwiftUI)
- Notes: high-fidelity replication; prototype is client-only — backend/API is designed by
  planning, not the bundle. Bundle README's "Extending the UI" section governs undepicted
  screens (auth, deletion, weight entry, editors). Injection pre-scan clean
  (design-audit); the design-spec stage still produces the gated injection report.

## Compliance / data posture
- Personal data + general fitness metrics; **no clinical data, not HIPAA**. GDPR/CCPA:
  classify stored fields at planning (data-protection-conventions); deletion cascade this
  run (data-lifecycle-conventions); Firebase UID is the only local identity key.

## What "done" means
- Smoke passes; register → sign in → quick-add a food → toggle sets (score ticks, Body
  glows) → log weight → switch palette/units (persists) → delete account cascades — all
  against the real API.
- Row-level ownership everywhere; every list query bounded; input validation; security
  report clean; perf p95 < 300 ms @ ~10 concurrent; backend coverage ≥ 80%.
- Docs + PR description; reduced-assurance stamp surfaced for the Swift portion.
