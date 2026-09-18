# C7 — Adaptive diet coach (TDEE / weekly macro adjustments)

_Phase C (features, local + Simulator), run 7 of 8. [C6](C6-healthkit-activity.md)
(HealthKit) improves its accuracy. Consumed by requirements-elicitation + planning at run
start._

**Monetization (owner decision, 2026-09-18): note only, not a blocker.** The coach is
built as a normal feature available to every user. Free vs freemium is decided before
going live (roadmap Phase E). If freemium is chosen then, the entitlement shape in the
"Monetization tie-in" section below is how the coach gets gated; StoreKit/webhook work
becomes its own planned run.

**Data (local-first):** the original brief assumed weeks of real post-launch intake and
weight data. Locally, the engine is developed and verified against **seeded synthetic
histories**: fixture series in tests, plus an optional dev seed script for the Simulator
demo user. They are never inserted by migrations; new users start empty (CLAUDE.md).

## Goal
The MacroFactor-style engine the design's coach banner promises. Estimate each user's
actual energy expenditure from logged intake vs weight trend, and adjust budget/macros
weekly ("Coach adjusts Mon").

## Algorithm shape (planning formalizes; keep it explainable)
- **Weight trend**: an exponentially weighted moving average over `weight_entries`
  (robust to water/scale noise).
- **TDEE estimate**: energy-balance regression — average intake minus (trend slope ×
  ~7700 kcal/kg) over a trailing 21–28 day window, clamped to physiological bounds.
- **Weekly adjustment**: move `kcal_budget` toward the goal rate.
  - Goal-setting UX is part of this run; target weight/rate is currently nowhere in the
    schema.
  - Macro grams are re-derived from the user's split preference, captured by the
    **macro-split % editor this run adds** (roadmap small item): % edits convert to grams
    at save, gram targets stay canonical, reconciling the design's "40P·35C·25F" copy.
  - Every adjustment produces a human-readable "why" string (the banner).
- **Guards**:
  - No adjustment with fewer than N logged days / M weigh-ins
  - A max step per week
  - Never below a safety floor
  - **An under-eating/eating-disorder guard is mandatory, in both copy and behavior**
    (health-adjacent product responsibility): never coach below the floor, and surface
    help copy on sustained extreme deficits.

## Architecture decision (the real one): where the weekly job runs
This is the first scheduled computation in the system.
- **Lazy compute, decided for the local phase**: on `GET /fuel`, check whether an
  adjustment is due. No new infrastructure; work is bounded per user.
- The infrastructure-native alternative (EventBridge Scheduler → deployed compute) only
  exists once E1 is live. Revisit it then if scale warrants.
- Either way: bounded windows per user, idempotent per (uid, week).
- **Budget note**: B2 field-encrypts intake/weight values, so window aggregates decrypt
  app-side through the crypto facade — no SQL AVG over ciphertext. Worst case is ~200
  entries × 28 days per compute; plan the compute cost accordingly.

## Data & schema
- `profiles` + goal fields (`target_weight_kg`, rate, mode maintain/cut/bulk).
- `tdee_estimates(owner_uid, week_key, tdee, confidence, adjustment, rationale)`:
  owner-scoped, bounded, classified personal-health (B1/B2 controls apply — standing
  rule 2). Joins the `erase.py` cascade + owner_uid registry (standing rule 1).
- The `GET /fuel` coach-message field stops being static. There is no separate banner
  endpoint.

## Monetization tie-in (only if freemium is chosen before go-live)
- Entitlement check via the auth/claims facade (a `require_entitlement("coach")` shape).
- The free tier keeps the static banner.
- StoreKit/webhook work is its own planned run when the decision is taken; the coach only
  consumes the entitlement flag.

## Acceptance sketch
- Fixture series (steady loss / gain / noisy / sparse) → expected TDEE ± tolerance and
  the expected adjustment.
- Guard cases (insufficient data, floor, max step) hold.
- The rationale string matches the numbers.
- Weekly idempotency.
- The banner reflects state end-to-end (XCUITest in the Simulator with seeded history).
- Under-floor is never emitted (property test).

## Size
Medium. The math is small; goal-setting UX + guards + explainability are the bulk.
