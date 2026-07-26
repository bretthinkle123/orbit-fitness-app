# Run 2 — SOC visibility & security monitoring + data-sensitivity hardening

_Pre-launch gate 2 of 4. Consumed by requirements-elicitation + planning at run start.
Scope assumes greenfield as built (structured audit logs to CloudWatch app + immutable
audit groups, X-Ray, thin Sentry init, `infra/` observability module) and run 1 (prod
exists). **Encryption must land in this run, pre-users:** post-launch it becomes a live
dual-write migration through KMS._

## Goal
A SOC analyst can **detect** security events (dashboard + paging); a responder can
**investigate and contain** them (queries, evidence, runbooks, least-privilege access) —
AWS-native managed services (CloudWatch + GuardDuty + CloudTrail + SNS = the
Well-Architected detective controls; read-only, no new app attack surface). **No in-app
admin UI** — trusted-personnel access is IAM, not app code. Plus: the health-data
escalation controls, landed before real users exist.

## Part A — Detect & page (Terraform in `infra/modules/observability`)
1. CloudWatch **metric filters** per detection signal (catalog below) — exact-field
   filters over the structured logs.
2. **Alarms → SNS**, severity-tiered topics (`security-page` / `security-digest`);
   email now, PagerDuty later.
3. **Dashboard** — security pane (auth failures, denials, 429s, validation warns,
   deletions, revocations) + health pane (p95, error rate, log volume).
4. **GuardDuty** → EventBridge → SNS. 5. **CloudTrail in Terraform** (S3, log-file
   validation). 6. **Silent-failure alarm** (log-ingestion absence). 7. **Sentry alert
   rules** into the same path.

### Detection catalog (tune thresholds in-run)
| Signal | Source | Threshold | Sev | Response |
|---|---|---|---|---|
| Credential stuffing / token abuse | auth-failure events | >20/min for 5 min | High | R1 |
| IDOR probing | cross-owner-denial events | >5/min single uid | High | R1 |
| Input fuzzing | validation-`warn` rate | >50/min | Med | R2 |
| Rate-limit pressure | 429 events | sustained 15 min | Med | R2 |
| Account-deletion anomaly | `account.delete` | >N/hr (baseline ~0) | High | R3 |
| Mass sign-out/revocation | user-security events | vs baseline | Med | R3 |
| Control-plane touch | CloudTrail: non-app-role `GetSecretValue`; log-policy/RDS change | any | High | R4 |
| GuardDuty finding | GuardDuty | ≥ Medium | per | R4 |
| Error spike | Sentry/5xx | release regression | Med | triage agent |
| Logs went quiet | ingestion bytes | 0 for 15 min | High | availability |

## Part B — Respond (runbooks + access model)
- **IAM:** `security-auditor` (read-only: Logs Insights both groups, dashboard, GuardDuty,
  CloudTrail, X-Ray; MFA; negative-tested no-write) and `incident-responder` (auditor +
  secret-rotation trigger, RDS snapshot/PITR; no DB data-plane read). Firebase console
  disable/revoke = documented containment lever (named humans, MFA).
- **Runbooks `docs/runbooks/` R1–R5** (token abuse; probing; takeover/deletion anomaly;
  control-plane/secret compromise; PITR recovery): detect → scope (saved Logs Insights
  queries committed as code) → contain → recover → evidence. Pipeline triage agent =
  app-defect entry point.
- **Evidence:** audit group 90 d hot + S3 archive lifecycle (Glacier; hashed-uid only, no
  PII, privacy-safe).

## Part C — Data-sensitivity hardening (the escalation, landed now)
Weight-over-time + diet logs are health data under GDPR Art. 9 (in context), WA My
Health My Data, CPRA sensitive PI, FTC HBNR, and Apple's Health & Fitness label — though
not HIPAA (consumer app). (The app stores no height and computes no BMI; if either is
ever added it inherits this classification.) Greenfield's pseudonymization+SSE posture was proportionate
pre-launch; this run escalates before users exist:
- **Field-level KMS envelope encryption** for weight values and food entry values
  (name/kcal/macros) via the `src/orbit/crypto/` facade; migration converts columns;
  value CHECKs move fully to Pydantic (DB CHECKs on ciphertext drop — document).
  Totals computed app-side (≤200 rows/day — already the shape).
- **Per-record read-access audit events** (audit-trail-conventions): who read which
  record-set, when, outcome — never values.
- **Consent UX** (explicit consent at register for health-data processing) + privacy
  policy/legal review checkpoint.

## Acceptance sketch
Every catalog row: filter+alarm exist (Terraform-asserted) + synthetic event fires
end-to-end to SNS; auditor role passes view/query tests and fails write (negative IAM);
GuardDuty sample finding routes; silent-failure alarm fires under fault; R1+R4 tabletop
walked; encrypted-at-rest proven (raw column read ≠ plaintext; API round-trip intact);
read-audit events emitted + append-only; consent flow blocks data writes until accepted;
Checkov clean.

## Non-goals
In-app admin screens; extra PII for monitoring (hashed uid stays the key);
auto-remediation without a human; SIEM before a SOC exists (Phase-3 escalations — WAF
logs, Security Hub, OpenSearch export, anomaly detection — deferred until traffic/team
justify).

## Size
Medium (Terraform + runbooks) + the encryption migration (contained: crypto facade +
repositories + one migration + tests).
