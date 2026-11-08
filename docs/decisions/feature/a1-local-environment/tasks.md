---
feature: a1-local-environment
task_count: 11
revision: 2   # rev 1 = plan-audit fixes (guard probes, single compose env mechanism, T6<-T3, .trivyignore, AC22 in T7); rev 2 = owner checkpoint (postgres newest 16.x, use_lockfile + lock probe, S2 wording, A2 owed rows)
ordering_rationale: >
  Terraform-against-moto is the run's primary technical risk (requirements.md), so T1-T3 prove it
  first, before any image, script or iOS work depends on it. T1 includes the account-guard probes;
  T3 includes the S3-native lock probe. The images (T4, T5) come next. They are independent of
  T1-T3 and of each other, so they are parallel-safe on a resume. T6/T7 assemble the stack and the
  one-command scripts. T8 adds CI. T9/T10 are the iOS phase; T10 is its own phase, with compose up
  and the test suite idle (operator kickoff). T11 is docs, the A2 owed rows, and the final
  regression.
---

# Tasks — A1 Local environment

Each task is one segment. Implementation runs **once**, task by task, with a checkpoint at every
task boundary. Plan references (`plan.md §…`) give the what, why and how. This file gives order,
scope and the done-gate.

**Compose invocation rule (plan.md §Compose invocation rule).** Every compose command in this
file is run from the repo root as `docker compose --env-file .env.local …`. Inside the scripts
that is the `dc()` function. There are no exceptions; a bare `docker compose` fails by design
because of the `${POSTGRES_*:?}` interpolation.

## Standard end-of-task gate

Every task ends **suite-green and app-bootable**:

1. **Memory hygiene first (operator kickoff):**
   - Run `xcrun simctl shutdown all`, except during T9/T10.
   - The compose stack must be **down** (`scripts/dev-down.sh` once it exists, else
     `docker compose --env-file .env.local down`) before pytest runs.
2. **Suite:** `source .venv/bin/activate && pytest --cov=src --cov-fail-under=80` → green.
3. **App-bootable:**
   - `bash ~/.claude/hooks/smoke-check.sh` → `PASS — http://localhost:8000/health responded 200`.
   - From T7 onward, also `scripts/dev-up.sh` → `step=health status=ok`, followed by
     `scripts/dev-down.sh`.
4. **If the task touched `infra/` root or modules:** `bash ~/.claude/hooks/infra-validate.sh`
   exits 0. The offline root plan still works.

**If compose thrashes or a container is OOM-killed:**
- Do **not** raise Colima memory.
- Measure with `docker stats` and `docker inspect --format '{{.State.OOMKilled}}'`.
- Look at the emulator and moto lines first.
- Reduce concurrency.

**Before T1 has `.env.local`:** T1–T2 use only the moto service. Before running any compose
command in T1, create `.env.local` from `.env.local.example` (sentinels replaced). If T3 has not
yet created the example, create a minimal local `.env.local` with the three `POSTGRES_*` keys.
This is required because the `:?` interpolation applies to the whole file once postgres is
defined (T6). In T1–T2, where the compose file holds moto only, it is harmless.

## Task table

