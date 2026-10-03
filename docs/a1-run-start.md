# A1 run-start checklist (read before starting the A1 run)

_Written 2026-10-03 on the WSL box, for a fresh Claude Code session on the operator's M2
Mac with no other context. Scope: getting the **A1** run started on the right machine with
the right environment and decisions. Retire this file at A1 closeout — it is a launch
checklist, not a living reference._

Everything here is derived from committed docs, cited inline. Where this file and a cited
doc disagree, **the cited doc wins**: it is maintained, this one is not.

## What the run is

**A1 — Local environment**, the first run of the post-greenfield roadmap. Brief:
[`plans/A1-local-environment.md`](../plans/A1-local-environment.md). Run order and the
standing rules every run must honor: [`docs/roadmap.md`](roadmap.md).

It builds the Dockerfile, docker-compose (Postgres, Redis, Firebase Auth emulator,
LocalStack), Terraform `envs/local` applied to LocalStack, the Simulator build config,
`dev-up.sh` / `dev-down.sh`, and `docs/local-development.md`. No AWS account is involved
and nothing costs money.

## Why the Mac

A1's acceptance includes the CLAUDE.md done-flow (register → log food → toggle sets →
weight → theme switch → delete account) **from the iOS Simulator**, against the
containerized API. The WSL box has no Xcode, so it cannot prove that half. The Mac proves
both halves in one place.

`.pipeline/` is gitignored and machine-local, so a run cannot be started on one machine
and finished on another. This run starts and ends on the Mac.

## Before starting the run

1. `cd ~/repos/orbit-fitness-app && git checkout main && git pull`
   - Three PRs merged on 2026-10-03: the AWS Lambda compute decision + the StoreKit spec
     (#6), CVE bumps for pyjwt/urllib3 plus a rate-limit test de-flake (#7), and this
     checklist. The A1 brief changed in #6, so confirm the pull landed before reading it.
2. `gh auth status` — the deployment stage needs it
   ([`docs/mac-session-handoff.md`](mac-session-handoff.md)).
3. Start the stack: `brew services start postgresql@16 redis`, plus Colima for Docker
   (`colima start`). The full restart recipe is in `docs/mac-session-handoff.md`.
4. **Check `.pipeline/waivers.json` exists.** It is gitignored and machine-local, so a
   fresh clone has none. If it is missing, re-record the two greenfield waivers with
   `record-waiver.sh`, or the security stage will re-flag them as new findings:
   - ASVS `6.3.3` — "MFA out of scope for greenfield run"
   - ASVS `6.2.x` — "Firebase delegated, with the enable-at-deploy follow-up"
5. **Put the venv's `bin` on `PATH`** (or activate it). The Postgres fixture shells out to
   `alembic` by name; without it, every DB-backed integration module errors at setup with
   `FileNotFoundError: 'alembic'`. This cost time on the WSL box on 2026-10-03.
6. **Confirm `.pipeline/` has no in-flight run marker.** On WSL an aborted A1 attempt from
   2026-09-06 left `state.json` + `run-started` behind; they were archived to
   `.pipeline/archive/aborted-a1-20260906/`. Handle any Mac leftovers the same way —
   move, don't delete.

## Decisions the run will ask about

[`plans/A1-local-environment.md`](../plans/A1-local-environment.md) § "Decisions for run
start" carries these in full. In short:

1. **Lambda runner: now, or in A2?** The deploy target is AWS Lambda as of 2026-09-19
   ([`plans/A2-production-terraform-authoring.md`](../plans/A2-production-terraform-authoring.md)
   § Compute decision). A1 builds the Dockerfile but A2 picks the runner (Lambda Web
   Adapter vs Mangum). So either A1 adds the adapter now on A2's recommendation, or it
   ships a plain uvicorn image and A2/E1 add the Lambda pieces. Either way, nothing
   Lambda-specific goes in `src/orbit/` (CLAUDE.md).
2. **Multi-arch digest.** Pin a multi-arch manifest digest for the base image, not a
   per-architecture one: the Mac is arm64 and the WSL box is amd64, and a per-arch digest
   pinned on one will not run on the other.
3. **Port conflicts.** The Mac already runs brew `postgresql@16` on 5432 and `redis` on
   6379, which compose will collide with unless host ports are remapped or `dev-up.sh`
   detects it and says so.
4. **LocalStack terms** — confirm what its free offering currently includes and requires.
   The fallback is moto server.
5. **Local Terraform state** — plain local backend, or S3 + DynamoDB on LocalStack (the
   better lesson).
6. **CI** — does CI get a LocalStack service container, or do tests stay on the current
   testcontainers path?

## Context that changed since the Mac last saw this repo

- **Compute target is AWS Lambda**, not ECS Fargate or App Runner. Decided 2026-09-19 on
  cost at the expected launch scale (1–3 users). The rationale and the open sub-decisions
  (front door, WAF placement, client-IP source, NAT on the per-request hot path, DB
  connections, the separate migration function, the CodeDeploy alias canary) are in A2's
  § Compute decision. A1 only needs to know the Dockerfile must also be Lambda-runnable.
- **The AWS account is created at the start of E1**, not before, so the free plan's
  credits aren't spent during local development
  ([`plans/E1-production-deploy-path.md`](../plans/E1-production-deploy-path.md) § cost
  model). Everything through Phase D is $0 and local.
- **StoreKit monetization is specced but NOT scheduled**
  ([`docs/specs/storekit-monetization.md`](specs/storekit-monetization.md)). Do not pull it
  into any run; it is gated on the owner's freemium decision at the roadmap's go-live gate.
- `deploy.yml` and `load-campaign.yml` are still ECS-shaped and carry header notes saying
  A2 rewrites them. Both stay inert (`DEPLOY_ENABLED` unset). Not A1's job.
- The iOS app, its test suites and the pipeline engine were all green on this Mac as of
  PR #3: 142 backend tests, 157 Swift unit tests, 12 XCUITests, and 259 engine eval checks
  across 18 suites (`docs/mac-session-handoff.md`).

## Honesty rules that apply to this run

- **Standing rule 5** ([`docs/roadmap.md`](roadmap.md)): an acceptance item only real AWS
  or a physical device can prove is **never faked locally** — it is recorded as owed to the
  named Phase E run. A1's live-only gap list already names Lambda cold
  starts/concurrency/VPC networking, the front door + WAF, IAM enforcement, RDS and
  ElastiCache behavior, real alarm delivery, and quotas.
- Native iOS is **reduced assurance** for the deterministic gates (CLAUDE.md). Never
  describe the Swift side as gate-verified.
