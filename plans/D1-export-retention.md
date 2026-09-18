# D1 — Export-my-data + retention automation

_Phase D (pre-live hardening, local), run 1 of 1. Required before going live, and hard
before any EU marketing push (GDPR Art. 20 portability). The CCPA access right applies to
California users regardless. Consumed by requirements-elicitation + planning at run start.
Local, with S3 via LocalStack; cost $0._

## Goal
A user can export everything Orbit holds about them in a portable format, and the
declared retention policy is enforced by machinery rather than by promise.

## Export design
- **`POST /me/export`** — **the one legitimately unbounded read in the system**, so it
  must not be a synchronous mega-query:
  - An async job writes a JSON bundle to S3 (SSE-KMS, per-user prefix).
  - A short-lived presigned URL is returned and surfaced in Settings.
  - At current scale a bounded sync path may suffice; decide against measured row counts
    in-run. Either way, design the contract async-shaped (`202` + status endpoint) so
    scale never changes the API.
- **Locally**: the bucket is created by Terraform in envs/local on LocalStack and authored
  for staging/prod (A2 rule). The Simulator downloads via the LocalStack presigned URL on
  localhost.
- **Format**: JSON (machine-readable satisfies Art. 20); one file per table + a manifest.
- **Enumerate from the shared owner_uid-table registry, never a hand list.** The registry
  is built by whichever Phase C run first added an owner-scoped table. By this run it
  covers greenfield's five tables plus every Phase C addition that exists:
  `day_activity`, `tdee_estimates`, user-owned `programs`/`exercises`, `level_events`,
  `strength_scores`, `progression`/`progression_events`, and any C1 idempotency table.
  The registry's parity test asserts export ∪ erase covers all owner_uid tables, so
  export and erasure can never drift.
- **Values decrypt through the B2 crypto facade.** Export is plaintext by definition, so
  the presigned link is the control:
  - Minutes-long TTL, single object
  - Fresh re-auth to request
  - Tier-2 rate limit (~1/day)
  - A `data.export` audit event via the B1 facade

## Retention automation
- **Current policy**: life of account, so there is nothing to age out. The automation is
  therefore **verification, not deletion**: a scheduled check asserting retention holds.
- **Checkable locally in this run**:
  - B1 audit-sink retention as declared
  - Export objects expire (the lifecycle rule is configured and asserted in Terraform)
  - The job itself runs green
- **Live-only, deferred to Phase E (proven in E1/E2)**:
  - Backup retention ≤ 7 days (the erasure-honesty window — an RDS setting)
  - The audit archive lifecycle
  - LocalStack actually enforcing S3 object expiry — it may not
  - Alarming the check's failure via E2
- If any per-field retention shorter than life-of-account gets declared later (e.g.
  `day_activity`), its enforcement job lands here.

## Security / compliance notes
- Export endpoint: fresh re-auth (the same 5-minute `auth_time` guard as deletion — it's
  the read-everything primitive), rate-limited, audited.
- S3 bucket private + SSE-KMS + lifecycle expiry (24 h); presigned TTL in minutes.
- No export content is ever logged.
- IAM: the app role gets put/get on the export prefix only (written now, enforced in E1).

## Acceptance sketch
- The export bundle contains every owner-scoped table's rows for the caller and nothing
  else (cross-owner leak test).
- The registry test proves export/erase table-list parity.
- Stale `auth_time` → 401.
- The link expires (TTL asserted).
- The audit event lands in the B1 sink.
- The retention-verification job runs green locally.
- Live-only checks recorded as E-phase items.

## Size
Small-medium; the table-registry parity mechanism is the durable value.
