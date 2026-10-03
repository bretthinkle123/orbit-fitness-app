# A1 — Local environment (Terraform on LocalStack + docker-compose + Simulator)

_Phase A (local foundation), run 1 of 2. Everything through Phase D develops and tests
against the stack this run builds. Consumed by requirements-elicitation + planning at run
start. Built from the local half of the original deploy-path brief — the live half stays
in [E1](E1-production-deploy-path.md)._

## Goal
One command brings up the whole app locally in an AWS-shaped way. The owner gets a first
real Terraform `init → plan → apply → destroy` loop to study, and every later run has a
repeatable local stack. Cost: $0.

## Where things stand (greenfield as built)
- Backend runs as a direct process (`uvicorn`), against a local Postgres/Redis via the
  `DATABASE_URL`/`REDIS_URL` settings overrides, the Firebase Auth emulator on port 9099,
  and the iOS Simulator.
- The secrets facade (`src/orbit/config/secrets.py`) calls Secrets Manager with no local
  endpoint; local runs sidestep it through the `*_password`/`*_web_api_key` overrides.
- `infra/` is authored but has never been applied anywhere (`offline_validate=true`).
- There is no Dockerfile and no compose file.

## Scope
- **Dockerfile** for the backend per delivery-conventions: pinned base-image digest,
  multi-stage, non-root, healthcheck, hadolint-clean. This is the same image E1 later
  deploys, so it is never a local-only variant. **The deploy target is AWS Lambda**
  (owner decision 2026-09-19; see [A2 § Compute decision](A2-production-terraform-authoring.md#compute-decision-owner-2026-09-19-aws-lambda-not-fargateapp-runner)).
  So the image must also run as a Lambda container image:
  - If A2's recommended runner is adopted, the AWS Lambda Web Adapter is copied in as an
    extension. It is inert outside Lambda, so compose still runs plain uvicorn.
  - Nothing Lambda-specific goes in `src/orbit/`.
  - Keep the import-time work small: it becomes Lambda cold-start latency.

  Optional stretch goal: invoke the image as a Lambda on LocalStack, to rehearse the
  deploy shape.
- **docker-compose** services:
  - `api`, built from the Dockerfile
  - `postgres` pinned to the RDS engine version in `infra/modules/data` (16.6)
  - `redis` pinned to the ElastiCache version (7.1). It stays because the rate limiter
    needs a shared store.
  - The Firebase Auth emulator
  - LocalStack, pinned
  - A one-off `migrate` service running `alembic upgrade head`. This rehearses the
    "migrations as a one-off run of the same image" shape. On Lambda this becomes a
    separate migration function with its own small handler (A2).
- **Pointing the AWS SDK at LocalStack is config-only.** boto3 (pinned 1.43.40) honors
  the `AWS_ENDPOINT_URL` environment variable natively, so no code branch is needed. No
  `if local:` anywhere in `src/orbit/`.
- **Terraform `infra/envs/local/`** — a root config that reuses the existing modules and
  applies them to LocalStack:
  - It applies only the modules whose services LocalStack's free tier supports: Secrets
    Manager, SSM, KMS, CloudWatch Logs, IAM, S3, SNS, DynamoDB.
  - RDS and ElastiCache are covered by the compose containers instead.
  - Modules are shared and never forked. If a module bundles a supported resource with
    an unsupported one, it is split, not copied.
  - Today's root composition (`infra/main.tf`, `environment` defaulting to `production`)
    stays where it is in this run. A2 moves it into `envs/prod`.
- **Local secrets**: seeded into LocalStack from a gitignored `.env.local`, with a
  committed `.env.local.example` template. The secrets facade then reads real values
  through its normal path.
- **iOS**: a Debug/Local build configuration (xcconfig) with the API base URL set to
  `http://localhost:8000`. The ATS exception is scoped to localhost in Debug only;
  Release keeps ATS on, so `store-compliance.sh` stays clean. The Simulator reaches the
  host's localhost directly.
- **Two commands**: `scripts/dev-up.sh` (compose up → `terraform apply` envs/local →
  migrate → seed → health check) and `scripts/dev-down.sh` (destroy + compose down).
  Demo data comes from a dev fixture script, never from migrations — new users start
  empty (CLAUDE.md).
- **IAM**: the app role's least-privilege policies are applied to LocalStack. They are
  not enforced there (see Live-only gaps), so Checkov is the local check.
- **Docs**: a new `docs/local-development.md` written as a learning document. It covers
  what each local piece stands in for, how Terraform state works here, and the
  live-only gaps below.

## Decisions for run start
- **Lambda runner, now or in A2.** A1 builds the Dockerfile, but A2 picks the runner
  (Lambda Web Adapter vs Mangum). So decide: does A1 add the LWA extension now on A2's
  recommendation, or ship a plain uvicorn image and let A2/E1 add the Lambda pieces?
  Adding it now keeps one image; deferring avoids building on a choice A2 could change.
- **Which machine runs this run, and what that costs.** This is the most
  machine-specific run in the roadmap: the operator has a WSL/Linux box (no Xcode) and
  an M2 Mac (Xcode, Colima, brew Postgres/Redis — see docs/mac-session-handoff.md). If
  it runs on WSL, three things must be handled in-run, not discovered on the Mac:
  - **Pin a multi-arch manifest digest**, not a per-architecture one. A digest pinned
    from an amd64 host will not run on the Mac's arm64, and delivery-conventions'
    digest-pin rule doesn't by itself prevent that.
  - **Port conflicts on the Mac.** It already runs brew `postgresql@16` and `redis` on
    5432/6379, which compose would collide with. Either map different host ports, or
    have `dev-up.sh` detect the conflict and say so.
  - **The iOS acceptance items cannot be proven on WSL** (Xcode build, Simulator
    done-flow, xcconfig base URL, XCUITest). They are recorded as owed to a Mac
    verification session, never checked off from Linux (standing rule 5's honesty rule
    applied to the Simulator).
- **LocalStack terms:** confirm at run start what LocalStack's free offering currently
  includes and requires. Its licensing and free-tier contents have been changing. If the
  free tier no longer fits, the fallback is **moto server** (Apache-2.0; covers S3, KMS,
  Secrets Manager, SSM, IAM, CloudWatch Logs, SNS).
- **Local Terraform state:** plain local backend, or S3 + DynamoDB running on LocalStack?
  The latter rehearses the real remote-state pattern, so it is the better lesson.
- **CI:** does CI get a LocalStack service container, or do tests stay independent of
  compose (the current testcontainers path)?

## Live-only gaps (recorded here, proven in E1/E2, never faked locally)
- IAM enforcement — LocalStack accepts calls a real policy would deny
- VPC routing, security groups, NAT
- RDS and ElastiCache behavior
- Lambda cold starts, concurrency limits and VPC networking; the front door + WAF
- Real alarm → SNS delivery
- Quotas and eventual consistency

## Security / compliance notes
- No new app input surface.
- `.env.local` is gitignored and gitleaks-scanned.
- Local data is synthetic and disposable. It is never migrated to a live environment:
  LocalStack KMS keys don't exist in real AWS, so ciphertext from B2 couldn't be
  decrypted there anyway.
- Checkov/Trivy on `envs/local`; hadolint on the Dockerfile.

## Acceptance sketch
- Fresh clone + `.env.local` → `dev-up.sh` → `/health` 200.
- The CLAUDE.md done-flow (register → log food → toggle sets → weight → theme switch →
  delete account) works from the Simulator against the containerized API.
- `terraform apply` on envs/local is clean; a second `plan` shows no changes; `destroy`
  is clean.
- The secrets facade reads from LocalStack (test).
- No environment-conditional branches in `src/orbit/` (grep check).
- Checkov, hadolint and Trivy clean; smoke check still passes at `:8000/health`.

## Size
Medium. Compose + Dockerfile + one Terraform root + two scripts + docs; minimal app code.
