# A2 — Production Terraform, authored and validated (never applied)

_Phase A (local foundation), run 2 of 2. Consumed by requirements-elicitation + planning at
run start. Writes the staging/prod infrastructure that [E1](E1-production-deploy-path.md)
later applies, so going live becomes apply-and-operate rather than write-from-scratch.
Cost: $0 — nothing here touches a real AWS account._

## Goal
The complete production topology exists as reviewed, Checkov-clean Terraform, validated
with `terraform plan` offline. The owner studies (and can modify) the full production
design long before paying for any of it.

## Compute decision (owner, 2026-09-19): AWS Lambda, not Fargate/App Runner
The backend deploys to **AWS Lambda**. The reason is cost at the expected launch scale
(1–3 users for a long while):
- Lambda compute sits inside the always-free allowance (1M requests + 400k GB-s/month).
- A CloudFront or Function URL front door can too.
- That leaves the database and NAT as the main fixed costs (~$20–25/mo lean; see E1's
  cost model).
- The smallest Fargate task plus an ALB would add roughly $25/mo on top.

Both options scale. Lambda scales per request, up to the account's concurrency quota. Its
practical limit is Postgres connections, not compute. containerization-conventions'
rubric allows Lambda for spiky, low-traffic workloads. This brief records it as an owner
call, so planning does not re-open the choice.

Accepted trade-off: **cold starts.** With 1–3 users most requests land on a cold
function, and importing FastAPI + SQLAlchemy + firebase_admin + boto3 takes seconds. The
CLAUDE.md p95 < 300 ms budget is measured warm at ~10 concurrent, so it still applies.
Cold-start latency is measured and reported separately, never averaged into it.

What this changes, and what A2 must decide at run start (verified in an audit on
2026-09-19; re-check anything marked unverified):
- **Packaging: a Lambda container image (recommended) vs a zip.**
  - A1's Dockerfile builds one image for local compose and for Lambda. The image path
    keeps delivery-conventions intact: ECR, immutable SHA tags, cosign, SBOM,
    verify-before-rollout.
  - Runner options:
    - **AWS Lambda Web Adapter (LWA)**, copied into `/opt/extensions` and inert outside
      Lambda. uvicorn runs unchanged, and `src/orbit/` has no Lambda-only entrypoint.
    - **Mangum**, a small handler wrapping the FastAPI app. It must live outside
      `src/orbit/` (CLAUDE.md).
    - The choice interacts with client IP (below). Weigh them together.
  - With LWA, set `AWS_LWA_READINESS_CHECK_PATH=/health` (the default is `/`).
  - **SnapStart** (the main cold-start mitigation) supports container images since
    July 2026, as well as zip:
    - AWS base images work as-is. A custom base image needs the
      `com.amazonaws.lambda.feature.snapstart="Allow"` label and possibly runtime hooks.
    - Python pays caching and restore charges.
    - It excludes provisioned concurrency and EFS.
    - Unverified: SnapStart alongside the LWA extension. Test it before relying on it.
- **Front door + WAF.** WAF cannot attach to an API Gateway HTTP API or a Lambda Function
  URL. The options:
  - (a) CloudFront → Function URL, WAF on CloudFront.
    - CloudFront's always-free tier covers this scale. Evaluate CloudFront's flat-rate
      **Free plan** (Nov 2025), which bundles WAF and DDoS protection. Unverified: its
      compatibility with Function URL origins.
    - **Trap:** with origin access control (OAC) on a Function URL, every POST/PUT must
      carry `x-amz-content-sha256` (the body's SHA-256). CloudFront doesn't compute it,
      so every iOS write would need client-side hashing, and Apple's server
      notifications (the StoreKit spec) could never be accepted.
    - So use OAC only with Lambda@Edge adding the hash. Otherwise run the Function URL
      without OAC, plus a secret origin header CloudFront injects and the app (or LWA
      config) checks.
  - (b) API Gateway REST API with WAF attached directly (~$3.50 per million requests; no
    always-free tier).
  - (c) HTTP API, or a bare Function URL, with no WAF for the lean launch, as a recorded
    accepted risk. API Gateway's HTTP API has no always-free tier either (its free
    allowance was a 12-month legacy offer).

  Standalone WAF is ~$5/mo per web ACL + $1 per rule + request fees. **Bot Control is a
  separately priced managed group** (subscription + per-request), so the lean budget
  keeps the common + IP-reputation rules only, unless the owner opts in.
