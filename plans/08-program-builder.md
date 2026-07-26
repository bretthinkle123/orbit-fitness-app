# Run 8 — Program builder / periodization

_Post-launch run; the biggest one on the roadmap. The hard prerequisite for run 10 and a
strong accuracy boost for run 9 (it introduces performed-set logging; run 9 has a
set-count fallback without it). Consumed by requirements-elicitation + planning at run
start._

## Goal
Users create/edit their own workout programs (exercises, set×rep schemes, weights,
ordering), schedule them into blocks/weeks ("Wk 8 · Block 2" becomes real state), and —
critically — log what they actually lifted.

## The two schema decisions that dominate this run
1. **User-owned programs vs global seeds:** add `owner_uid` (nullable = seeded/global) to
   `programs`/`exercises`, or parallel `user_programs` tables. Lean: nullable owner on
   the existing tables (one query path, ownership predicate extends the existing
   repository seam; seeded Push Day stays owner NULL, read-only). **Standing rule:**
   user-owned `programs`/`exercises` rows join the `erase.py` cascade + AC5 erasure test
   + owner_uid registry in this run (owner-NULL seed rows stay outside the cascade).
2. **Exercise immutability/versioning (the history-integrity trap):** `set_events` FK
   exercises with prescribed weight/reps on the exercise row. If a user edits "Bench
   100 lb → 110 lb" in place, history silently rewrites. Logged-against exercise rows
   must be immutable — edits create a new version row; history keeps pointing at the
   version it was performed against. Decide version-chain shape (`exercise.replaces_id`
   lean) in-run. **This is the reason the run must not be improvised.**
- **Performed-set logging:** `set_events` gains `performed_weight_kg`/`performed_reps`
  (nullable — toggle-only remains valid; canonical metric per convention). This is the
  data runs 9–10 need; adding it here, where the logging UX is already open, avoids a
  third schema pass.

## Scope
CRUD endpoints (programs, exercises, ordering) — every list bounded (caps: programs/user,
exercises/program, hard LIMITs) + owner-scoped + validated (name length-bound,
muscle_tag from the fixed 13-group allowlist, scheme bounds); scheduling model
(block/week labels; keep to labels + active-program pointer — full periodization
calendars can wait); Train screen: program picker, builder UI, per-set weight/rep entry
(undepicted screens per the design README's "Extending the UI"); week-strip/score
semantics with multiple programs (score formula unchanged: base + today's done count).

## Security / compliance notes
Standard shapes throughout (IDOR on every new resource, unauth-denied, constraint→4xx,
Tier-2 write limits). Program/exercise names are user free-text → length-bound,
parameterized, logged by id only, encrypted at rest per run-2 classification review.

## Acceptance sketch
Build → schedule → log a session end-to-end (XCUITest); edit-after-log preserves history
(version test — the load-bearing one); seeded program read-only; caps enforced; cross-
owner 404s; per-set performed data persists and feeds the day's score/body derivations.

## Size
Large. Consider splitting: (a) performed-set logging on the seeded program, (b) builder
CRUD + versioning, (c) scheduling/blocks.
