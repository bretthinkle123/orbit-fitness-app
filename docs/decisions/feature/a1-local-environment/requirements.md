# Requirements — A1 Local environment

_Elicited 2026-10-19 with the owner, on the M2 Mac, pre-flight READY (22/0/0). Brief:
`plans/A1-local-environment.md`. Sharpens that brief; where the two disagree, this file
is the later word, but the brief remains the scope source._

**Logged deviation (M4″-A2 session isolation).** `requirements-elicitation` instructs the
operator to kick off the pipeline in a FRESH session, because the interview context should
not precede orchestration in the same window. The owner chose to start in-session, and
also asked that this chat's own context be carried in alongside the brief. Recorded here
for the auditor rather than quietly ignored. The material carry-over is factual machine
state, listed under Resolved, all of it independently verified this session rather than
recalled.

## Resolved

- **Which machine runs A1** → the M2 Mac. Verified READY (22 passed / 0 warnings / 0
  failures). The brief's WSL contingency therefore does NOT apply: no multi-arch digest
  hazard from an amd64 host, and the iOS acceptance items are provable in-run rather than
  owed to a later session.
- **Lambda runner, now or in A2** → **plain uvicorn now; A2 adds the runner.** A1 ships a
  clean multi-stage image that compose runs directly; A2 decides Lambda Web Adapter vs
  Mangum and adds it. Avoids building on a choice A2 could reverse. Accepted cost: E1
  touches the Dockerfile again, and the image A1 proves is not byte-identical to the one
  that eventually deploys.
- **Local AWS emulator** → **moto server, the brief's own fallback — not LocalStack.**
  LocalStack ended Community-edition support on 2026-03-23 (no further updates or security
  patches), its unified image now requires a `LOCALSTACK_AUTH_TOKEN` merely to start, and
  the remaining free plans (Hobby/Student/OSS-non-profit) are **non-commercial only**.
  Orbit is commercial: `pyproject.toml` declares `license = "Proprietary"`, there is a
  StoreKit monetization spec, and App Store submission is on the roadmap. Commercial use
  is ~$23–39/month, which breaks the brief's "Cost: $0" premise. Verified rather than
  assumed: **moto 5.1.22 supports all eight services A1 needs** — Secrets Manager, SSM,
  KMS, CloudWatch Logs, IAM, S3, SNS, DynamoDB — under Apache-2.0, with no account or
  token. Sources: blog.localstack.cloud/2026-upcoming-pricing-changes,
  github.com/getmoto/moto/blob/master/LICENSE.
  **Planning must treat Terraform-against-moto as the run's primary technical risk** and
  prove it EARLY: moto has no `tflocal` equivalent, so every AWS provider block needs
  explicit per-service endpoint overrides. This is the least-travelled part of the choice.
- **Host port conflicts** → **shift the host mappings; never the container ports.**
  Postgres publishes on **5433**, Redis on **6380**; inside the compose network the api
  still reaches them as `postgres:5432` / `redis:6379` by service name. Confirmed live,
  not hypothetical: brew `postgresql@16` (pid 1613) and `redis` (pid 1604) are bound to
  5432/6379 right now. Both stacks therefore run simultaneously and the host can still
  `psql`/`redis-cli` into the containers, which matters for a run whose purpose is
  learning. Docs must state which port is host and which is container.
- **Firebase Auth emulator port** → **9099 inside compose, 9100 on the host.** The
  integration suite's session-scoped `firebase_emulator` fixture (`tests/conftest.py`)
  **spawns its own** emulator on 9099, and CLAUDE.md warns that anything squatting there
  fails the suite with 401s — compose's emulator would be that squatter. Shifting the host
  mapping leaves 9099 entirely to the suite, so the 106 passing tests and their fixture are
  untouched and both stacks coexist. Accepted cost: two emulators means **two user stores**
  — a user registered from the Simulator is not visible to the test suite — and
  `docs/local-development.md` must say so plainly.
  (Note: the pipe deadlock recorded in `docs/mac-session-handoff.md` is already FIXED —
  conftest now writes emulator output to a temp file, so a taken port fails cleanly
  instead of hanging. The handoff note is stale on that point.)
- **Terraform state for `envs/local`** → **staged.** Get `init → plan → apply → destroy`
  working against moto with a plain local state file FIRST, then move state to S3 +
  DynamoDB on moto as a discrete, revertible step. Keeps the better lesson (the real
  remote-state pattern) as the target while making it a bonus rather than a blocker —
  deliberate, because moto's Terraform path is unproven. If the backend step fails, A1
  still ships a working stack and the gap is recorded as owed to A2.
