# Run 10 — Strength tier & percentile engine

_Post-launch run; hard dependency on run 8's performed-set data (weight×reps) and uses
bodyweight from weight_entries. Consumed by requirements-elicitation + planning at run
start._

## Goal
"Intermediate II", "Top 22% @ 183 lb", and the %-to-next-tier bar become computed from
the user's actual lifts instead of stored display defaults.

## Mechanics (planning formalizes)
- e1RM per key lift from performed sets (Epley/Brzycki — pick one, record it).
- Standards dataset: bodyweight-relative strength standards by lift × gender.
  **The licensing decision is the run's real risk:** published standards tables
  (symmetricstrength/strengthlevel-style) are proprietary — options: license one,
  derive from open powerlifting data (OpenPowerlifting is open-data; skews competitive),
  or author our own curve and label it honestly. Ships as a static seeded dataset via
  migration (no runtime dependency).
- Tier ladder (Novice→Elite with sub-tiers) + percentile interpolation + %-to-next-tier;
  gender from profile, bodyweight from latest weight entry (staleness rule needed).
- Honesty rule: users without performed-set data (toggle-only) keep a "log weights to
  unlock" state — never fake a percentile.

## Key decisions / open questions
Which lifts anchor the score (compound-only?); combining per-lift tiers into the single
headline tier (lean: weighted best-3 compounds); percentile phrasing honesty ("of
lifters in reference dataset", not "of all humans"); imperial display (existing units
setting handles it).

## Data & schema
Seeded `strength_standards` (global, via migration; no owner — outside the cascade);
computed `strength_scores(owner_uid, lift, e1rm, tier, percentile, computed_at)` —
owner-scoped, bounded, lazy-computed on Train read; derived personal-fitness data, so
the classification row + run-2 controls apply, and it joins the `erase.py` cascade +
owner_uid registry (standing rule); profile display fields switch from static to
computed source.

## Acceptance sketch
Fixture lifter profiles → expected e1RM/tier/percentile against the seeded dataset;
no-data → locked state (never fabricated); bodyweight-staleness rule enforced; formula +
dataset provenance recorded in docs; UI strings unchanged in shape.

## Size
Small-medium once run 8 exists; dataset sourcing/licensing is the long pole.
