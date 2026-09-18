# C6 — HealthKit activity (real calories-burned source)

_Phase C (features, local + Simulator), run 6 of 8. Makes "Burned +412" and the burn rate
real, and materially improves [C7](C7-adaptive-coach.md)'s TDEE accuracy (do this before
the coach). Consumed by requirements-elicitation + planning at run start._

## Goal
Read active energy from HealthKit (Apple Watch / iPhone motion) and feed the daily burned
figure into the ring math ("remaining = budget − eaten + burned") with real data.

## Local / Simulator notes
- **The Simulator supports HealthKit**: its Health app accepts manually entered sample
  data, and tests can write fixture samples. The whole flow is built and verified there.
- **Before the run, check** whether the HealthKit entitlement on a *physical device*
  requires the paid Apple Developer Program. The Simulator path needs no paid account.
- Real Watch/motion data is verified on a device during E3's TestFlight round.

## Scope
- **iOS**: HealthKit entitlement + `NSHealthShareUsageDescription`.
  - Read `activeEnergyBurned`. Also `basalEnergyBurned`? Lean no: TDEE estimation in C7
    owns the basal side.
  - A consent screen.
  - Background delivery vs on-open refresh: lean on-open + pull-to-refresh, with no
    background-modes complexity in v1.
- **Data minimization (the architectural rule):** raw HealthKit samples stay on the
  device; the backend receives only a per-day aggregate.
  - New table `day_activity(owner_uid, day_key, burned_kcal, source, updated_at)`,
    UNIQUE(owner_uid, day_key).
  - Bounded upsert `PUT /activity/{day_key}`, with the same validation, ownership and
    rate-limit shapes as every write.
- **Standing rule 1:** `day_activity` joins the `erase.py` cascade + the AC5 erasure test
  in this run and registers in the shared owner_uid-table registry. If no earlier run has
  built the registry by then, this run builds it and its export ∪ erase parity test (see
  `docs/roadmap.md` standing rule 1).
- **Consent revocation**: stop writes and show the zero-state. Decide whether stored
  aggregates are erased on revoke. Lean: keep them (they're the user's day history), but
  surface this in the policy.

## Store / compliance notes (this is the heavy half)
- **Apple 5.1.3**: HealthKit data may never be used for advertising or data-mining, may
  not be written to iCloud, and must be used for health-related purposes. All true by
  architecture — state it.
- **Privacy nutrition label + manifest update**: Health & Fitness data collection
  expands. This rides the E3 submission.
- **B1/B2 controls**: `day_activity` gets its field classification row, B2 encryption and
  B1 read-audit events (standing rule 2).

## Key decisions
- Watch-less users (phone-motion only): set expectations in the copy
- Unit edge: HealthKit returns kcal; store an int
- Backfill window on first consent: lean 7 days, bounded

## Acceptance sketch
- Consent → today's burned value appears in the ring math and the Home card (Simulator
  with sample data).
- Revoke → zero-state, no writes.
- `day_activity` rows are owner-scoped, bounded, B2-encrypted and B1-audited.
- Aggregate-only proven: no sample-level payloads in any request schema.
- Manifest updated; the label change is queued for E3.

## Size
Small-medium backend (one table + one endpoint); the work is iOS consent/UX + compliance.
