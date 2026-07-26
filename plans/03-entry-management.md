# Run 3 — Entry management (per-entry edit/delete + idempotency)

_Pre-launch gate 3 of 4. Consumed by requirements-elicitation + planning at run start._

## Goal
Users can fix their own data (GDPR Art. 16 rectification; duplicate recovery), and
ambiguous-network retries stop being able to double-log. Closes greenfield's known gap:
food-entry creates are non-idempotent and nothing below account erasure is deletable.

## Scope
- **`DELETE /fuel/entries/{id}`** (and decide: `PATCH` edit vs delete-and-relog — lean
  delete-only first; edit adds validation surface for little gain).
- **`DELETE /weight/{id}`** (mis-entered weights poison the 30-day trend/delta).
- **Past-day set un-toggle?** Decision for elicitation — the depicted Train UI exposes
  only today, but the **API already accepts past `day_key`s** (backdating allowed, AC15;
  `DELETE /train/sets` is (uid, exercise, set, day)-scoped), so past-day toggles are
  API-legal in greenfield and score/week-strip derivations are already
  retroactive-capable. Decide: surface past-day editing in the UI, tighten the API to
  today-only, or leave as-is.
- **Idempotency keys** (api-edge-conventions) on `POST /fuel/entries` + `POST /weight`:
  client-generated UUID header; replay returns the original row (200), never a duplicate.
- iOS: swipe-to-delete on meal rows + weight list per the design's "Extending the UI"
  conventions; VoiceOver actions for the same.

## Data & schema touchpoints
Idempotency: `UNIQUE(owner_uid, idempotency_key)` on the two tables (nullable column;
TTL cleanup not needed at day-key scale) — or a shared keys table; decide in-run.
Deletes are hard deletes (consistent with the no-soft-delete lifecycle posture).

## Security / compliance notes
Owner-scoped delete by (id AND owner_uid) → cross-owner 404 (existing IDOR shape);
`entry.delete` audit events (id-only, no values); Tier-2 rate limit on the new writes;
totals/derived values re-verified after delete (score, week strip, trend).

## Acceptance sketch
Same-key replay → one row + same response; delete → row gone, day totals/trend update,
audit event emitted; cross-owner delete 404; unauth 401; past-day policy enforced as
decided; XCUITest swipe-to-delete flow.

## Size
Small. Fold into run 1 or 2's PR train if convenient, but keep its criteria distinct.
