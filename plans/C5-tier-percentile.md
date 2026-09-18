# C5 — Strength tier & percentile engine

_Phase C (features, local + Simulator), run 5 of 8. Hard dependency on
[C3](C3-program-builder.md)'s performed-set data (weight × reps); uses bodyweight from
`weight_entries`. Consumed by requirements-elicitation + planning at run start._

## Goal
"Intermediate II", "Top 22% @ 183 lb" and the %-to-next-tier bar are computed from the
user's actual lifts instead of stored display defaults.

## Mechanics (planning formalizes)
- **e1RM** per key lift from performed sets. Epley or Brzycki — pick one and record it.
- **Standards dataset**: bodyweight-relative strength standards by lift × gender.
  - **The dataset licence is the run's real risk.** Published standards tables
    (symmetricstrength/strengthlevel-style) are proprietary.
  - Options: license one; derive from open powerlifting data (OpenPowerlifting — confirm
    its licence in-run; it skews competitive); or author our own curve and label it
    honestly.
  - **Local-first/$0 posture:** a paid licence needs the owner's explicit approval. The
    default is the open-data or self-authored path.
  - Ships as a static seeded dataset via migration (no runtime dependency).
- **Tier ladder** (Novice → Elite with sub-tiers), percentile interpolation and
  %-to-next-tier. Gender comes from the profile; bodyweight from the latest weight entry,
  which needs a staleness rule.
- **Honesty rule**: users without performed-set data (toggle-only) keep a "log weights to
  unlock" state. Never fake a percentile.

## Key decisions / open questions
- Which lifts anchor the score (compound-only?)
- How per-lift tiers combine into the single headline tier. Lean: weighted best-3
  compounds.
- Percentile phrasing honesty: "of lifters in reference dataset", not "of all humans"
- Imperial display — the existing units setting handles it

## Data & schema
- Seeded `strength_standards`: global, via migration, no owner, outside the cascade.
- Computed `strength_scores(owner_uid, lift, e1rm, tier, percentile, computed_at)`:
  owner-scoped, bounded, lazy-computed on Train read.
- `strength_scores` is derived personal-fitness data, so it gets a classification row and
  the B1/B2 controls (standing rule 2) and joins the `erase.py` cascade + owner_uid
  registry (standing rule 1).
- Profile display fields switch from a static to a computed source.

## Acceptance sketch
- Fixture lifter profiles → expected e1RM/tier/percentile against the seeded dataset.
- No data → locked state (never fabricated).
- Bodyweight-staleness rule enforced.
- Formula and dataset provenance/licence recorded in docs.
- UI strings unchanged in shape.

## Size
Small-medium once C3 exists; dataset sourcing/licensing is the long pole.
