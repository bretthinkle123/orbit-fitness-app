# A2 — Production Terraform, authored and validated (never applied)

_Phase A (local foundation), run 2 of 2. Consumed by requirements-elicitation + planning at
run start. Writes the staging/prod infrastructure that [E1](E1-production-deploy-path.md)
later applies, so going live becomes apply-and-operate rather than write-from-scratch.
Cost: $0 — nothing here touches a real AWS account._

## Goal
The complete production topology exists as reviewed, Checkov-clean Terraform, validated
with `terraform plan` offline. The owner studies (and can modify) the full production
design long before paying for any of it.

## Scope
- **The `infra/envs/` split**: `envs/staging` and `envs/prod` roots alongside A1's
  `envs/local`, all sharing the same modules. Staging mirrors prod's shape at a smaller
  size. Greenfield's root composition (`infra/main.tf` + its variables/outputs) moves
  into `envs/prod`, leaving `infra/` as `modules/` + `envs/` + `bootstrap/`.
- **Network completion**: public subnets, internet gateway, NAT, route tables. Today's
  VPC is private-subnet-only. The backend needs outbound internet (it fetches Firebase's
  token-verification keys from Google), so some NAT is required. Choose NAT gateway vs a
  NAT instance, informed by the cost estimate.
- **Compute**: ECS Fargate + ALB vs App Runner, decided with containerization-conventions'
  rubric. Evidence to weigh: greenfield's task role already assumes
  `ecs-tasks.amazonaws.com`, and `deploy.yml`'s canary is built on ALB weighted target
  groups, whereas the original brief leaned App Runner. Also autoscaling floor/ceiling and
  HTTPS.
- **Edge**: WAF (managed common/bot/IP-reputation rules), attached to the ALB on ECS or
  associated directly on App Runner. The rate limiter's trusted-proxy source gets pinned
  to the chosen ingress.
- **Observability Terraform**: SLO definitions, burn-rate alarms (the canary-rollback
  signal), SNS topics, synthetic canary definitions.
- **Deploy/CI identity — `infra/bootstrap/`**: the GitHub OIDC provider, the deploy and
  ops roles, and the S3 state bucket + DynamoDB lock table. This is the manual
  chicken-and-egg bootstrap E1 runs once. It is authored here and applied there.
- **IAM throughout**: least-privilege policies for every role, written in full. Nothing
  enforces them until E1, so they get written carefully here.
- **`deploy.yml`**: its placeholders are mapped to the Terraform outputs that will fill
  them. The workflow stays inert (`DEPLOY_ENABLED` unset).
- **Cost estimate** per environment (monthly and hourly) as a committed doc. It feeds
  E1's always-on vs apply-and-destroy decision.

## Validation (the gates for an unapplied run)
- `terraform validate` + `plan` on every root with `offline_validate=true`
- Checkov and Trivy config scan clean
- tflint, if adopted in-run

## Rule this run sets for every later run
A run that adds an AWS resource adds it to the shared module **and** to envs/local (if
LocalStack supports it) **and** to envs/staging/prod, in the same run. The authored
production config never goes stale. See the roadmap's local-first rule.

## Security / compliance notes
- Re-model the compute-topology STRIDE rows greenfield deferred (plan §Accepted risks).
- Trivy `AWS-0104` (unrestricted egress on the db/redis security groups) was accepted
  "until compute lands". With the NAT/route topology now authored, narrow the egress
  here.
- No new app input surface.

## Out of scope (stays in E1)
- Any `terraform apply` to real AWS
- The account and budget alert
- Bootstrap execution
- Canary proven by fault injection
- Synthetics green
- Alarm → SNS verified end-to-end
- Sentry release automation and iOS dSYM upload
- Custom domain + ACM

## Acceptance sketch
- Every envs/ root plans clean offline; Checkov/Trivy clean.
- Topology diagram added to `docs/system_architecture.md`.
- Cost estimate committed.
- IAM policy inventory, stating each role's allowed actions and why.
- `deploy.yml` placeholder → output map documented.
- The E1 brief updated to "apply and operate what A2 authored".

## Size
Medium-large; almost entirely Terraform + docs; zero app code.
