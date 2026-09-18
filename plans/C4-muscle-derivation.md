# C4 — Muscle progression (levels derived from lift history)

_Phase C (features, local + Simulator), run 4 of 8. Benefits strongly from
[C3](C3-program-builder.md) (exercise variety + performed-set data). Consumed by
requirements-elicitation + planning at run start._

## Goal
The Body screen's 13 muscle-group levels (6-stop scale) are computed from actual training
history instead of seeded statics, including level-up moments.

## Algorithm shape (planning formalizes)
- Per muscle group: training volume over a trailing window (e.g. 12 weeks).
- Volume = sets × reps × weight where performed data exists; set-count fallback where it
  doesn't.
- Mapped through level thresholds, with decay for inactivity. Levels can drop — decide
  how soft that feels in the UX.
- Deterministic, explainable, bounded reads (window + LIMIT per group).

## Key decisions / open questions
- **Seeded base levels**: floor, starting offset, or discarded on first computation?
  Lean: a one-time migration to computed-with-floor, so nobody's figure craters on day 1.
- **Exercise → muscle mapping**: there is a single `muscle_tag` today. Add
  secondary-muscle weighting (e.g. bench → triceps 0.5)? Lean yes: a small static map is
  a big fidelity win.
- **Compute timing**: on-write incremental vs on-read lazy. Lean lazy, with
  bounded-window discipline. This is the first derived-on-read computation in the
  system, so **the decision made here sets the precedent** that
  [C5](C5-tier-percentile.md), [C7](C7-adaptive-coach.md) and
  [C8](C8-rank-progression.md) follow.
- **Level-up event**: where it surfaces (a Body screen moment; **no push** — reminders
  remain excluded), plus a `level_up` domain event for [C8](C8-rank-progression.md)'s
  streak/rank logic. A `level_up` is a gamification event, not a B1 audit event.

## Data & schema
- `muscle_base_levels` becomes `muscle_levels` (computed value + `computed_at` + floor).
- Optional `level_events(owner_uid, muscle_group, level, day_key)` for C8 to consume.
- All owner-scoped/bounded.
- Personal-health classification rows and B2 controls apply (standing rule 2).
- **Rename ripples**, to be named in the plan — all update in this run:
  - `POST /me/bootstrap` seeding (AC4's "13 muscle base levels")
  - The `GET /profile` and `GET /body` response shapes
  - The `erase.py` table list
- `level_events` joins the cascade + owner_uid registry (standing rule 1).

## Acceptance sketch
- Fixture histories (fresh user / consistent push-day / stopped-training / mixed-program)
  → expected levels ±0.
- Decay behaves as decided.
- The trained-today glow is unchanged.
- The migration's no-regression floor holds.
- Figure rendering is unchanged (levels are its only input).

## Size
Medium. Pure backend math + one migration; the iOS change is near-zero (same 13 × 6
contract).
