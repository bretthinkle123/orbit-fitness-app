# C1 — Entry management (per-entry edit/delete + idempotency)

_Phase C (features, local + Simulator), run 1 of 8. Consumed by requirements-elicitation +
planning at run start._

## Goal
Users can fix their own data (GDPR Art. 16 rectification; duplicate recovery), and
ambiguous-network retries can no longer save the same meal or weigh-in twice. This closes
greenfield's known gap: food-entry creates are non-idempotent, and nothing below account
erasure is deletable.

## Scope
- **`DELETE /fuel/entries/{id}`**. Decide `PATCH` edit vs delete-and-relog; lean
  delete-only first, since edit adds validation surface for little gain.
- **`DELETE /weight/{id}`**: mis-entered weights poison the 30-day trend/delta.
- **Past-day set un-toggle?** A decision for elicitation:
  - The depicted Train UI exposes only today, but the **API already accepts past
    `day_key`s** (backdating allowed, AC15).
  - `DELETE /train/sets` is (uid, exercise, set, day)-scoped, so past-day toggles are
    already API-legal, and the score/week-strip derivations can already recompute
    retroactively.
  - Options: surface past-day editing in the UI, tighten the API to today-only, or leave
    as-is.
- **Idempotency keys** (api-edge-conventions) on `POST /fuel/entries` + `POST /weight`: a
  client-generated UUID header; a replay returns the original row (200), never a
  duplicate.
- **iOS**: swipe-to-delete on meal rows and the weight list, per the design's "Extending
  the UI" conventions, with matching VoiceOver actions.

## Data & schema touchpoints
- **Idempotency storage**: `UNIQUE(owner_uid, idempotency_key)` on the two tables
  (nullable column; no TTL cleanup needed at day-key scale), or a shared keys table.
  Decide in-run.
- **If the shared-keys table wins**, it may be the first run to add an owner-scoped table.
  If so, it owns building the owner_uid-table registry and its export ∪ erase parity test,
  and adds the table to the `erase.py` cascade and the AC5 erasure test (roadmap standing
  rule 1). It also gets a data-classification row and the B1/B2 controls (standing
  rule 2). The nullable-column option carries none of these obligations.
- Deletes are hard deletes (consistent with the no-soft-delete lifecycle posture).

## Security / compliance notes
- Owner-scoped delete by (id AND owner_uid) → cross-owner 404 (the existing IDOR shape).
- `entry.delete` audit events through the B1 audit facade (id-only, no values).
- Tier-2 rate limit on the new writes.
- Totals/derived values re-verified after delete (score, week strip, trend).

## Acceptance sketch
- Same-key replay → one row + the same response.
- Delete → row gone, day totals/trend update, audit event in the B1 sink.
- Cross-owner delete → 404; unauth → 401.
- Past-day policy enforced as decided.
- XCUITest swipe-to-delete flow in the Simulator against the A1 local stack.

## Size
Small.
