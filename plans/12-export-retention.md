# Run 12 — export-my-data + retention automation

_Post-launch run with a hard trigger: ships BEFORE any EU marketing push (GDPR Art. 20
portability); pull earlier if that comes sooner. CCPA access-right applies to California
users regardless — at small scale, manual fulfillment via support is the interim answer;
this run automates it. Consumed by requirements-elicitation + planning at run start._

## Goal
A user can export everything Orbit holds about them in a portable format, and the
declared retention policy is enforced by machinery rather than promise.

## Export design
- `POST /me/export` — **the one legitimately unbounded read in the system**, so it must
  not be a synchronous mega-query: async job writes a JSON bundle to S3 (SSE-KMS,
  per-user prefix) → short-lived presigned URL returned/surfaced in Settings. At current
  scale a bounded sync path may suffice — decide against measured row counts in-run, but
  design the contract async-shaped (`202 + status endpoint`) so scale never changes the
  API.
- Format: JSON (machine-readable satisfies Art. 20); one file per table + manifest.
  **Enumerate from the shared owner_uid-table registry (introduced in run 6), never a
  hand list** — by this run that means greenfield's five tables plus every addition from
  runs 6–11 that exists (`day_activity`, `tdee_estimates`, user-owned
  `programs`/`exercises`, `level_events`, `strength_scores`,
  `progression`/`progression_events`). The registry's parity test asserts
  export ∪ erase covers all owner_uid tables, so export and erasure can never drift.
- Values decrypt through the run-2 crypto facade (export is plaintext by definition —
  the presigned link is the control: minutes-TTL, single object, fresh re-auth to
  request, Tier-2 rate limit ~1/day, `data.export` audit event).

## Retention automation
Current policy: life-of-account (nothing to age out) — so the automation is
**verification, not deletion**: a scheduled check asserting backup retention ≤ 7 d
(the erasure-honesty window), audit-log retention = 90 d + archive lifecycle intact,
export objects expired. If any per-field retention shorter than life-of-account gets
declared later (e.g. day_activity), its enforcement job lands here.

## Security / compliance notes
Export endpoint: fresh re-auth (same 5-min `auth_time` guard as deletion — it's the
read-everything primitive), rate-limited, audited; S3 bucket private + SSE-KMS +
lifecycle-expire (24 h); presigned TTL minutes; no export content ever logged.

## Acceptance sketch
Export bundle contains every owner-scoped table's rows for the caller and nothing else
(cross-owner leak test); registry test proves export/erase table-list parity; stale
`auth_time` → 401; link expires; audit event emitted; retention-verification job green
and alarmed via run 2 on failure.

## Size
Small-medium; the table-registry parity mechanism is the durable value.