| ID | depends_on | ACs advanced | test_strategy slice | expected files |
|---|---|---|---|---|
| T1 | — | AC5, AC6, AC7, AC8, AC23 | Terraform cycle evidence (local backend); account-guard probes 1 and 2 + regex probe; `infra-validate.sh`; full pytest (regression) | `docker-compose.yml` (moto service only), `.gitignore`, `infra/modules/secrets/{main,variables}.tf`, `infra/modules/app_identity/{main,variables,outputs}.tf`, `infra/main.tf`, `infra/outputs.tf`, `infra/envs/local/{versions,providers,main,variables,outputs}.tf`, `infra/envs/local/.terraform.lock.hcl` |
| T2 | T1 | AC5, AC7, AC8, AC15 | Terraform cycle evidence (all four modules); Checkov `infra/` + `envs/local`; `infra-validate.sh` | `infra/modules/data_keys/{main,variables,outputs}.tf`, `infra/modules/data/{main,variables,outputs}.tf` (`engine_version` untouched), `infra/main.tf`, `infra/envs/local/{main,outputs}.tf`, `docker-compose.yml` (moto env) |
| T3 | T2 | AC9, AC21, AC23 | `tests/unit/test_dev_scripts.py` (validate-env, endpoint guard, subcommand allowlist, **no DynamoDB client**); **`test_backend_uses_lockfile`**; Terraform cycle + guard probes under remote state; **concurrent-plan lock probe** | `scripts/dev/__init__.py`, `scripts/dev/local_aws.py`, `infra/envs/local/{backend.tf,backend.moto.hcl}`, `.env.local.example`, `tests/unit/test_dev_scripts.py`, `tests/unit/test_local_stack_config.py` |
| T4 | — (parallel-safe with T1–T3, T5) | AC13, AC14, AC16, AC18, AC22, AC25 | `tests/unit/test_local_stack_config.py` (Dockerfile + dockerignore cases); hadolint; Trivy image; standalone `/health` | `Dockerfile`, `.dockerignore`, `.trivyignore` (**conditional**: only for a no-fix finding), `.github/workflows/build-provenance.yml`, `tests/unit/test_local_stack_config.py` |
| T5 | — (parallel-safe with T1–T4) | AC18, AC19 | `test_local_stack_config.py` (emulator digest + firebase-tools parity); container healthy; JDK evidence | `docker/firebase-emulator/{Dockerfile,firebase.json,entrypoint.sh}`, `tests/unit/test_local_stack_config.py` |
| T6 | T2, T3, T4, T5 | AC2, AC10, AC11, AC12, AC17, AC18, AC21, AC22, AC23 | `tests/integration/test_secrets_facade_moto.py`; `tests/unit/test_no_env_branches.py`; `test_compose_env_file_single_mechanism`; **`test_postgres_major_matches_rds_engine_major`**; compose-level evidence (no `DATABASE_URL`, loopback `lsof`, tfstate grep, `docker compose config` without env file fails) | `docker-compose.yml` (all services, postgres newest 16.x, `${VAR:?}`), `scripts/dev/local_aws.py` (`seed-secrets`, `_redact_dsn`), `tests/integration/test_secrets_facade_moto.py`, `tests/unit/test_no_env_branches.py`, `tests/unit/test_local_stack_config.py`, `tests/unit/test_dev_scripts.py` |
| T7 | T3, T6 | AC1, AC2, AC3, AC4, AC20, AC21, AC22, AC29 | `test_dev_scripts.py` (seed validators); `test_compose_env_file_single_mechanism` (scripts half); system evidence: fresh clone, ×2 idempotency (postgres not recreated), interrupt + moto-restart convergence, down/up UID persistence, `--clean`, bad args, no secret in transcripts | `scripts/dev-up.sh`, `scripts/dev-down.sh`, `scripts/seed_dev_data.py`, `tests/unit/test_dev_scripts.py`, `tests/unit/test_local_stack_config.py` |
| T8 | T3, T4, T5 | AC5, AC8, AC14, AC15, AC24 | CI `local-stack` job (re-runs the guard probes, the Terraform cycle, hadolint, Trivy, Checkov); diff confirms the 7 existing jobs are unchanged | `.github/workflows/pipeline-ci.yml` |
| T9 | — (code-independent; **verify only after T7**) | AC26 | `xcodebuild build`; `-only-testing:OrbitTests`; `store-compliance.sh`; `-showBuildSettings` evidence | `ios/Orbit/Config/{Debug,Release}.xcconfig`, `ios/Orbit/project.yml`, `ios/Orbit/Resources/Info.plist`, `ios/Orbit/App/OrbitApp.swift` (doc comment), `ios/Orbit/Tests/UITests/AuthFlowUITests.swift` |
| T10 | T7, T9 | AC27, AC30 | E2E `SmokeUITests` against compose (no overrides) + API log evidence; smoke with stack up | evidence only (`.pipeline/a1-evidence/`); no source files unless a contingency fires (ATS → Debug-only plist key) |
| T11 | T7, T8, T10 | AC28, AC29, AC30, AC31, AC32 | Doc review checklist (AC28, incl. A2 owed rows A/B); final full regression (AC30); hand-off of mechanism list to security (AC32) | `docs/local-development.md`, `CLAUDE.md`, `README.md`, `infra/README.md`, `infra/envs/local/README.md`, `ios/Orbit/README.md`, `docs/system_architecture.md`, `docs/mac-session-handoff.md`, `docs/roadmap.md`, `scripts/README.md`, `tests/README.md`, `plans/A2-production-terraform-authoring.md`; delete `docs/a1-run-start.md` |

**Parallel-safe on a resume:**
- T4 and T5 have no dependencies and touch no files shared with T1–T3, apart from appending to
  `tests/unit/test_local_stack_config.py`. That file is created by whichever of T3/T4/T5 runs
  first and appended by the others.
- T9's code edits are independent, but its **verification** must wait for T7, because it needs the
  stack and memory sequencing.
- All other tasks are strictly sequential.

**AC coverage check:** the union of "ACs advanced" is AC1–AC32. Every criterion is built by at
least one task.

---

## T1 — Prove Terraform-against-moto on the secrets module (local backend) + account-guard probes

