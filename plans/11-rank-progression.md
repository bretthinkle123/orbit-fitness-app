# Run 11 — Rank progression / gamification

_Post-launch run; order-flexible retention work (any time after launch; reads events
runs 9–10 produce if present, degrades fine without them). Consumed by
requirements-elicitation + planning at run start._

## Goal
The space theme's progression becomes real: streaks ("Day 12 in orbit"), orbit ranks
that unlock planets/rings ("rank up to travel further"), replacing the greenfield
cosmetic planet picker with earned progression.

## Mechanics (planning formalizes)
- **Streak definition (the core decision):** what counts as an active day — any log
  (food/set/weight) vs training-only? Lean: any log (diet apps live on logging streaks).
  Grace semantics: strict daily vs 1 rest-day allowance vs weekly-goal streaks (lean:
  N-days-per-week goal met = streak week — kinder and more honest for training).
- Day boundaries: `day_key` (device-tz) already settled — travel edge cases inherit the
  documented model; streak recompute is a bounded trailing-window read.
- Ranks: streak-weeks + milestones (first level-up, first PR from runs 9/10 events) →
  rank ladder → planet/ring unlock table; `planet_index` becomes highest-unlocked
  (grandfather existing choices — never take away a planet a user already had).
- Surfacing: Home card + planet picker states; **no push notifications** (reminders stay
  excluded; streaks surface in-app only).

## Ethics guardrail (health-adjacent gamification)
No punishment framing for rest (the grace model is the mechanism); no streak-repair
purchases ever (also keeps this run monetization-neutral); copy reviewed against the
eating-disorder guard from run 7.

## Data & schema
`progression(owner_uid, streak_weeks, current_rank, updated_at)` + optional
`progression_events` (bounded); lazy-computed on Home read (same pattern as runs 7/9);
unlock rules as a seeded static table (global, outside the cascade). `progression` and
`progression_events` are personal-fitness data — classification row + run-2 controls
apply; both join the `erase.py` cascade + owner_uid registry (standing rule).

## Acceptance sketch
Fixture activity calendars (daily / N-per-week / gap / timezone-shift) → expected
streak/rank; unlock at exact thresholds; grandfathering holds; rest-day never breaks the
weekly-goal streak; Home/planet UI reflects state (XCUITest).

## Size
Small-medium; pure additive; the design work (rank ladder + copy) outweighs the code.
