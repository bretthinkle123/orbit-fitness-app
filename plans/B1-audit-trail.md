# B1 — Append-only audit trail (who touched which record)

_Phase B (data-protection foundation), run 1 of 2. Moved forward from the original SOC
brief's Part C ([E2](E2-soc-visibility.md)) so every Phase C feature run emits audit
events through a facade that already exists instead of retrofitting them. Consumed by
requirements-elicitation + planning at run start. Local; cost $0._

**Terminology:** "audit" here means the **security audit trail** — an immutable record of
who accessed or changed which record. It is not user-facing meal/workout logging, which is
ordinary app data (C1–C3).

## Goal
Every covered action on health/personal data produces an immutable audit event naming
the authenticated actor. The events go through one facade into an append-only sink and
never contain the data values themselves.

## Where things stand (greenfield as built)
- Audit-style events exist only as ordinary structured log lines in the app log stream,
  e.g. `get_logger().info("account.delete", user_id=<hashed>, outcome=...)` in
  `routes/me.py`.
- Terraform provisions a CloudWatch `audit` log group with a delete-deny resource policy,
  but no app path routes to it.
- No read-access events exist.

## Scope
- **Audit facade** `src/orbit/audit/`, per audit-trail-conventions. It is the only writer
  of audit events, the same pattern as the crypto facade. Existing audit-style log lines
  (e.g. `account.delete`) migrate onto it.
- **Event schema**: actor (hashed uid via the crypto facade), action, resource type +
  record id(s), outcome, timestamp, trace id. **Never values.**
- **Covered actions**:
  - Reads of health/personal data: the fuel day and the weight window. These are the
    data the original SOC brief already identified as health data. B2 runs after this
    and builds the full classification table; any field it classifies health-grade is
    added to the covered list then, in B2.
  - Creates, updates and deletes of those records
  - Account deletion
  - Consent changes (B2)
  - Export (D1), later

  Planning maps each existing endpoint to covered or not-covered.
- **Sink — append-only by construction**. Lean: a Postgres `audit_events` table where
  the app's DB role has INSERT only (no UPDATE/DELETE grants), so it is append-only even
  if the app layer is compromised. It behaves identically on local Postgres and on RDS.
  Alternative: CloudWatch Logs via LocalStack. Shipping the events to the existing
  CloudWatch audit group is E2's job.
- **Retention**: declared per the data-lifecycle table. Greenfield's plan chose 90 days
  hot; the S3/Glacier archive belongs to E2.
- **Erasure interaction**: events carry the hashed uid, not the raw uid. Decide in-run
  whether `audit_events` is erasure-exempt, with a recorded basis
  (security/legal-obligation), or deleted by hashed uid. Record the outcome in the
  lifecycle table either way. The owner_uid-table registry doesn't exist yet when B1
  runs; whichever run later builds it (B2, C1 or C3) records `audit_events`' status there
  (roadmap standing rule 1).

## Key decisions
- Sink: the DB table (lean) vs CloudWatch Logs
- Synchronous insert per covered read vs a buffered/async writer. This is a perf
  question; re-measure p95.
- The erasure basis for audit rows

## Security / compliance notes
- The append-only property is enforced by DB grants, not convention.
- A static check confirms the facade is the only writer.
- Payloads are values-free: tested, not assumed.
- No new user-facing input surface.

## Acceptance sketch
- Each covered action → **query the raw sink** → an event with the right actor, action,
  resource and outcome exists.
- UPDATE/DELETE on `audit_events` as the app role fails (append-only test).
- No event contains a value field (schema test).
- Existing `account.delete` routed through the facade.
- p95 still < 300 ms at ~10 concurrent with read-auditing on.
- All of this is proven on the local stack.

## Size
Small-medium; one facade, one table + migration + grants, a route sweep, tests.
