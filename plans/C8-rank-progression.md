# C8 — Rank progression / gamification

_Phase C (features, local + Simulator), run 8 of 8. Reads C4's level events and C3's
performed-set history ([C4](C4-muscle-derivation.md), [C3](C3-program-builder.md)), and
degrades fine without them. Consumed by requirements-elicitation + planning at run start._

## Goal
The space theme's progression becomes real: streaks ("Day 12 in orbit") and orbit ranks
that unlock planets/rings ("rank up to travel further"). Earned progression replaces
greenfield's cosmetic planet picker.

## Mechanics (planning formalizes)
- **Streak definition (the core decision):** what counts as an active day?
  - Any log (food/set/weight) vs training-only. Lean: any log — diet apps live on
    logging streaks.
  - Grace semantics: strict daily vs a 1-rest-day allowance vs weekly-goal streaks. Lean:
    meeting an N-days-per-week goal = a streak week; kinder and more honest for training.
- **Day boundaries**: `day_key` (device timezone) is already settled. Travel edge cases
  inherit the documented model; streak recompute is a bounded trailing-window read.
- **Ranks**: streak-weeks + milestones → rank ladder → planet/ring unlock table.
  Milestones: first level-up (C4's `level_events`) and first PR (a new best e1RM,
  derived from C3's performed sets — C5 stores only the current e1RM, not history) →
  unlocks. `planet_index` becomes the highest unlocked.
  Grandfather existing choices: never take away a planet a user already had.
- **Surfacing**: Home card + planet picker states. **No push notifications** — reminders
  stay excluded; streaks surface in-app only.

## Ethics guardrail (health-adjacent gamification)
- No punishment framing for rest (the grace model is the mechanism).
- No streak-repair purchases, ever (this also keeps the run monetization-neutral).
- Copy reviewed against C7's eating-disorder guard.

## Data & schema
- `progression(owner_uid, streak_weeks, current_rank, updated_at)` + optional
  `progression_events` (bounded).
- Lazy-computed on Home read (the same pattern as C4/C7).
- Unlock rules live in a seeded static table (global, outside the cascade).
- `progression` and `progression_events` are personal-fitness data: classification rows +
  B1/B2 controls (standing rule 2); both join the `erase.py` cascade + owner_uid registry
  (standing rule 1).

## Acceptance sketch
- Fixture activity calendars (daily / N-per-week / gap / timezone shift) → expected
  streak/rank.
- Unlocks trigger at the exact thresholds; grandfathering holds.
- A rest day never breaks the weekly-goal streak.
- Home/planet UI reflects state (XCUITest in the Simulator).

## Size
Small-medium; purely additive. The design work (rank ladder + copy) outweighs the code.
