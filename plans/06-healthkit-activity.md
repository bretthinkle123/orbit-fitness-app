# Run 6 — HealthKit activity (real burned-kcal source)

_Post-launch run; makes "Burned +412" / burn-rate real and materially improves run 7's
TDEE accuracy (do this before the coach). Consumed by requirements-elicitation +
planning at run start._

## Goal
Read active-energy from HealthKit (Apple Watch / iPhone motion) and feed the daily
burned figure into the ring math ("remaining = budget − eaten + burned") with real data.

## Scope
- iOS: HealthKit entitlement + `NSHealthShareUsageDescription`; read
  `activeEnergyBurned` (decide: + `basalEnergyBurned`? lean no — TDEE estimation in run
  7 owns the basal side); consent screen; background delivery vs on-open refresh
  (lean on-open + pull-to-refresh — no background modes complexity in v1).
- **Data minimization (the architectural rule):** raw HealthKit samples stay on device;
  the backend receives only a per-day aggregate. New table
  `day_activity(owner_uid, day_key, burned_kcal, source, updated_at)` —
  UNIQUE(owner_uid, day_key), bounded upsert (`PUT /activity/{day_key}`), same
  validation/ownership/rate-limit shapes as every write. **Standing rule (first
  new-table run):** `day_activity` joins the `erase.py` cascade + the AC5 erasure test
  in this run, and this run introduces the shared owner_uid-table registry with its
  export∪erase parity test (pulled forward from run 12) so no later run can under-erase.
- Consent revocation: stop writes, show 0-state; decide whether stored aggregates are
  erased on revoke (lean: keep — they're the user's day history — but surface in policy).

## Store / compliance notes (this is the heavy half)
- Apple 5.1.3: HealthKit data may never be used for advertising/data-mining; may not be
  written to iCloud; usage must be health-related — all true by architecture, state it.
- Privacy nutrition label + manifest update: Health & Fitness data collection expands;
  rides the next submission.
- Run 2's hardening already classified this data health-grade (encryption + read-audit
  cover `day_activity` too — add the field classification row).

## Key decisions
Watch-less users (phone-motion only — set expectation copy); unit edge (HK returns kcal;
store int); backfill window on first consent (lean: 7 days, bounded).

## Acceptance sketch
Consent → today's burned appears in ring math + Home card; revoke → zero-state, no
writes; day_activity rows owner-scoped/bounded/encrypted per run 2; aggregate-only
proven (no sample-level payloads in any request schema); manifest/label updated.

## Size
Small-medium backend (one table + one endpoint); the work is iOS consent/UX + compliance.