- **CI** → **keep the existing testcontainers path; add ONE new job for the new surface.**
  The seven current jobs stay exactly as they are; the 106 integration tests keep spinning
  their own hermetic Postgres/Redis and stay independent of compose. The new job covers
  only what A1 adds: `terraform validate`/`plan` against moto, hadolint on the Dockerfile,
  Trivy on the image, Checkov on `envs/local`. Rationale: the merge gate is green today and
  rewiring 106 passing tests onto a shared service container is regression risk for no
  behavioural gain — the AWS surface those tests touch is nearly nil.
- **`dev-up.sh` on partial failure** → **idempotent and re-runnable; it converges.** Every
  step must be safe to repeat: `compose up` is already declarative, `terraform apply`
  converges by nature, `alembic upgrade head` is a no-op when current, and the seed script
  must check before inserting. A failed run leaves a diagnosable half-up stack that a
  re-run completes. Chosen because OOM mid-bring-up is a realistic outcome at this memory
  budget, and the alternative costs a full teardown per transient failure. Accepted cost:
  the seed fixture must be written idempotent rather than as a blind insert.
- **`dev-down.sh` data semantics** → **preserve volumes by default; `--clean` wipes.**
  Destroying data is the surprising default, so it is opt-in. Keeps the inner loop fast by
  skipping re-migrate/re-seed, and pairs naturally with an idempotent `dev-up`. Required
  mitigation: a stale volume can collide with a changed migration during A-phase, so
  `docs/local-development.md` must present `--clean` as **the first thing to try when
  alembic misbehaves**.
- **`dev-up.sh` runtime** → **measured and recorded, NOT a pass/fail budget.** The script
  times itself and the figure lands in `docs/local-development.md` so the next machine
  knows what normal looks like. Deliberately no threshold: nobody yet knows what five
  containers plus a JVM cost in a 3GB VM on an 8GB host, and an invented number becomes
  either a false-failing gate or a meaningless loose one. Planning must therefore NOT emit
  a `perf.budget.*` for this, since a declared budget with no measured value blocks the
  deploy gate.

### Confirmed assumptions (owner said yes)

- iOS acceptance is **proven in-run, not owed** — the done-flow (register → log food →
  toggle sets → weight → theme switch → delete account) from the Simulator against the
  containerized API gates A1. Largest single work item in the run.
- brew `postgresql@16` and `redis` **keep running** and are not replaced; the port shift
  exists precisely so the native and containerized stacks coexist.
- `infra/envs/local/` **keeps its name** despite the emulator being moto — "local"
  describes the environment, not the tool. Today's root composition (`infra/main.tf`,
  `environment` defaulting to `production`) stays put; A2 moves it to `envs/prod`.
- Colima stays at **4 CPU / 3GB / 20GB** (resized this session from 2/2/20 on an 8GB host;
  6GB was considered and rejected as actively harmful at that RAM). A1 **records the
  observed resource cost** rather than prescribing an unmeasured minimum.

## Open

_All four items opened at elicitation were closed the same day — three by direct
investigation, one by owner decision. Kept here with their resolutions so planning sees
the evidence rather than re-opening the questions._

- **RESOLVED — Terraform drives moto cleanly, with one required local-only setting.**
  Spiked for real against `moto_server` 5.1.22 + Terraform 1.15.9 + AWS provider ~>6.0,
  using a config mirroring `infra/modules/secrets`' exact resource mix (`aws_kms_key`,
  `aws_kms_alias`, `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version`,
  `aws_ssm_parameter`). Results:
  - `apply` → 5 resources created, clean.
  - Second `plan` → **"No changes. Your infrastructure matches the configuration."**
    (`-detailed-exitcode` 0). The acceptance criterion holds; moto reconciles well enough
    for these resource types.
  - `destroy` → clean, 5 destroyed.
  - **But re-`apply` after `destroy` FAILED**: `ResourceExistsException: the secret
    orbit/spike/db already exists`. moto faithfully emulates AWS's Secrets Manager
    *recovery window* — Terraform reports a successful destroy while the secret is only
    SCHEDULED for deletion and still occupies its name.
  - **Fix, verified:** `recovery_window_in_days = 0` on `aws_secretsmanager_secret`. Full
    cycle then passes repeatedly: apply → destroy → apply → plan(no changes) → destroy.
  - **Planning consequence:** this is a *local-only* value — prod must keep a real
    recovery window. Per the brief's no-fork rule it becomes a **module variable** on
    `infra/modules/secrets` (default: the AWS default; `envs/local` passes 0), never a
    forked copy. Without it, `dev-down.sh` followed by `dev-up.sh` breaks on the second
    bring-up — which directly undercuts the "idempotent and re-runnable" decision above,
    so treat it as required, not optional.
  - Every provider block needs all eight endpoints set explicitly (no `tflocal`); the
    spike's working provider config is reproduced in the run notes.