- **Client IP for the Tier-1 rate limiter.** The greenfield ALB-CIDR
  `ProxyHeadersMiddleware` plan is replaced. The mechanism depends on the runner:
  - **Mangum:** the ASGI `client` comes from the event's `requestContext` source IP, with
    no header trust. With CloudFront in front, that source is CloudFront's IP, so the
    viewer IP must come from `CloudFront-Viewer-Address`, trusted only via the origin
    secret.
  - **LWA:** uvicorn sees a connection from 127.0.0.1. The pinned uvicorn (0.50.0)
    defaults to `proxy_headers=True` with `forwarded_allow_ips=127.0.0.1`, so
    `request.client.host` **silently becomes the `X-Forwarded-For` value** the front
    door passes through.
    - Whether that value is the true client or a spoofable, client-supplied entry
      depends on the front door. Unverified for a bare Function URL, which is reported
      to pass client XFF through.
    - Reading LWA's `x-amzn-request-context` header in `src/orbit/` would be
      Lambda-specific code, which is not allowed.
  - Either way, pin it as **config** (`FORWARDED_ALLOW_IPS` and the front door's XFF
    semantics). Acceptance test per front door: a spoofed `X-Forwarded-For` does not
    change the rate-limit bucket, and two real clients don't share one.
- **Networking: the NAT is on the per-request hot path.** The function runs in the VPC's
  private subnets, because RDS and Redis are private. Egress carries:
  - Firebase's token-key fetch, plus a Firebase round trip on **every authenticated
    request** (`check_revoked=True`, `src/orbit/auth/firebase.py`)
  - Secrets Manager/SSM
  - Sentry
  - a hosted Redis over TLS
  - Apple OCSP, if the billing verifier's online checks are on

  A NAT gateway (~$33/mo) would be the biggest line in the lean budget, so a NAT
  instance is favored. But a single NAT instance is then a single point of failure for
  every authenticated request, and it adds latency to the p95. Decide consciously:
  a NAT instance with auto-recovery (an auto-scaling group of 1) or an accepted outage
  risk. Consider interface VPC endpoints for Secrets Manager/SSM, priced against the
  saving.
- **Postgres connections and the concurrency quota.**
  - Every concurrent function instance opens its own pool. Configure through
    `Settings`: `pool_size=1, max_overflow=0` (SQLAlchemy's default overflow of 10 would
    defeat the cap), or `NullPool`.
  - Bound total instances with a **reserved-concurrency cap**, instead of RDS Proxy
    (~$22/mo+). Revisit RDS Proxy only when concurrency needs it.
  - **New accounts often get a concurrency quota of 10**, and reserved concurrency
    requires ≥ 100 unreserved. On a fresh account no cap can be set until a quota
    increase (≥ ~110) is granted. E1's bootstrap requests it; unverified whether
    free-plan accounts can get one.
  - Until then, the connection bound is the quota itself × the pool size, checked
    against RDS `max_connections`.
- **Redis.** The rate limiter still needs a shared store: ElastiCache in the VPC, or E1's
  lean hosted free-tier Redis over TLS. Unchanged in principle.
- **Migrations: a separate migration function.** CI cannot reach the private DB, and a
  Lambda container must speak the Lambda Runtime API. A command override of
  `alembic upgrade head` just exits (`Runtime.ExitError`), and under LWA the readiness
  check never passes. So:
  - A **dedicated migration function** from the same image uses a tiny handler
    (`awslambdaric` + a module that runs Alembic), kept **outside `src/orbit/`**.
  - `ImageConfig` command overrides are per-function, not per-invocation.
  - It gets its **own role** with DDL-capable DB credentials and no app secrets.
  - The deploy role gets `lambda:InvokeFunction` on it only.
  - CI invokes it before shifting traffic. This replaces `deploy.yml`'s "ECS run-task
    form" residual.