**Goal:** the run's primary risk, retired first. This covers the minimum to `apply → plan(no
changes) → destroy → apply → destroy` with `infra/envs/local` on the **exact** provider pin
(6.52.0) and a plain local state file. It also establishes, by probe, which layers of the "never
touch real AWS" guard actually hold.

1. **`docker-compose.yml` skeleton:**
   - Top-level `name: orbit-local` and the `moto` service only.
   - Image `motoserver/moto:5.1.22@sha256:<multi-arch index digest>`. Resolve it with
     `docker buildx imagetools inspect motoserver/moto:5.1.22` and take the **index** digest.
   - Port `"127.0.0.1:5001:5000"`.
   - Healthcheck on `/moto-api/`; fall back to a TCP probe if that path is absent, and record
     which.
   - Before mapping, confirm with `lsof -nP -iTCP:5000 -sTCP:LISTEN` that :5000 is held by
     AirPlay (assumption) and that :5001 is free.
2. **`infra/modules/secrets`:** add `recovery_window_in_days` (number, default 30, validation
   `0 || 7..30`) and set it on both `aws_secretsmanager_secret` resources.
3. **`infra/modules/app_identity`:**
   - Move `aws_iam_role.app_task` from `infra/main.tf` into the module as `aws_iam_role.this`.
   - Same name `${var.name_prefix}-task`, same Lambda trust policy, same tags.
   - Outputs `role_name`, `role_arn`.
   - Root: call the module, add a `moved {}` block, and repoint `module.secrets` /
     `module.observability` `app_task_role_name` and `outputs.tf` `app_task_role_arn`.
4. **`infra/envs/local`:**
   - `versions.tf`: `required_version = ">= 1.11.0, < 2.0.0"`, needed by T3's `use_lockfile`.
     Confirm with `terraform version` that the Mac is ≥1.11.
   - `providers.tf`:
     - dummy creds `test`/`test` (with the `CKV_AWS_41` inline skip reason);
     - 9 endpoints from `var.moto_endpoint`;
     - `allowed_account_ids = ["123456789012"]`;
     - `s3_use_path_style = true` and `skip_metadata_api_check = true`;
     - **`skip_credentials_validation` and `skip_requesting_account_id` NOT set**;
     - default tags.
   - `variables.tf` (`moto_endpoint` with validation).
   - `main.tf` with `app_identity` + `secrets` (`recovery_window_in_days = 0`).
   - `outputs.tf`.
5. **Lock file:** `terraform -chdir=infra/envs/local providers lock -platform=darwin_arm64 -platform=linux_amd64`.
6. **`.gitignore`:** add `.env.local`, `**/.terraform/`, `*.tfstate.*`, `.local/`, `*_override.tf`.
7. **Prove the cycle:**
   - Create `.env.local` (see the note above), then `docker compose --env-file .env.local up -d --wait moto`.
   - `terraform -chdir=infra/envs/local init && apply -auto-approve`.
   - `plan -detailed-exitcode` → 0.
   - `destroy -auto-approve`, `apply -auto-approve`, `destroy -auto-approve`.
   - Save transcripts to `.pipeline/a1-evidence/t1-*.txt`.
8. **Prove the guard (AC8)**, saving to `.pipeline/a1-evidence/t1-guard-*.txt`:
   - **Regex probe:** `terraform -chdir=infra/envs/local plan -var moto_endpoint=https://example.com`
     → must fail validation.
   - **Probe 1 (Layer B):**
     - Write `infra/envs/local/zz_probe_override.tf` containing
       `provider "aws" { allowed_account_ids = ["000000000000"] }`.
     - `plan` → must exit non-zero with the provider's account-not-allowed message.
     - Delete the file, and confirm `git status` does not show it (gitignored).
     - **If `plan` does not fail:** record that verbatim. Layer B is **unclaimed**; note it for
       T11's docs and security hand-off. Continue.
   - **Probe 2 (Layer A):**
     `AWS_ACCESS_KEY_ID=AKIAEXAMPLEPROBE0000 AWS_SECRET_ACCESS_KEY=probe/not/real AWS_PROFILE=nonexistent-probe terraform -chdir=infra/envs/local plan`
     → must **succeed** (only possible against moto).
   - **If unsetting `skip_credentials_validation` breaks `init`/`plan` against moto:**
     - restore `skip_credentials_validation = true`;
     - re-run probe 1 and record the result;
     - apply the same claim rule.
9. **Root:** `bash ~/.claude/hooks/infra-validate.sh` → 0. The root plan now shows
   `recovery_window_in_days = 30`; the role is moved, not destroyed and recreated.
10. **If the cycle fails on 6.52.0 where the spike passed on `~>6.0`:**
    - Record the exact error.
    - Do **not** fork a module.
    - Fixes must be variables, or provider configuration in `envs/local`.
    - Escalate per the debugging protocol if a module change other than a variable is needed.

**Done-gate:** standard (suite + native smoke + `infra-validate.sh`), then
`docker compose --env-file .env.local down`.

## T2 — Observability + data split into envs/local

1. **moto service:** add `MOTO_IAM_LOAD_MANAGED_POLICIES=true` (moto v5 does not load
   AWS-managed policies by default; `AWSXRayDaemonWriteAccess` would fail with `NoSuchEntity`).
2. **Prove the finding:** first apply observability **without** the variable and capture the
   `NoSuchEntity` error as evidence. Then apply with it. The learning doc cites this.
3. **`infra/modules/data_keys`:**
   - Move `aws_kms_key.rds|redis`, `aws_kms_alias.rds|redis` and the two key-policy `data`
     documents out of `modules/data`, with the `#checkov:skip` lines kept **inside** the data
     blocks.
   - Inputs `name_prefix`, `tags`, `aws_account_id`. Outputs `rds_kms_key_arn`,
     `redis_kms_key_arn`.
   - `modules/data`: new variables `rds_kms_key_arn`, `redis_kms_key_arn`, used at every former
     `aws_kms_key.rds|redis.arn` reference. Remove the `db_kms_key_arn` output (now on
     `data_keys`). **Do not touch `engine_version = "16.6"`** (owed to A2).
   - Root: add `module "data_keys"`, pass its ARNs into `module "data"`, and add `moved {}`
     blocks for keys and aliases.
4. **`envs/local/main.tf`:** add `module "observability"` (`ops_role_arn` =
   `arn:aws:iam::123456789012:role/orbit-local-ops`) and `module "data_keys"`. **Not** `data`,
   **not** `network`.
5. **Prove:**
   - The full T1 cycle again, and re-run probe 2 (cheap).
   - `checkov-scan.sh -d infra` and `-d infra/envs/local`. No new unwaived failures; new skips
     (e.g. `CKV_AWS_41` on the dummy provider creds) carry inline reasons.