- **RESOLVED — module split list, by inspection of `infra/modules/*`:**
  - `secrets` (secretsmanager, ssm, kms, iam) → **fully moto-supported, apply as-is.**
    Smallest and the right first target.
  - `observability` (cloudwatch logs + log resource policy, kms, iam) → **fully
    moto-supported, apply as-is.**
  - `data` → **MIXED, must be split**: `aws_iam_role`, `aws_iam_role_policy_attachment`,
    `aws_kms_key`, `aws_kms_alias` are supported, while `aws_db_instance`,
    `aws_db_parameter_group`, `aws_db_subnet_group`,
    `aws_elasticache_replication_group`, `aws_elasticache_subnet_group` are RDS/ElastiCache
    — which the brief deliberately covers with compose containers instead. Split, never
    fork.
  - `network` (vpc, subnet, security groups, flow log) → **excluded from `envs/local`
    entirely**, not split: VPC routing, security groups and NAT are named live-only gaps.
    Its `aws_cloudwatch_log_group` + IAM are duplicated by `observability` anyway.
- **RESOLVED — seed fixtures are three separate concerns, not one.**
  - `scripts/seed_dast_user.py`'s **idempotency shape is directly reusable** for the dev
    user: attempt create, and on `EMAIL_EXISTS` sign in instead (its `_EMAIL_ALREADY_EXISTS`
    path). That matches the idempotent-`dev-up` decision exactly.
  - But it seeds a **Firebase auth user**, not domain rows — a different problem.
  - Global reference data (quick-food catalog, Push Day program, muscle base levels) is
    ALREADY seeded by `migrations/versions/0002_seed_catalog_program_levels.py`, correctly,
    because it is reference data rather than per-user demo content.
  - So the dev demo-data fixture is a **third, separate, dev-only script** that must stay
    out of migrations — CLAUDE.md's "new users start empty" holds, and 0002 does not
    violate it.
- **RESOLVED (owner decision) — build the Firebase emulator image in-repo.** No official
  first-party image exists; every candidate is community-maintained and unendorsed (most
  current: `thoughtgears/docker-firebase-emulator`, firebase-tools 15.30.1, 2026-09-15).
  Decision: a small in-repo Dockerfile on a **pinned base digest** that installs a **pinned
  firebase-tools** and runs `firebase emulators:start --only auth`. Depends only on
  firebase-tools, which this project already trusts and runs natively, rather than on a
  third-party image layer in the one stack every future run depends on. Fits
  delivery-conventions (own digest, own provenance-ledger entry) and the repo's
  anti-slopsquatting posture. Planning must choose the JDK explicitly — the emulator needs
  Java and this is the VM's largest memory line — and record the observed footprint.

## Out of scope

- **Invoking the image as a Lambda on the emulator** (the brief's optional stretch goal) —
  dead as a consequence of the moto decision: running real container images as Lambdas is
  a LocalStack paid feature and moto's Lambda backend does not provide it. Revisit in A2/E1
  against real AWS, not locally.
- **Anything Lambda-specific in `src/orbit/`** — brief's standing rule; the runner is A2's
  call and must stay out of the app package.
- **Picking the Lambda runner** (LWA vs Mangum) — A2 owns it.
- **Moving `infra/main.tf` into `envs/prod`** — A2 owns it.
- **Live-only gaps, never faked locally**: IAM enforcement (moto accepts calls a real
  policy would deny), VPC routing / security groups / NAT, real RDS and ElastiCache
  behaviour, Lambda cold starts / concurrency / VPC networking, the front door + WAF, real
  alarm → SNS delivery, quotas and eventual consistency. Recorded here, proven in E1/E2.
- **Paying for a LocalStack licence** — rejected this run; it breaks the $0 premise and
  makes the local stack depend on a vendor account whose terms have already changed once.
- **A pass/fail `dev-up.sh` time budget** — explicitly declined; measure and record only.
- **Rewiring the 106 integration tests onto compose** — declined for both CI and local;
  they stay hermetic via testcontainers.
- **New application input surface** — A1 adds none (brief's security note).
