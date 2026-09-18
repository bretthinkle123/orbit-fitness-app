# E1 — Production deploy path (go live: apply, operate, prove)

_Phase E (going live), run 1 of 3. **Parked until the owner decides to go live**; nothing
here runs during Phases A–D. Consumed by requirements-elicitation + planning at run start._

> **Status (2026-09-18 reorder).** Development is local-first. By the time this runs,
> **A1** will have built the Dockerfile and the local stack, and **A2** will have authored
> and offline-validated the staging/prod Terraform (envs split, network completion,
> compute, WAF, observability alarms, the `bootstrap/` stack, and IAM). This run therefore
> **applies, operates and proves** what A2 authored,
> rather than writing it from scratch. The original brief below is retained in full as
> the go-live reference. Where it says to *author* something that A2 already delivered,
> read it as *apply and verify*.
>
> The original framing was: pre-launch gate 1 of 4. Greenfield shipped the data-security
> baseline (`infra/`: RDS, Redis, Secrets Manager, log groups, remote state) and an inert
> `deploy.yml`; the backend runs as a direct process. This run makes production real.

## Goal
A staging + production AWS environment the app actually runs on, deployed by CI on merge,
with rollback and someone-is-watching wiring — the launch prerequisite.

## Scope
- **Compute:** App Runner vs ECS Fargate decision (rubric: containerization-conventions;
  App Runner favored at this scale for managed simplicity, ECS if WAF/NLB needs force it)
  + HTTPS + autoscaling floor/ceiling (ALB exists only on the ECS branch; App Runner has
  no customer ALB and attaches its WAF web ACL directly).
- **Containerization:** the direct process almost certainly becomes a container here —
  Dockerfile per delivery-conventions (immutable SHA tags, cosign signing, SBOM, SLSA
  attestation, verify-before-rollout).
- **`envs/` staging/prod split** in Terraform; staging seeded (incl. DAST user) so k6 and
  ZAP Layers 2–3 (`dast-plan.md`) run against staging in CI.
- **Edge:** WAF (managed common/bot/ip-reputation rules) + optional CloudFront; pin the
  rate-limiter's trusted-proxy XFF source per the compute choice (ALB CIDR on ECS; App
  Runner's managed ingress otherwise) — greenfield coded the trust-only-named-proxy
  shape, this run supplies the actual CIDRs.
- **Observability wiring (deferred half of observability-conventions):** SLO definitions
  + burn-rate alarms (the canary-rollback signal), synthetic monitoring on /health + one
  real read, Sentry release automation, iOS dSYM upload.
- **Deploy:** `DEPLOY_ENABLED=true`, canary/rolling strategy + automated rollback on
  burn-rate alarm; `terraform apply` via the OIDC role in CI only.

## Key decisions / open questions
- App Runner vs ECS Fargate (WAF attaches to ALB — App Runner needs its own WAF assoc).
- Custom domain + ACM cert; API base URL config for the iOS build (per-env xcconfig).
- DB migration execution in deploy (one-off task vs app-start gate; advisory lock).
- Staging data policy (synthetic only; never prod restores).

## Security / compliance notes
Re-model the deferred compute-topology STRIDE rows (plan §Accepted risks); Checkov on all
new Terraform; image scanning in the delivery path; no new app input surface.

## Acceptance sketch
Staging + prod applied from CI; merge → staging deploy → smoke + k6 + DAST vs staging →
prod canary with auto-rollback proven once by fault injection; synthetics green; alarm →
SNS verified end-to-end; Checkov clean; runbook for deploy/rollback.

## Size
Medium-large; mostly Terraform + CI + one Dockerfile; minimal app-code change (config).


## Going-live prerequisites & costs (captured 2026-09 planning discussion)

**Manual bootstrap, done by the owner before CI can apply anything.** Terraform needs
these to exist before it can run, so it cannot create them itself. The `infra/bootstrap/`
stack A2 authored is applied once, by hand:
- An AWS account, with an **AWS Budget alert set before the first apply** (e.g. $25/mo)
- The S3 state bucket + DynamoDB lock table (`infra/backend.hcl.example`)
- The GitHub OIDC identity provider + the `deploy_role_arn` / `ops_role_arn` roles

**GitHub settings (the agent's token cannot write Actions variables or secrets):**
- Repo variables: `DEPLOY_ENABLED=true`, plus `DAST_STAGING_ENABLED` and `DR_DRILL_ENABLED`
  for the staging-dependent workflows.
- A GitHub **`production` environment with a protection rule**. After merge, this is the
  human approval gate `deploy.yml` relies on.

**Outside services and obligations:**
- A Sentry org/project + auth token (free tier) for release automation and dSYM upload.
- The **Firebase Authentication password policy** must be enabled. The ASVS `6.2.x`
  waiver was granted "with the enable at deploy follow-up", so this run discharges it.
  Waivers live in gitignored `.pipeline/waivers.json`; on a fresh clone, re-record them
  with `record-waiver.sh`.
- A custom domain + ACM certificate (optional, ~$12/yr). Also needs per-environment iOS
  xcconfig base URLs for staging/prod, alongside A1's local one.

**Live-only verification owed by earlier phases (prove them here, don't re-derive):**
- A1: IAM enforcement (expect AccessDenied debugging on first apply — that is the lesson),
  VPC routing/security groups/NAT, RDS and ElastiCache behavior.
- B2: KMS key policy + app-role permissions under real enforcement.
- D1: backup retention ≤ 7 days, S3 object expiry actually enforced.
- Local data is synthetic and disposable, and never migrated. Production starts empty
  (new users start empty anyway); LocalStack-KMS ciphertext can't be decrypted by real
  KMS.

**Cost model (us-east-1 ballparks from 2026-09; re-check current pricing at run start):**

| Topology | Approx. cost |
|---|---|
| Brief as written: staging + prod at parity (NAT gateway, ALB, Fargate, RDS, ElastiCache, WAF, KMS/Secrets/logs) | ~$200/mo if left running (~$110 prod + ~$89 staging) |
| Same topology, **applied only while working, then `terraform destroy`** | ~$0.27/hr — about $6 for a full day |
| Lean single-env prod (App Runner, NAT instance, no ElastiCache, SSM instead of Secrets Manager) | ~$20/mo in year one (RDS free tier), ~$32/mo after |

Items with no free tier: NAT gateway (~$33/mo), ALB (~$16), ElastiCache (~$12),
WAF (~$10). The backend needs outbound internet (it fetches Firebase's token keys), so
some NAT is required. For a learning-first owner, **apply → operate → break on purpose →
destroy** sessions are the intended mode. Leaving the stack running is only for once real
users exist.