**Done-gate:** standard plus `infra-validate.sh`.

## T3 — Staged remote state on moto with S3-native locking (bonus step, revertible)

1. **`scripts/dev/local_aws.py`** (argparse subcommands `validate-env`, `ensure-state-backend`;
   `seed-secrets` comes in T6):
   - `_require_loopback_endpoint()` runs **before** any boto3 client is built.
   - Strict `.env.local` parser with key allowlist and contracts (plan.md §Validation
     contracts).
   - `CHANGE_ME` refusal.
   - `ensure-state-backend`: idempotently create **only** bucket `orbit-local-tfstate`
     (versioning + SSE-S3).
   - **No DynamoDB table and no `dynamodb` client.** Nothing in A1 needs DynamoDB (owner
     decision, OQ11).
2. **`.env.local.example`:**
   - `POSTGRES_USER=orbit`, `POSTGRES_DB=orbit`, `POSTGRES_PASSWORD=CHANGE_ME`,
     `ORBIT_DEV_USER_EMAIL=dev@orbit-fitness.test`, `ORBIT_DEV_USER_PASSWORD=CHANGE_ME`.
   - Comment lines explain each key, the `openssl rand -hex 24` one-liner, and that compose
     reads this file only via `--env-file`.
3. **Backend files:**
   - `infra/envs/local/backend.tf`: `backend "s3" {}`.
   - `backend.moto.hcl`: bucket, key `envs/local/terraform.tfstate`, region,
     **`use_lockfile = true`**, `encrypt = true`, `endpoints = { s3 = "http://localhost:5001" }`,
     `use_path_style = true`, the skip flags and dummy keys. **No `dynamodb_table`.**
   - Then `terraform -chdir=infra/envs/local init -migrate-state -backend-config=backend.moto.hcl`.
4. **Prove the backend:**
   - The full cycle under remote state.
   - Probe 1 and probe 2 re-run under this backend.
   - `ensure-state-backend` run twice: the second run is a no-op.
   - The state object is visible in moto S3.
5. **Prove locking (AC9)**, saving to `.pipeline/a1-evidence/t3-lock-*.txt`:
   - **Holder:** start a lock-holding run in the background that waits at its approval prompt:
     `sleep 60 | terraform -chdir=infra/envs/local apply -input=true > t3-lock-holder.txt 2>&1 &`.
     `apply` takes the state lock before prompting, and the open-but-silent stdin keeps it waiting.
   - **While the holder waits (after ~5 s):**
     - list the bucket via boto3; `envs/local/terraform.tfstate.tflock` must be present;
     - run `terraform -chdir=infra/envs/local plan -lock-timeout=0s`; it must exit non-zero with
       "Error acquiring the state lock" and the holder's lock ID.
   - **After the holder exits** (stdin EOF → apply cancels), `plan` succeeds and the `.tflock`
     object is gone.
   - If the background-holder technique misbehaves on this Terraform version, an equivalent
     holder is acceptable (e.g. a second `apply` paused at its prompt in another terminal).
     Record which was used.
6. **Tests:**
   - `tests/unit/test_dev_scripts.py`: every contract row, the guard-before-client test
     (monkeypatch `boto3.client` to fail the test if it is called), the subcommand allowlist, the
     sentinel refusal, and **`test_ensure_state_backend_creates_no_dynamodb`** (a boto3 stub
     asserts no `dynamodb` client is requested).
   - `tests/unit/test_local_stack_config.py::test_backend_uses_lockfile`: `backend.moto.hcl`
     contains `use_lockfile = true` and no `dynamodb_table`.
7. **Fallback (AC9 option b):** if the S3 backend or its locking cannot be made reliable against
   moto:
   - Delete `backend.tf` and `backend.moto.hcl`, and mark `test_backend_uses_lockfile` skipped
     with the recorded reason.
   - Re-init with the local backend.
   - Record the failure for `docs/local-development.md` (T11) and flag A2 Inherited row 3 as
     owed (T11).
   - The run continues.

**Done-gate:** standard.

## T4 — API image (plain uvicorn), build context, inert provenance

1. **`Dockerfile`:** per plan.md §Backend.
   - Resolve the `python:3.12-slim-bookworm` **index** digest via `docker buildx imagetools inspect`.
     Choose the newest digest that is **≥14 days old**.
   - Builder: `poetry==2.4.1`, `poetry check --lock`, then `poetry install --only main`.
   - Runtime: uid 10001, stdlib healthcheck, `CMD uvicorn orbit.main:app --host 0.0.0.0 --port 8000`.
   - No secret, emulator or endpoint `ENV`/`ARG`.
2. **`.dockerignore`:** allowlist (line 1 `*`).
3. **`.github/workflows/build-provenance.yml`:** the gate step requires `-f Dockerfile` **and**
   `${{ vars.DEPLOY_ENABLED }}` = `true`; otherwise it echoes `inert until E1 (DEPLOY_ENABLED unset)`.
4. **`tests/unit/test_local_stack_config.py`** (create or append): Dockerfile digest pins,
   non-root `USER`, `HEALTHCHECK` present, `test_dockerfile_bakes_no_emulator_or_endpoint_env`,
   `test_dockerignore_is_allowlist`. Text and regex only; no YAML library.
