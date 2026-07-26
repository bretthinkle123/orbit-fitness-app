# Run 7 — Adaptive diet coach (TDEE / weekly macro adjustments)

_Post-launch run; sits AFTER the monetization decision gate — if freemium was chosen,
this is the flagship premium feature and ships behind the entitlement. Prereq: a few
weeks of real intake + weight data (exists by now); run 6 improves accuracy. Consumed by
requirements-elicitation + planning at run start._

## Goal
The MacroFactor-style engine the design's coach banner promises: estimate each user's
actual energy expenditure from logged intake vs weight trend, and adjust budget/macros
weekly ("Coach adjusts Mon").

## Algorithm shape (planning formalizes; keep it explainable)
- Weight trend: exponentially-weighted moving average over `weight_entries` (noise-robust
  vs water/scale variance).
- TDEE estimate: energy-balance regression — average intake minus (trend slope ×
  ~7700 kcal/kg) over a trailing window (21–28 d), clamped to physiological bounds.
- Weekly adjustment: move `kcal_budget` toward goal rate (goal-setting UX is part of this
  run — target weight/rate is currently nowhere in the schema); macro grams re-derived
  from the user's split preference — captured by the **macro-split % editor UX this run
  adds** (the roadmap small-item: % edits convert to grams at save, gram targets stay
  canonical, reconciling the design's "40P·35C·25F" copy); every adjustment produces a
  human-readable "why" string (the banner).
- Guards: no adjustment under N logged days / M weigh-ins; max step per week; never below
  a safety floor. **An under-eating/eating-disorder guard is mandatory copy+behavior**
  (health-adjacent product responsibility — never coach below the floor, surface help
  copy on sustained extreme deficits).

## Architecture decision (the real one): where the weekly job runs
First scheduled computation in the system. Options: EventBridge Scheduler → the run-1
compute (clean, infra-native) vs on-read lazy compute ("is an adjustment due?" checked on
`GET /fuel` — no new infra, work bounded per user). **Lean lazy-compute** at this scale;
revisit when a real job runner exists. Either way: bounded windows per user, idempotent
per (uid, week). Budget note: run 2 field-encrypts intake/weight values, so window
aggregates decrypt app-side through the crypto facade (worst case ~200 entries × 28 days
per compute) — no SQL AVG over ciphertext; plan the compute cost accordingly.

## Data & schema
`profiles` + goal fields (target_weight_kg, rate, mode maintain/cut/bulk);
`tdee_estimates(owner_uid, week_key, tdee, confidence, adjustment, rationale)` —
owner-scoped, bounded, classified personal-health (run-2 controls apply); joins the
`erase.py` cascade + owner_uid registry (standing rule). The `GET /fuel` coach-message
field stops being static (there is no separate banner endpoint).

## Monetization tie-in (if freemium)
Entitlement check via the auth/claims facade (`require_entitlement("coach")` shape);
free tier keeps static banner; StoreKit/webhook work is its own planned run when the
gate decision is taken — this run only consumes the entitlement flag.

## Acceptance sketch
Fixture series (steady loss / gain / noisy / sparse) → expected TDEE ±tolerance +
expected adjustment; guard cases (insufficient data, floor, max-step) hold; rationale
string matches numbers; weekly idempotency; banner reflects state end-to-end (XCUITest);
under-floor never emitted (property test).

## Size
Medium. The math is small; goal-setting UX + guards + explainability are the bulk.
