# Requirements — Orbit greenfield run (full depicted app)

_Elicited 2026-07-14 (interview), then REVISED the same day by operator directive after
the Claude Design export landed: the greenfield run now includes the **full feature set
the design depicts**, not the earlier thin slice. Where this file and the 2026-07-14
interview answers conflict, THIS file wins; superseded items are marked. Companion
scope audit: `.pipeline/design-audit.md`. This is planning's authoritative brief.
Kick off orchestration in a FRESH session (see Handoff)._

## Resolved

### Scope & shape
- This run builds the **full depicted ORBIT app**: 4 screens (Home / Fuel / Train / Body)
  + Settings sheet, native SwiftUI, replicated high-fidelity from
  `design/design_handoff_orbit_swiftui/` — **plus the real backend behind it** (the
  prototype is client-only; the shipped app is not).
- **Inclusion rule (operator-ratified):** flow depicted in the design (or required +
  designable from the README's "Extending the UI" conventions) → build it. Flow
  undepicted (button/label/number only) → stub/default now, named future run
  (see Out of scope + design-audit §6).
- **SUPERSEDED:** the interview's minimal placeholder workout resource (`type` enum +
  `duration_min` + `notes`, `POST/GET /workouts`) is **replaced** by the design's training
  model (program → exercises → set events). Do NOT build the placeholder.

### Stack (unchanged from interview)
- Backend: Python 3.12 / FastAPI / PostgreSQL (Alembic) / structlog; AWS + Sentry per
  skills. Auth: **Firebase Auth, email/password** (no MFA, no social). Frontend: **native
  iOS SwiftUI** from the Claude Design export (`claude-design-to-swiftui` +
  design-system-conventions). Reduced-assurance stamp applies to the Swift portion.

