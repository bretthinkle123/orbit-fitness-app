# C3 — Program builder + workout logging

_Phase C (features, local + Simulator), run 3 of 8. The biggest run on the roadmap. It is
the hard prerequisite for [C5](C5-tier-percentile.md) (strength tiers) and a strong
accuracy boost for [C4](C4-muscle-derivation.md) (muscle levels): it introduces
performed-set logging (weight × reps). C4 has a set-count fallback without it. Consumed by
requirements-elicitation + planning at run start._

**Terminology:** "workout logging" here means users **saving the workouts they performed**
(sets, weight, reps) — app data. It is not the security audit trail (B1).

## Goal
Users create and edit their own workout programs (exercises, set × rep schemes, weights,
ordering) and schedule them into blocks/weeks ("Wk 8 · Block 2" becomes real state). Most
importantly, they log what they actually lifted.

## The two schema decisions that dominate this run
1. **User-owned programs vs global seeds.** Either add `owner_uid` (nullable =
   seeded/global) to `programs`/`exercises`, or create parallel `user_programs` tables.
   Lean: nullable owner on the existing tables — one query path, and the ownership
   predicate extends the existing repository seam. The seeded Push Day stays owner NULL
   and read-only.
   - **Standing rule 1:** user-owned `programs`/`exercises` rows join the `erase.py`
     cascade, the AC5 erasure test and the owner_uid registry in this run. Owner-NULL seed
     rows stay outside the cascade.
   - If no earlier run (C1's shared-keys option) has built the registry, **this run
     builds it**, along with its export ∪ erase parity test.
2. **Exercise immutability/versioning (the history-integrity trap).** `set_events` has an
   FK to `exercises`, and the prescribed weight/reps live on the exercise row. If a user
   edits "Bench 100 lb → 110 lb" in place, their history silently rewrites.
   - Exercise rows that have been logged against must be immutable: an edit creates a new
     version row, and history keeps pointing at the version it was performed against.
   - Decide the version-chain shape in-run (lean: `exercise.replaces_id`).
   - **This is the reason the run must not be improvised.**

## Performed-set logging
`set_events` gains `performed_weight_kg`/`performed_reps`, nullable so toggle-only stays
valid; canonical metric per convention. This is the data C4 and C5 need. Adding it here,
where the logging UX is already open, avoids a third schema pass.

## Scope
- **CRUD endpoints** for programs, exercises and ordering. Every list is:
  - Bounded (caps on programs/user and exercises/program; hard LIMITs)
  - Owner-scoped
  - Validated (name length-bound, `muscle_tag` from the fixed 13-group allowlist, scheme
    bounds)
- **Scheduling model**: block/week labels plus an active-program pointer. Full
  periodization calendars can wait.
- **Train screen**: program picker, builder UI, per-set weight/rep entry. These are
  undepicted screens, so they follow the design README's "Extending the UI".
- **Week-strip/score semantics** with multiple programs. The score formula is unchanged:
  base + today's done count.
- **Pagination** (roadmap small item): decide here whether program lists need it or stay
  within the bounded caps.

## Security / compliance notes
- Standard shapes throughout: IDOR on every new resource, unauthenticated requests
  denied, constraint violation → 4xx, Tier-2 write limits.
- Program/exercise names are user free text: length-bound, parameterized, logged by id
  only.
- New fields get classification rows and B2 encryption where classified sensitive
  (standing rule 2).
- Reads and writes emit B1 audit events.

## Acceptance sketch
- Build → schedule → log a session end-to-end (XCUITest in the Simulator against the A1
  stack).
- Edit-after-log preserves history (the version test — the load-bearing one).
- Seeded program is read-only; caps enforced; cross-owner requests 404.
- Per-set performed data persists and feeds the day's score/body derivations.

## Size
Large. Consider splitting: (a) performed-set logging on the seeded program, (b) builder
CRUD + versioning, (c) scheduling/blocks.
