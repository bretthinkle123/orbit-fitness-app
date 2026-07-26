# Run 1 — Production deploy path (compute topology + full observability wiring)

_Pre-launch gate 1 of 4. Consumed by requirements-elicitation + planning at run start.
Greenfield shipped the data-security baseline (`infra/`: RDS, Redis, Secrets Manager,
log groups, remote state) and an inert `deploy.yml`; the backend runs as a direct
process. This run makes production real._

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