### Domain scope (per design-audit §2 — all depicted, all in)
- **Nutrition (Fuel):** per-user kcal budget + macro targets (editable in Settings;
  defaults 2,350 kcal · P185 / C240 / F72 g — **gram targets are canonical**; the
  Settings row's "40P · 35C · 25F" copy is a prototype inconsistency, see Open); food
  entries (name, kcal,
  P/C/F g, meal group Breakfast/Lunch/Snacks/Dinner, logged-at) via **quick-add chips**
  from a seeded quick-food catalog; Meals ⇄ By-hour views; coach banner renders a
  server-supplied message (static default copy this run).
- **Training (Train):** one seeded "Push Day" program (5 exercises: name, sets×reps,
  weight, muscle tag); tap-to-toggle set completion (day-keyed set events); client-side
  120s rest timer; score = stored base (512) + today's done sets; week strip from
  session-days-this-week; tier/percentile/68%-bar shown from stored profile defaults.
- **Body:** front+back muscle figures (geometry verbatim from `figure-paths.md`), M/W
  toggle, 13 groups × 6-level scale; per-user base levels (seeded to design defaults);
  **trained-today glow derived from today's set events** (depicted logic); by-muscle list.
- **Weight:** weight entries; canonical metric storage, display per units setting;
  30-day trend + weekly delta on Home; minimal entry sheet (undepicted → per conventions).
- **Home:** aggregates all of the above per the design (ring, macros, mission card, stat
  chips, weight card, planet picker).
- **Settings:** palette preset (4), Metric/Imperial, gender (M/W figures), planet index,
  budget + macro-target editors (grams; simple sheets), **Sign out**, **Delete account**.
- **Theming:** 4-preset palette system, everything recolors (Theme struct per README) —
  core feature, not polish.
- **Visual system:** starfield (deterministic seeds, shooting stars, toggleable ships),
  3D SceneKit heroes (Home planet+rings, Fuel macro moons, Train heating asteroid),
  scroll-driven cameras, per README/§3D spec. **Staged LAST in tasks.md** so caps land
  after function (design-audit §5).
- **Auth/onboarding UI:** undepicted → design minimal sign-in/register/name screens per
  "Extending the UI" conventions.

### Carried decisions (interview, still binding)
- Account deletion **in scope**: erases user's rows across ALL domains + Firebase
  identity (App Store 5.1.1(v) + GDPR erasure; data-lifecycle cascade).
- Client failure behavior: clear error state + manual retry; **no offline queue**.
- Perf: **p95 < 300 ms per API endpoint @ ~10 concurrent** (skeleton scale).
- Local PII stance: **auth identity only** — Firebase UID is the owner key; email/display
  name live in Firebase (greeting/avatar read Firebase profile). Domain rows carry uid,
  not PII. GDPR/CCPA posture; no clinical data, not HIPAA.
- Duplicates allowed (two identical food entries / re-doing a set pattern is legitimate);
  no idempotency keys.
- Timestamps (`logged_at`, `done_at`, weight date, etc.): client-provided; backdating
  allowed; **reject future** (> server now). Generalized from the interview's rule.
- **Every collection query is bounded**: day-/window-scoped AND hard-capped
  (e.g. entries/day ≤ 200, weights = 30-day window, LIMIT always present). Generalizes
  the interview's newest-100 rule; no pagination this run.
- Row-level ownership on every domain row; backend coverage ≥ 80%; structlog fields per
  logging-conventions.

### Data & seeds
- New users start **empty** (design's Dinner-empty pattern extends to all zero-data
  states). The prototype's demo day exists only in previews/tests. Real seed data =
  quick-food catalog (with macros) + Push Day program + default muscle base levels +
  profile defaults (budget/split/score-base/tier strings).

## Open
- **Onboarding screens' exact composition** (sign-in/register/name) — designed per
  conventions; planning proposes, human sees it at the plan checkpoint.
- **Weight-entry UI shape** — default: sheet from the Home weight card.
- **Budget/macro editor shape** — default: stepper/numeric sheets off the Settings rows.
- **Macro-split copy mismatch (design defect, audit-caught)** — Settings shows
  "40P · 35C · 25F" but the day targets P185/C240/F72 g compute to ≈31/41/28% of
  2,350 kcal; the prototype is internally inconsistent. Default: gram targets canonical;
  the split row displays the derived % — flag at the design-approval checkpoint.
- **Burned kcal / burn rate** — no input source exists in-app; default: optional server
  field, absent→0 display; real source is a named future run. Copy may keep design values
  in previews only.
- **Day rollover / timezone** — default: day-key = user's device-timezone local date,
  client sends tz; confirm at plan checkpoint.
- **Units rounding rules** (lb↔kg display) — default: store kg canonical, round display
  to 0.1.
- **Coach banner message source** — default: server constant string this run.
- **Data retention specifics** (how long entries kept; backups/logs honesty) — planning
  proposes per data-lifecycle-conventions.
- **App Store submission pass** (privacy labels, signing) — future run; planning may emit
  advisory criteria only.

## Out of scope (this build — hard exclusions; durably tracked in `docs/roadmap.md`)
- Functional **Scan / Photo / Search / Label** food logging (buttons render as depicted,
  actions stubbed) — future runs w/ food DB / OCR / recognition integrations.
- **Adaptive TDEE coach** (weekly macro adjustment engine).
- **Muscle-level derivation from lift history** (base levels static; trained-today glow
  IS in scope).
- **Tier/percentile computation**; **program builder / periodization** (one seeded
  program only); **rank-progression mechanics** (planet picker = persisted cosmetic).
- Wearables / Apple Health / Google Fit; any burned-kcal source.
- Social/feed; reminders/scheduling; analytics beyond depicted; payments; MFA/social
  login; offline queue/local sync; pagination; idempotency keys.
- Editing/deleting individual logged entries (set toggle covers today's sets; account
  deletion covers erasure); export-my-data flow.
- The superseded placeholder workout resource (see Resolved).
- Android/web frontends.

## Handoff
Design source is in-repo and the `Design source:` lines are set → the fresh-session
orchestrator starts at **design-spec** (untrusted-bundle normalization + injection
report), then the human design-approval checkpoint, then planning (which must emit
`tasks.md` and stage visual fidelity last). Elicitation happened in this session —
M4″-A2: **start orchestration in a fresh session**; this file + PROJECT.md + CLAUDE.md +
design-audit.md are the complete handoff.