5. **Prove:**
   - `docker build -t orbit-api:local .` with a **canary** `.env.local` + `.pipeline/` present,
     then `ls -a /app` in the image.
   - `id -u` → 10001; no `poetry`.
   - hadolint clean.
   - `docker history --no-trunc orbit-api:local | grep -c "$POSTGRES_PASSWORD"` → 0 (AC22, image
     half).
   - Standalone `docker run -d -p 127.0.0.1:18080:8000 orbit-api:local`, then `/health` → 200.
   - Wheels resolve on arm64 without a compiler (assumption check).
6. **Trivy + `.trivyignore` (AC14):**
   - Run `~/.claude/hooks/trivy-scan.sh image --severity HIGH,CRITICAL --exit-code 1 orbit-api:local`.
   - **Fixable finding:** bump the base digest (still ≥14 days old) and re-scan.
   - **Finding with no fixed version:** add one `.trivyignore` line, preceded by a comment with
     the CVE, the date, `no fixed version available` and a revisit-by date. Then flag it to Brett
     in the T4 checkpoint.
   - Otherwise leave `.trivyignore` untouched.
   - Never add an entry for a fixable finding, and never use the local-only `.pipeline/waivers.json`
     for this.

**Done-gate:** standard. The image must not be left running.

## T5 — In-repo Firebase Auth emulator image (JDK decision by evidence)

1. **`docker/firebase-emulator/Dockerfile`:**
   - `node:24-trixie-slim@sha256:<index digest ≥14 days old>`. The audit confirmed the tag exists.
   - `ARG FIREBASE_TOOLS_VERSION=15.18.0` (must equal `pipeline-ci.yml`).
   - `npm install -g firebase-tools@${FIREBASE_TOOLS_VERSION} && npm cache clean --force`.
   - `USER node`, `EXPOSE 9099`, Node-`fetch` `HEALTHCHECK`,
     `ENV NODE_OPTIONS=--max-old-space-size=192`.
2. **`firebase.json`** (auth 0.0.0.0:9099, UI off) and **`entrypoint.sh`**:
   - `#!/bin/sh`, `set -eu`.
   - Add `--import=/data` only if `/data/firebase-export-metadata.json` exists.
   - `exec firebase emulators:start --only auth --project demo-orbit-test … --export-on-exit=/data`.
3. **JDK decision — evidence first:**
   - Build with **no JRE**, run it, and probe
     `/emulator/v1/projects/demo-orbit-test/config` → 200. Save the transcript.
   - Only if the CLI refuses without Java: add `openjdk-21-jre-headless` (apt, pinned version,
     `--no-install-recommends`) + `JAVA_TOOL_OPTIONS=-Xmx256m -XX:+UseSerialGC`. Record why.
4. **Prove persistence:**
   - Create a user via the REST signUp.
   - `docker stop` (graceful, with compose `init: true` semantics: run with `--init`).
   - Restart with the same volume; the user still exists with the same `localId`.
5. **Measure:** idle memory (`docker stats --no-stream`) for the T11 footprint table.
6. **Tests:** append to `test_local_stack_config.py`: emulator `FROM` digest-pinned;
   `test_firebase_tools_matches_ci` (parse `FIREBASE_TOOLS_VERSION:` from `pipeline-ci.yml`).
7. **Trivy:** scan the emulator image **advisory** (OQ10). Record the counts; do not gate.

**Done-gate:** standard.

## T6 — Assemble the full compose stack; secrets through moto; single env-file mechanism

1. **`docker-compose.yml`:** the full service set per plan.md §Infrastructure.
   - `api`: build `.` as `orbit-api:local`, env per plan.md with **no `DATABASE_URL`**,
     `read_only`, `tmpfs /tmp`, `cap_drop ALL`, `no-new-privileges`, healthcheck,
     `depends_on … service_healthy`.
   - `migrate`: `profiles: [tools]`, `alembic upgrade head`.
   - **`postgres:16.<newest patch>-alpine@sha256:…`** (owner decision):
     - pick the newest 16.x alpine whose **multi-arch index** digest is ≥14 days old (16.15 at
       audit time if it qualifies);
     - record the chosen patch and digest date in the evidence;
     - `pg_isready` healthcheck, volume `pgdata`;
     - `POSTGRES_USER/PASSWORD/DB` use **`${VAR:?set VAR in .env.local}`**.
   - `redis:7.2.<patch>-alpine@sha256:…`. Pick the newest 7.2 patch whose digest is ≥14 days old;
     at audit time that was 7.2.16. Use the no-persistence flags.
   - `firebase-emulator`: build `docker/firebase-emulator`, `init: true`,
     `stop_grace_period: 30s`, volume `fbauth`.
   - Every port `127.0.0.1:`-bound.
   - Provisional `mem_limit`s.
2. **`scripts/dev/local_aws.py`:** add `seed-secrets` (`put_secret_value` on
   `orbit/database-url`, container-network DSN) and `_redact_dsn`.
