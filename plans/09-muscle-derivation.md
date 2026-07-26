# Run 9 — Muscle-level derivation from lift history

_Post-launch run; benefits strongly from run 8 (exercise variety + performed-set data).
Consumed by requirements-elicitation + planning at run start._

## Goal
The Body screen's 13 muscle-group levels (6-stop scale) become computed from actual
training history instead of seeded statics — including level-up moments.

## Algorithm shape (planning formalizes)
Per muscle group: training volume over a trailing window (e.g. 12 weeks; sets × reps ×
weight where performed data exists, set-count fallback where it doesn't) mapped through
level thresholds, with decay for inactivity (levels can drop — decide UX softness).
Deterministic, explainable, bounded reads (window + LIMIT per group).

## Key decisions / open questions
- Seeded base levels: floor, starting offset, or discarded on first computation?
  (Lean: one-time migration to computed-with-floor so nobody's figure craters on day 1.)
- Exercise→muscle mapping: single `muscle_tag` today; secondary-muscle weighting
  (e.g. bench → triceps 0.5)? Lean yes, small static map — big fidelity win.
- Compute timing: on-write incremental vs on-read lazy (mirror run 7's lazy-compute
  decision; same bounded-window discipline).
- Level-up event: where surfaced (Body screen moment; **no push** — reminders remain
  excluded) + `level_up` audit-free domain event for run 11's streak/rank logic.

## Data & schema
`muscle_base_levels` becomes `muscle_levels` (computed value + computed_at + floor);
optional `level_events(owner_uid, muscle_group, level, day_key)` for run 11 to consume.
All owner-scoped/bounded; personal-health classification per run 2. Rename ripples to
name in-plan: `POST /me/bootstrap` seeding (AC4's "13 muscle base levels"), the
`GET /profile` and `GET /body` response shapes, and the `erase.py` table list all update
in this run; `level_events` joins the cascade + owner_uid registry (standing rule).

## Acceptance sketch
Fixture histories (fresh user / consistent push-day / stopped-training / mixed-program)
→ expected levels ±0; decay behaves; trained-today glow unchanged; migration preserves
no-regression floor; figure rendering unchanged (levels are the only input).

## Size
Medium. Pure backend math + one migration; iOS change is near-zero (same 13×6 contract).