- **Canary + rollback.**
  - Lambda **versions + a weighted alias**, shifted by CodeDeploy's Lambda canary config
    (e.g. 10% for N minutes) with CloudWatch-alarm auto-rollback. That replaces ALB
    target-group weights.
  - Terraform must `ignore_changes` on the alias's version/routing config, or every
    apply fights CodeDeploy.
  - At 1–3 users a 10% slice sees roughly no traffic, so the burn-rate alarm can't
    fire. The rollback proof (E1) uses injected synthetic traffic.
- **Runtime identity.** `infra/main.tf`'s `app_task` role now trusts
  `lambda.amazonaws.com` (switched 2026-09-19). A2 adds the VPC execution permissions
  (ENI create/describe/delete, the `AWSLambdaVPCAccessExecutionRole` equivalent)
  least-privilege, on that same role. Log writes are already granted
  (`modules/observability`).
- **Observability.**
  - stdout structlog → CloudWatch Logs via the function's logging config, pointed at
    the existing app log group. The app also writes the audit group directly, which
    needs egress.
  - X-Ray active tracing.
  - The OTel/ADOT collector is baked into the image (layers don't apply to images).
  - Sentry's Lambda integration.
- **Payload, body cap and timeouts.**
  - Lambda's synchronous payload limit is 6 MB.
  - A Function URL has no configurable smaller body cap. So the greenfield plan to close
    the chunked-body gap at "the ingress/ALB body cap" (`src/orbit/edge/bodysize.py`) is
    re-decided against the chosen front door, and that stale comment updated.
  - Set the function timeout below the front door's timeout.
- **Stale ALB wording in code comments** (`src/orbit/edge/bodysize.py`,
  `src/orbit/logging/__init__.py`'s "deployed ALB/X-Ray header") gets corrected in this
  run, once the front door is chosen.

## Scope
- **The `infra/envs/` split**: `envs/staging` and `envs/prod` roots alongside A1's
  `envs/local`, all sharing the same modules. Staging mirrors prod's shape at a smaller
  size. Greenfield's root composition (`infra/main.tf` + its variables/outputs) moves
  into `envs/prod`, leaving `infra/` as `modules/` + `envs/` + `bootstrap/`.
- **Network completion**: public subnets, internet gateway, NAT, route tables. Today's
  VPC is private-subnet-only. The backend needs outbound internet on every authenticated
  request (Firebase revocation check, token keys), so some NAT is required and it is on
  the hot path. Choose NAT gateway vs NAT instance (with auto-recovery), informed by the
  cost estimate.
- **Compute**: the Lambda function (see the compute decision above): ECR repository,
  function, alias, reserved-concurrency cap, VPC config, timeout/memory, and the
  separate migration function with its own role. HTTPS comes from the chosen front door.
- **Edge**: the front door, plus WAF (managed common + IP-reputation rules; Bot Control
  only if the owner opts into its extra cost) where the chosen option supports it. The rate limiter's client-IP source gets pinned to that
  front door.
- **Observability Terraform**: SLO definitions, burn-rate alarms (the canary-rollback
  signal), SNS topics, synthetic canary definitions.
- **Deploy/CI identity — `infra/bootstrap/`**: the GitHub OIDC provider, the deploy and
  ops roles, and the S3 state bucket + DynamoDB lock table. This is the manual
  chicken-and-egg bootstrap E1 runs once. It is authored here and applied there.
- **IAM throughout**: least-privilege policies for every role, written in full. Nothing
  enforces them until E1, so they get written carefully here.
- **`deploy.yml` + `load-campaign.yml`, rewritten for Lambda.** Both are ECS-shaped
  today: ECS task-definition registration, ALB target-group weights, and an ECS
  stop-task failover drill. Rewrite them:
  - Deploy: publish a version → invoke the migration function → CodeDeploy alias
    canary with alarm rollback.
  - Failover drill: a Lambda equivalent, e.g. a throttle/reserved-concurrency-0 drill,
    or a bad version that trips the alarm.

  Map their placeholders to the Terraform outputs. The workflows stay inert
  (`DEPLOY_ENABLED` unset).
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
- `deploy.yml` / `load-campaign.yml` rewritten for Lambda; placeholder → output map
  documented.
- Cost estimate includes the Lambda lean topology (the go-live target) alongside the
  staging + prod parity topology.
- The E1 brief updated to "apply and operate what A2 authored".

## Size
Medium-large; almost entirely Terraform + docs; zero app code.