3. **Prove the secrets path by hand** (dev-up comes in T7). Every compose call carries
   `--env-file .env.local`:
   - `docker compose --env-file .env.local up -d --wait postgres redis moto firebase-emulator`.
   - `terraform -chdir=infra/envs/local apply -auto-approve` (after `ensure-state-backend` +
     `init -backend-config=backend.moto.hcl` if T3 kept the backend), then
     `.venv/bin/python scripts/dev/local_aws.py seed-secrets --env-file .env.local` (with
     `AWS_ENDPOINT_URL=http://localhost:5001`).
   - `docker compose --env-file .env.local run --rm migrate`.
   - `docker compose --env-file .env.local up -d --wait api`.
   - `docker compose --env-file .env.local exec api env | grep -c DATABASE_URL` → 0.
   - Sign up a user on :9100, then call `POST /me/bootstrap` on :8080 → 200. This proves auth
     → emulator and DB → moto DSN.
4. **Prove the single-mechanism backstop (AC2):**
   - `docker compose config >/dev/null; echo $?` (no `--env-file`) → non-zero, with the
     required-variable message.
   - `docker compose --env-file .env.local up -d --wait api` a second time leaves the postgres
     container ID unchanged (`ps -q postgres`, before and after).
5. **Loopback check:**
   - `lsof -nP -iTCP -sTCP:LISTEN` shows only 127.0.0.1/[::1] for the five ports, and nothing
     on 9099/8000.
   - If Colima does **not** forward 127.0.0.1-bound publishes, apply the plan's documented
     fallback and record the observation.
6. **Secret-material check:** `grep -c "$POSTGRES_PASSWORD"` over the tfstate (and the moto S3
   state object) and `docker history --no-trunc orbit-api:local` → 0.
7. **`tests/integration/test_secrets_facade_moto.py`:**
   - testcontainers `DockerContainer` with the moto image@digest **parsed from
     `docker-compose.yml`**.
   - `AWS_ENDPOINT_URL` and dummy creds set via `monkeypatch`.
   - `get_settings.cache_clear()` and the facade `_cache.clear()` around each test.
   - Cases per AC10.
8. **`tests/unit/test_no_env_branches.py`:** per plan.md §Test strategy.
   - The forbidden list includes `FIREBASE_AUTH_EMULATOR_HOST`.
   - The single allowlist entry is pinned by file + line content.
   - A self-test confirms a synthetic second occurrence is caught.
9. **Append config tests:**
   - `test_ports_loopback_and_mapped`, `test_images_digest_pinned`,
     **`test_postgres_major_matches_rds_engine_major`** (the tag's major 16 == `modules/data`
     `engine_version` major; the minor is not compared), `test_api_service_has_no_database_url`;
   - `test_gitignore_covers_local_secrets` (incl. `*_override.tf`);
   - `test_compose_env_file_single_mechanism`, compose half: every `${POSTGRES_*}` uses `:?`.
   - `test_redact_dsn` in `test_dev_scripts.py`.
10. **Measure:** steady-state `docker stats` with the whole stack idle. Retune the `mem_limit`s to
    observed peak × ~1.5 and note both values for T11.

**Done-gate:** `docker compose --env-file .env.local down` (keep volumes), then the standard gate.
The new integration test runs in this pytest pass, starting its own moto container.

## T7 — `dev-up.sh` / `dev-down.sh` / dev seed, with idempotency and convergence proofs

1. **`scripts/dev-up.sh`** (bash-3.2-compatible, `set -euo pipefail`):
   - Defines `REPO_ROOT` and `dc() { docker compose --env-file "$REPO_ROOT/.env.local" -f "$REPO_ROOT/docker-compose.yml" "$@"; }`.
     **Every** compose call uses `dc`.
   - Implements the 11 steps in plan.md §Command sequence. The preflight checks
     `terraform version` ≥ 1.11, and the `tf-state` step calls `ensure-state-backend` (bucket
     only).
   - Preflight with named fix commands.
   - `--rebuild` is the only flag; anything else → usage + exit 2.
   - Per-step `[dev-up] step=… status=… elapsed_s=…` lines.
   - The loopback assertion.
   - The final report with total wall time and `docker stats`.
