# E2 — SOC visibility & security monitoring (go live)

_Phase E (going live), run 2 of 3. **Parked until the owner decides to go live.** Consumed
by requirements-elicitation + planning at run start. Assumes E1 (prod exists)._

> **Status (2026-09-17 reorder).** This brief originally bundled three parts. **Part C
> (data-sensitivity hardening) moved forward** into Phase B, so every feature run inherits
> it:
> - Per-record read-access audit → [B1](B1-audit-trail.md)
> - Field-level KMS encryption + consent UX → [B2](B2-field-encryption-consent.md)
>
> What remains here is Parts A and B, which need real AWS: detection, paging, GuardDuty,
> CloudTrail, the auditor/responder IAM roles and their negative tests, and runbooks. It
> also ships B1's audit events into the CloudWatch `audit` log group + S3/Glacier archive.
> The metric filters, alarms and SNS Terraform *may* be authored ahead of time on the A2
> pattern (plan-validated, not applied); decide at run start. Verification is live-only.
>
> The original framing was: pre-launch gate 2 of 4. Scope assumed greenfield as built
> (structured audit logs to CloudWatch app + immutable audit groups, X-Ray, thin Sentry
> init, `infra/` observability module) and prod existing.

## Goal
A SOC analyst can **detect** security events (dashboard + paging); a responder can
**investigate and contain** them (queries, evidence, runbooks, least-privilege access) —
AWS-native managed services (CloudWatch + GuardDuty + CloudTrail + SNS = the
Well-Architected detective controls; read-only, no new app attack surface). **No in-app
admin UI** — trusted-personnel access is IAM, not app code. (The health-data
escalation controls moved to B1/B2 and land before this run.)

## Part A — Detect & page (Terraform in `infra/modules/observability`)
1. CloudWatch **metric filters** per detection signal (catalog below) — exact-field
   filters over the structured logs.
2. **Alarms → SNS**, severity-tiered topics (`security-page` / `security-digest`);
   email now, PagerDuty later.
3. **Dashboard** — security pane (auth failures, denials, 429s, validation warns,
   deletions, revocations) + health pane (p95, error rate, log volume).
4. **GuardDuty** → EventBridge → SNS. 5. **CloudTrail in Terraform** (S3, log-file
   validation). 6. **Silent-failure alarm** (log-ingestion absence). 7. **Sentry alert
   rules** into the same path. 8. **Retention-check alarm**: alarm on failure of D1's
   retention-verification job. D1 ran locally before go-live, so the live alarming it
   owes lands here.

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

## Part C — Data-sensitivity hardening → moved to Phase B
Moved to [B1](B1-audit-trail.md) (read-access audit trail) and
[B2](B2-field-encryption-consent.md) (field-level KMS encryption, consent UX, the
health-data classification rationale). The privacy-policy **legal review** checkpoint
from this part is a go-live item and moves to [E3](E3-app-store-submission.md). This run
proves B2's KMS key policy + app-role permissions under real IAM enforcement.

## Acceptance sketch
Every catalog row: filter+alarm exist (Terraform-asserted) + synthetic event fires
end-to-end to SNS; auditor role passes view/query tests and fails write (negative IAM);
GuardDuty sample finding routes; silent-failure alarm fires under fault; R1+R4 tabletop
walked; B1 audit events delivered to the CloudWatch audit group + archive lifecycle
intact; D1's retention-verification job alarms on failure; B2's KMS permissions hold
under real IAM (the app role can decrypt, other principals can't); Checkov clean.
(Encrypted-at-rest, read-audit append-only and consent gating were proven in B1/B2.)

## Non-goals
In-app admin screens; extra PII for monitoring (hashed uid stays the key);
auto-remediation without a human; SIEM before a SOC exists (Phase-3 escalations — WAF
logs, Security Hub, OpenSearch export, anomaly detection — deferred until traffic/team
justify).

## Size
Medium (Terraform + runbooks + IAM). The encryption migration moved to B2.
