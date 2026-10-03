# E1 — Production deploy path (go live: apply, operate, prove)

_Phase E (going live), run 1 of 3. **Parked until the owner decides to go live**; nothing
here runs during Phases A–D. Consumed by requirements-elicitation + planning at run start._

> **Status (2026-09-17 reorder).** Development is local-first. By the time this runs,
> **A1** will have built the Dockerfile and the local stack, and **A2** will have authored
> and offline-validated the staging/prod Terraform (envs split, network completion,
> compute, WAF, observability alarms, the `bootstrap/` stack, and IAM). This run therefore
> **applies, operates and proves** what A2 authored, rather than writing it from
> scratch. The original brief below is retained in full as the go-live reference. Where
> it says to *author* something that A2 already delivered, read it as *apply and
> verify*.
>
> The original framing was: pre-launch gate 1 of 4. Greenfield shipped the data-security
> baseline (`infra/`: RDS, Redis, Secrets Manager, log groups, remote state) and an inert
> `deploy.yml`; the backend runs as a direct process. This run makes production real.

## Goal
A staging + production AWS environment the app actually runs on, deployed by CI on merge,
with rollback and someone-is-watching wiring — the launch prerequisite.

## Scope
- **Compute: AWS Lambda** (owner decision 2026-09-19, cost at 1–3 users; see
  [A2 § Compute decision](A2-production-terraform-authoring.md#compute-decision-owner-2026-09-19-aws-lambda-not-fargateapp-runner)).
  Apply A2's function, alias, front door and reserved-concurrency cap. Measure real cold
  starts; the p95 budget is judged warm.
- **Containerization:** A1's Dockerfile image is what Lambda runs (container-image
  Lambda, unless A2 chose zip). It goes through ECR per delivery-conventions (immutable
  SHA tags, cosign signing, SBOM, SLSA attestation, verify-before-rollout).
- **`envs/` staging/prod split** in Terraform; staging seeded (incl. DAST user) so k6 and
  ZAP Layers 2–3 (`dast-plan.md`) run against staging in CI.
- **Edge:** the front door A2 chose (CloudFront → Function URL, REST API, or HTTP API),
  with WAF where it attaches. Prove the rate limiter sees the real client IP (event
  `sourceIp`, or `CloudFront-Viewer-Address` trusted only from CloudFront), not a proxy
  IP and not a spoofable header.
- **Observability wiring (deferred half of observability-conventions):** SLO definitions
  + burn-rate alarms (the canary-rollback signal), synthetic monitoring on /health + one
  real read, Sentry release automation, iOS dSYM upload.
- **Deploy:** `DEPLOY_ENABLED=true`. Canary via Lambda weighted alias + CodeDeploy, with
  automated rollback on burn-rate alarm, proven with injected synthetic traffic (at 1–3
  users a canary slice sees none). The separate migration function runs before traffic
  shifts. `terraform apply` via the OIDC role in CI only.

## Key decisions / open questions
- Lambda cold starts in practice: accept, or pay for mitigation (SnapStart — supported
  for container images since July 2026, if it works with A2's runner; or provisioned
  concurrency, which excludes SnapStart) once real users exist.
- Custom domain + ACM cert; API base URL config for the iOS build (per-env xcconfig).
- DB migration execution in deploy: A2 authors a separate migration function (same
  image, its own small handler and role). Confirm the advisory lock, and that it runs
  before the alias shifts.
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
- A **Lambda concurrency quota increase** (to ≥ ~110). New accounts often start at 10,
  and reserved concurrency (A2's DB-connection cap) needs ≥ 100 left unreserved. File it
  on day one, because it can take time. Check whether a free-plan account can get it.
- The S3 state bucket + DynamoDB lock table (`infra/backend.hcl.example`)
- The GitHub OIDC identity provider + the `deploy_role_arn` / `ops_role_arn` roles

**GitHub settings (the agent's token cannot write Actions variables or secrets):**
- Repo variables: `DEPLOY_ENABLED=true`, plus `DAST_STAGING_ENABLED` and `DR_DRILL_ENABLED`
  for the staging-dependent workflows.
- A GitHub **`production` environment with a protection rule**. After merge, this is the
  human approval gate `deploy.yml` relies on.

**Outside services and obligations:**
- **A real Firebase project.** Everything so far runs against the Auth emulator
  (project `demo-orbit-test`):
  - The backend's Admin credentials go into Secrets Manager
    (`orbit/firebase-admin-credentials`).
  - `FIREBASE_PROJECT_ID` is set per environment.
  - The iOS `Resources/GoogleService-Info.plist`, which holds emulator-only
    placeholders today, is replaced with the real project's file before any
    staging/TestFlight build.
- A Sentry org/project + auth token (free tier) for release automation and dSYM upload.
- The **Firebase Authentication password policy** must be enabled. The ASVS `6.2.x`
  waiver was granted "with the enable at deploy follow-up", so this run discharges it.
  Waivers live in gitignored `.pipeline/waivers.json`; on a fresh clone, re-record them
  with `record-waiver.sh`.
- If the StoreKit spec (`docs/specs/storekit-monetization.md`) has been scheduled: this
  run owns the deployed App Store Server Notifications URL. That endpoint must survive
  the chosen front door, which rules out OAC without Lambda@Edge; see A2.
- A custom domain + ACM certificate (optional, ~$12/yr). Also needs per-environment iOS
  xcconfig base URLs for staging/prod, alongside A1's local one.

**Live-only verification owed by earlier phases (prove them here, don't re-derive):**
- A1/A2: IAM enforcement for every role A2 wrote (expect AccessDenied debugging on first
  apply — that is the lesson), VPC routing/security groups/NAT, RDS and ElastiCache
  behavior.
- B2: KMS key policy + app-role permissions under real enforcement.
- D1: backup retention ≤ 7 days, S3 object expiry actually enforced.
- Local data is synthetic and disposable, and never migrated. Production starts empty
  (new users start empty anyway); LocalStack-KMS ciphertext can't be decrypted by real
  KMS.

**Cost model (us-east-1 ballparks from 2026-09; re-check current pricing at run start):**

| Topology | Approx. cost |
|---|---|
| Original brief: staging + prod at parity (NAT gateway, ALB, Fargate, RDS, ElastiCache, WAF, KMS/Secrets/logs). Fargate-era figure; the Lambda switch drops the ALB and Fargate lines, and A2 re-estimates. | ~$200/mo if left running (~$110 prod + ~$89 staging) |
| Same topology, **applied only while working, then `terraform destroy`** | ~$0.27/hr — about $6 for a full day |
| **Lean single-env prod — the go-live target (2026-09-19):** Lambda + a CloudFront/Function-URL front door (API Gateway has no always-free tier; REST API ~$3.50/M requests), NAT instance, single-AZ `db.t4g.micro` RDS, free-tier hosted Redis instead of ElastiCache, SSM instead of Secrets Manager | ~$20–25/mo; add ~$8–10 for standalone WAF (common + IP-reputation rules; Bot Control extra), or ~$0 if CloudFront's flat-rate Free plan fits |

Items with no free tier: NAT gateway (~$33/mo), ALB (~$16), ElastiCache (~$12),
WAF (~$10), RDS (~$14 for single-AZ `db.t4g.micro` + 20 GB), public IPv4 addresses
(~$3.60/mo each). Lambda compute and requests (1M requests + 400k GB-s/month) and
CloudFront (1 TB + 10M requests/month) sit inside the always-free allowance at this
scale. `modules/data` defaults RDS to multi-AZ, which roughly doubles the RDS cost; the
lean env sets it single-AZ through `.tfvars`. The backend needs outbound internet (it fetches Firebase's token keys), so
some NAT is required. Redis can't simply be dropped: the rate limiter requires a shared
store, never in-process counters — hence a hosted free tier in the lean row.

For a learning-first owner, **apply → operate → break on purpose → destroy** sessions are
the intended mode. Leaving the stack running is only for once real users exist.

**AWS free plan (owner intent, 2026-09-19): create the account at the start of this run,
not earlier.** Accounts created after July 2025 get a credit-based free plan: roughly
$100 at signup plus up to about $100 more for onboarding tasks, over about 6 months. It
replaces the old "12 months of free RDS" tier, and the credits' clock starts at account
creation. At the lean row's rate the credits cover the first several months. Upgrade to
the paid plan before the free plan ends; free-plan accounts that aren't upgraded are
closed. Re-check the current terms at run start: they change.