2. **`scripts/dev-down.sh`:** the same `REPO_ROOT` + `dc()`.
   - Destroy only if `dc ps moto` reports it healthy, then `dc down`.
   - `--clean` → `dc down -v` + remove the local tfstate if the local backend is in use.
   - Prints the live-gap caveat (moto doesn't enforce the log delete-deny).
   - Bad args → exit 2.
3. **`scripts/seed_dev_data.py`:** per plan.md.
   - Idempotent dev user via the `seed_dast_user.py` pattern against :9100.
   - API demo data with check-before-insert.
   - Prints the dev user's UID (for AC4 evidence), never the token or password.
   - Loopback guards.
4. **dev-up also runs** `FIREBASE_AUTH_EMULATOR_HOST=localhost:9100 scripts/seed_ui_test_user.sh`.
5. **Tests:**
   - Extend `test_dev_scripts.py` with the seed validators and loopback guards.
   - Complete `test_compose_env_file_single_mechanism`, scripts half: no `docker compose`
     occurrence in `dev-up.sh`/`dev-down.sh` outside the `dc()` definition line.
6. **Evidence** (to `.pipeline/a1-evidence/t7-*`):
   - **AC1:** fresh `git clone` of the branch into the session scratchpad, copy `.env.local`,
     `dev-up.sh` → /health 200, `dev-down.sh --clean`, delete the clone (disk pressure).
   - **AC2:** dev-up ×2 plus the count comparison; postgres container ID unchanged; no
     `Recreating` line.
   - **AC3:** (a) interrupt after `infra-up`, then re-run; (b)
     `docker compose --env-file .env.local restart moto`, then re-run. Under the S3 backend, the
     bucket, state and any lock vanish with moto, and dev-up must still converge.
   - **AC4:** `dev-down` → `dev-up` (same UID, data present, second apply succeeds); `--clean`
     removes both volumes; bad flags → 2.
   - **AC22:** `grep -c "$POSTGRES_PASSWORD"` over the full dev-up and seed transcripts → 0, with
     the DSN shown only as `://user:***@`.
   - **AC29:** cold first-run wall time and warm re-run wall time from the report.

**Done-gate:** `dev-down.sh`, then the standard gate (suite + native smoke + `dev-up`/`dev-down`
round trip).

## T8 — CI: the one new `local-stack` job

1. **`.github/workflows/pipeline-ci.yml`:** add `local-stack` exactly per plan.md §CI.
   - `services.moto` on the same digest with `MOTO_IAM_LOAD_MANAGED_POLICIES=true` and
     `5001:5000`.
   - SHA-pinned `actions/checkout` (the repo's existing pin) and `hashicorp/setup-terraform`
     (look up the v4.0.1 release commit SHA; `terraform_version: 1.15.9`, which satisfies ≥1.11).
   - hadolint, Trivy and Checkov images pinned by digest (≥14 days old).
   - `pip install boto3==1.43.40` for `ensure-state-backend` (bucket only; only if T3 kept the
     backend).
   - `init`/`validate`/`plan`.
   - **The guard-probe steps (AC8):**
     - write `infra/envs/local/zz_probe_override.tf` with `allowed_account_ids = ["000000000000"]`;
     - `if terraform -chdir=infra/envs/local plan -input=false 2>&1 | tee probe1.txt; then exit 1; fi; grep -qi 'not allowed' probe1.txt`;
     - `rm` the override;
     - run `plan` with fake `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_PROFILE` in the step
       `env:` (it must succeed);
     - **If T1 recorded Layer B as unclaimed:** CI keeps probe 2 and the regex probe, and replaces
       probe 1's assertion with a comment pointing at the recorded gap. CI never asserts a claim
       that T1 disproved.
   - The full Terraform cycle with `plan -detailed-exitcode`.
   - `docker build` + Trivy image (honors `.trivyignore`).
   - Checkov `envs/local`.
   - Liveness artifact checks.
   - `permissions: contents: read`, `timeout-minutes: 25`.
2. **Do not touch** any of the seven existing active jobs. Confirm that
   `git diff main -- .github/workflows/pipeline-ci.yml` contains additions only, inside the new
   job.
3. **Local dry run:** run each job command locally in the same order against the compose moto.
   Run `actionlint` if available; otherwise record that it was skipped. The real proof is the
   PR's CI run (deployment stage). Note in the PR that `local-stack` should be added to branch
   protection after its first green run.

**Done-gate:** standard.

## T9 — iOS build configuration (Debug → compose)

**Memory:** compose may be down for the build. Shut down the Simulator when done.

1. **New xcconfigs:**
   - `ios/Orbit/Config/Debug.xcconfig`: `ORBIT_API_BASE_URL = http:/$()/localhost:8080` and
     `ORBIT_FIREBASE_AUTH_EMULATOR_HOST = localhost:9100`.
   - `ios/Orbit/Config/Release.xcconfig`: `ORBIT_API_BASE_URL = http:/$()/localhost:8001` (the
     **pre-existing** literal, moved verbatim; not a fix) and `ORBIT_FIREBASE_AUTH_EMULATOR_HOST =`.
   - Header comments explain the `/$()/` escape and that Release's base URL is a pre-existing
     placeholder replaced by the real HTTPS origin at E1/E3.
2. **`ios/Orbit/project.yml`:** `configFiles` on the `Orbit` target. Then
   `cd ios/Orbit && xcodegen generate`.
3. **`Info.plist`:** `OrbitAPIBaseURL` → `$(ORBIT_API_BASE_URL)`; add `OrbitFirebaseAuthEmulatorHost`
   → `$(ORBIT_FIREBASE_AUTH_EMULATOR_HOST)`. **No ATS key.** Keep the SC-3 prose warning intact.
4. **`OrbitApp.swift`:** doc comment only.
5. **`AuthFlowUITests.launchApp()`:** set the two `launchEnvironment` keys only when
   `ProcessInfo.processInfo.environment["ORBIT_UITEST_API_BASE_URL"]` /
   `["ORBIT_UITEST_FIREBASE_AUTH_EMULATOR_HOST"]` are non-empty. Then run
   `python scripts/check_ui_test_identifier_consistency.py` (must still pass).
6. **Prove (AC26):**
   - `xcodebuild -showBuildSettings -configuration Debug` and `-configuration Release`, grepping
     `ORBIT_`. Release shows an empty emulator host and the unchanged `http://localhost:8001`.
   - `xcodebuild build` (Debug, iPhone 17 Pro simulator).
   - `xcodebuild test -only-testing:OrbitTests` → green.
   - `bash scripts/ci/store-compliance.sh` → critical 0.
   - `grep -c NSAppTransportSecurity ios/Orbit/Resources/Info.plist` → 0.
   - `xcrun simctl shutdown all`.

**Done-gate:** standard backend gate (Simulator shut down, stack down) — nothing backend changed,
so this is a regression check.

## T10 — iOS acceptance phase: done-flow from the Simulator against the containers

**Operator sequencing (binding):**
- Compose **up**.
- The pytest suite **idle** for the whole task.
- Close other heavy apps.
- Never raise Colima memory.

1. `scripts/dev-up.sh` → healthy. Optionally capture `docker stats` here too, with the Simulator
   booted (footprint under real use).
2. Run with **no** `TEST_RUNNER_ORBIT_UITEST_*` variables set, so the Debug xcconfig is what
   gets tested:
   `xcodebuild test -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OrbitUITests/SmokeUITests -resultBundlePath .pipeline/a1-evidence/smoke.xcresult`.
   If a single run fails on a wait expiry, re-run it alone before treating it as a regression
   (`docs/mac-session-handoff.md`).
3. Capture `docker compose --env-file .env.local logs --since <start> api` and extract the
   request lines. 2xx is required for `POST /me/bootstrap`, `POST /fuel/entries`,
   `POST /train/sets`, `POST /weight`, `PATCH /profile` and `DELETE /me`.
4. **ATS contingency:** if the run fails with NSURLError `-1022`, add `NSAllowsLocalNetworking`
   via a **Debug-only** Info.plist (per-configuration `INFOPLIST_FILE`), re-run, and record it.
   Release is untouched.
5. **Advisory:** run the full `OrbitUITests` suite against compose. The UI-test user was seeded
   by dev-up. Record the result; it is not a gate.
6. **AC30, smoke-with-stack-up half:** while the stack is still up, run
   `bash ~/.claude/hooks/smoke-check.sh` → PASS on :8000 (proves no collision with :8080).
7. `xcrun simctl shutdown all`, then `scripts/dev-down.sh`.

**Done-gate:** standard (stack down, suite green, native smoke PASS).

## T11 — Documentation, footprint record, A2 owed rows, final regression, security hand-off

1. **`docs/local-development.md`:** the learning document. Covers every AC28 item, plus:
   - the **measured** footprint table from T5/T6/T7/T10 (idle, peak, with the Simulator; final
     `mem_limit`s and how they were derived);
   - dev-up cold and warm wall time;
   - the machine spec;
   - the JDK finding;
   - the `MOTO_IAM_LOAD_MANAGED_POLICIES` finding;
   - the account-guard probe outcome (Layer B claimed or unclaimed);
   - the `--env-file` invocation rule;
   - **S3-native locking:**
     - what the `.tflock` object is;
     - the T3 lock-probe transcript excerpt;
     - `force-unlock`;
     - why not DynamoDB, with the stated `iac-conventions` deviation;
   - **Postgres:** the newest 16.x locally (chosen patch and date), major parity, and the prod
     16.6 bump owed to A2;
   - the Release base URL as a pre-existing placeholder owed to E1/E3;
   - the Colima loopback observation;
   - the AirPlay :5000 note;
   - AC9's outcome.
   No invented minimum RAM.
2. **Other docs:**
   - Update `CLAUDE.md` (How to run: `scripts/dev-up.sh` / `dev-down.sh [--clean]`, the port
     table pointer, venv-activation note, `docker compose --env-file .env.local` form; keep the
     existing Start/Test lines), `README.md`, `infra/README.md` (including the local-vs-prod
     locking difference), `infra/envs/local/README.md` (new), `ios/Orbit/README.md`,
     `docs/system_architecture.md` (local topology section + diagram), `docs/roadmap.md`
     (A1 entry), `scripts/README.md` and `tests/README.md`.
   - Fold `docs/a1-run-start.md`'s durable pre-flight (steps 1–8 minus PR-specific notes) into
     `docs/mac-session-handoff.md`, with the `TEST_RUNNER_ORBIT_UITEST_*` native-stack recipe.
     Then delete `docs/a1-run-start.md`.
3. **A2 owed rows:** in `plans/A2-production-terraform-authoring.md` § Inherited from A1:
   - resolve row 3 (remote state) and row 4 (Terraform against an emulator) to their actual
     outcome;
   - **add row A:** bump `infra/modules/data` `engine_version` 16.6 → a currently supported RDS
     16.x. **Firm.**
   - **add row B:** align `infra/backend.tf.template` + `infra/backend.hcl.example` to
     `use_lockfile = true`, dropping `dynamodb_table`; decide whether the E1 bootstrap needs a
     lock table; reconcile with `iac-conventions`. **Firm.**
   - Do **not** edit `modules/data` `engine_version` or the prod backend template in A1.
4. **Live-only gaps:** listed verbatim (AC31), and staged for the PR description (documentation
   stage), together with the "parity pins" note (moto, firebase-tools).
5. **Final regression (AC30):** stack down, Simulator off,
   `pytest --cov=src --cov-fail-under=80` → green (record the count and coverage), then native
   smoke PASS.
6. **Security hand-off (AC32, delegated):** list in `.pipeline/a1-evidence/mechanisms.md` each
   STRIDE mechanism with its file path and the evidence file proving its enabling condition.
   - E1 is listed as Layer A, plus Layer B only if probe 1 passed.
   - T4 lists the single env-file mechanism and its test.
   - T6 lists the lockfile and its T3 lock-probe evidence.
   - S2 states that the emulator host is mitigated and the Release base URL is pre-existing (not
     claimed).
   - Raise OQ9/OQ10 waiver needs and any `.trivyignore` addition to Brett. Agents never record
     waivers.

**Done-gate:** standard.
