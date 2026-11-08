---
feature: a1-local-environment
criteria_total: 32
delegated_criteria: [AC32]
revision: 2   # rev 1 = plan-audit flags 1-2; rev 2 = owner checkpoint (postgres newest 16.x, use_lockfile, S2 wording). AC count unchanged.
source: >
  Derived from .pipeline/requirements.md (authoritative), .pipeline/operator-kickoff.md (incl.
  Plan-checkpoint decisions 2026-10-20), plans/A1-local-environment.md § Acceptance sketch, and
  PROJECT.md/CLAUDE.md "What done means" (traced in plan.md). No perf.budget is declared:
  dev-up.sh wall time is measured and recorded only (requirements.md), and no API perf budget
  applies this run (plan.md §Performance, OQ8). No migration is added, so no
  migration-reversibility criterion applies. No new stored field, so no data_protection
  criterion applies.
evidence_dir: .pipeline/a1-evidence/
---

# Acceptance criteria — A1 Local environment

**Conventions used in the table below.**
- **Ports:** host 8080 → api 8000, 5433 → postgres 5432, 6380 → redis 6379, 9100 → emulator 9099,
  5001 → moto 5000.
- **Evidence:** "Evidence: …" means a command transcript saved under `.pipeline/a1-evidence/`.
- **Backend pytest:** always run with the compose stack **down**, the venv activated, and the
  Simulator shut down (operator kickoff).
- **Compose commands:** every compose command here is run from the repo root as
  `docker compose --env-file .env.local …`. This is the plan's single invocation mechanism;
  inside the scripts it is the `dc()` function.

| ID | Criterion | File / layer | How verified |
|---|---|---|---|
| AC1 | Fresh clone + `.env.local` (copied from `.env.local.example`, sentinels replaced) → `scripts/dev-up.sh` exits 0, and `GET http://localhost:8080/health` returns 200. | `scripts/dev-up.sh`, `docker-compose.yml`, `Dockerfile` | Evidence: `git clone` of the branch into the session scratchpad, `cp` the env file, run `dev-up.sh`, then `curl -sf -o /dev/null -w '%{http_code}' http://localhost:8080/health` → `200`. Also the dev-up transcript's `step=health status=ok`. |
| AC2 | `dev-up.sh` is idempotent. An immediate second run exits 0 and creates no duplicates: `terraform apply` reports 0 changes, `migrate` is a no-op, postgres is **not** recreated, and the dev user's demo data for today is unchanged. **Single compose env mechanism:** every compose call in `dev-up.sh`/`dev-down.sh` goes through `dc()` (`docker compose --env-file .env.local …`), and `docker-compose.yml` interpolates `POSTGRES_USER/PASSWORD/DB` only with required syntax `${VAR:?…}`, so a call without the env file fails loudly rather than interpolating blanks. | `scripts/dev-up.sh`, `scripts/dev-down.sh`, `scripts/seed_dev_data.py`, `docker-compose.yml` | Evidence: run twice. Between runs, compare `GET /fuel?day_key=<today>` entry count, `GET /weight` entry count and `GET /train?day_key=<today>` done-set count (authed as the dev user) → equal. The second transcript shows `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` and no `Recreating …postgres`. The postgres container ID is unchanged across runs (`docker compose --env-file .env.local ps -q postgres`). pytest: `test_local_stack_config.py::test_compose_env_file_single_mechanism`. Evidence: `docker compose config` **without** `--env-file` exits non-zero with the required-variable message. |
| AC3 | `dev-up.sh` converges after partial failure. (a) Interrupt it after `infra-up` (Ctrl-C or `kill`); a re-run completes to AC1's 200. (b) `docker compose --env-file .env.local restart moto` (moto state lost while tfstate persists); a re-run's apply recreates the resources and completes. | `scripts/dev-up.sh`, `infra/envs/local/` | Evidence: both scenarios' transcripts ending `step=health status=ok`. |
| AC4 | `dev-down.sh` keeps volumes by default. After `dev-down.sh` then `dev-up.sh`: the dev user signs in with the **same UID**, and its previously seeded rows are still returned. The second bring-up's `terraform apply` succeeds after the destroy (recovery-window regression). `dev-down.sh --clean` removes `orbit-local_pgdata` and `orbit-local_fbauth`, and the next dev-up re-migrates and re-seeds. Any other argument prints usage and exits 2. | `scripts/dev-down.sh`, `docker-compose.yml`, `docker/firebase-emulator/entrypoint.sh` | Evidence: UID printed by `seed_dev_data.py` before and after (equal); `docker volume ls` before and after `--clean`; `dev-down.sh --bogus; echo $?` → `2`. |
| AC5 | Terraform on `infra/envs/local` against moto: `apply` clean; an immediate second `plan -detailed-exitcode` exits **0** ("No changes"); `destroy` clean; `apply` **after** `destroy` clean again. | `infra/envs/local/*`, `.github/workflows/pipeline-ci.yml` (`local-stack`) | Evidence: local transcript of the full cycle. CI: `local-stack` job green on the PR, running the same cycle against a moto service container. |
| AC6 | `modules/secrets` exposes `recovery_window_in_days`: number, default **30**, validation `== 0 \|\| (>= 7 && <= 30)`. It is applied to both secrets. `envs/local` passes `0`; root `infra/` passes nothing, so prod keeps the AWS default. No forked copy of any module exists. | `infra/modules/secrets/{main,variables}.tf`, `infra/envs/local/main.tf` | `terraform -chdir=infra plan` shows `recovery_window_in_days = 30` on both secrets. An out-of-range value (e.g. 3 via a scratch `*_override.tf`) fails validation. `grep -rl 'resource "aws_secretsmanager_secret"' infra/` → only `modules/secrets/main.tf`. |
| AC7 | Module split, never fork. `modules/data_keys` holds the RDS/Redis CMKs, aliases and key policies (checkov skips kept inside the data blocks). `modules/data` holds RDS/ElastiCache, subnet/parameter groups and the monitoring role, taking key ARNs as inputs. Its `engine_version` stays `16.6`; the bump is owed to A2. `modules/app_identity` holds the app execution role. `envs/local` composes only `app_identity` + `secrets` + `observability` + `data_keys` (not `data`, not `network`). Root `infra/` composes all of them with `moved` blocks, and still passes `infra-validate.sh` offline. | `infra/modules/{data,data_keys,app_identity}/`, `infra/main.tf`, `infra/outputs.tf`, `infra/envs/local/main.tf` | `bash ~/.claude/hooks/infra-validate.sh` exits 0, and `.pipeline/infra-plan.txt` is written. `grep -n 'module "' infra/envs/local/main.tf` lists exactly the four modules. `git diff main -- infra/modules/data/main.tf \| grep engine_version` is empty. Review of the `moved` blocks. |
| AC8 | `envs/local` provider guard, each layer claimed only as far as a probe proves it. See the layer and probe list below the table. | `infra/envs/local/{providers,variables}.tf`, `docker-compose.yml`, `.gitignore`, `.github/workflows/pipeline-ci.yml` | Evidence (T1, `t1-guard-*.txt`): the regex-probe failure; probe 1 output (failure plus the account-not-allowed message) **or** the recorded non-failure with Layer B marked unclaimed; probe 2 success transcript; `git check-ignore infra/envs/local/zz_probe_override.tf` matches. CI: the `local-stack` probe steps are green. AC5's apply output lists `module.observability.aws_iam_role_policy_attachment.app_xray_write` created. |
| AC9 | Remote state (staged), with S3-native locking. See the two acceptable outcomes below the table. | `infra/envs/local/{backend.tf,backend.moto.hcl,versions.tf}`, `scripts/dev/local_aws.py`, docs | (a) `terraform -chdir=infra/envs/local state list` succeeds after `init -backend-config=backend.moto.hcl`. The boto3 `list_objects_v2` key list during and after the lock probe shows the lock object, then its absence. The lock-probe transcript (`t3-lock-*.txt`) shows the second plan's "Error acquiring the state lock". pytest: `test_local_stack_config.py::test_backend_uses_lockfile`, `test_dev_scripts.py::test_ensure_state_backend_creates_no_dynamodb`. AC5 evidence under this backend. (b) The doc and A2-brief diff. |
| AC10 | The secrets facade reads from moto with no code change. `get_secret("orbit/database-url")` returns the value stored in a moto server reached via `AWS_ENDPOINT_URL`. A repeat call is served from the TTL cache. `resolve_database_url()` with `DATABASE_URL` unset returns the moto value. A missing secret raises `SecretNotFoundError`. | `tests/integration/test_secrets_facade_moto.py` (testcontainers moto, digest parsed from `docker-compose.yml`) | pytest: `test_secrets_facade_moto.py` (all cases) green locally and in CI `build-and-test`. |
| AC11 | In the running stack, `api` and `migrate` have **no** `DATABASE_URL`, and they reach Postgres using the DSN fetched from moto through the facade. | `docker-compose.yml`, `scripts/dev/local_aws.py` (`seed-secrets`) | Evidence: `docker compose --env-file .env.local exec api env \| grep -c DATABASE_URL` → `0`. `docker compose --env-file .env.local run --rm migrate` succeeds. An authed `GET /profile` as the dev user returns 200. `tests/unit/test_local_stack_config.py::test_api_service_has_no_database_url`. |
| AC12 | No environment-conditional branches in `src/orbit/`, and no file there changed. The forbidden-pattern scan passes: `AWS_ENDPOINT_URL`, `endpoint_url`, `localstack`, `moto`, `FIREBASE_AUTH_EMULATOR_HOST`, `environment\s*(==\|!=\|in)`, `is_local`, `if .*\blocal\b`. Exactly one allowlisted pre-existing occurrence is pinned by file **and** line content (the `FIREBASE_AUTH_EMULATOR_HOST` check in `auth/firebase.py::_build_credential`, the Firebase SDK's own toggle, which predates A1), so any second occurrence fails. | `tests/unit/test_no_env_branches.py` | pytest: `test_no_env_branches.py` green, including a self-test that a synthetic second occurrence is caught. Evidence: `git diff main -- src/orbit` is empty. |
| AC13 | API `Dockerfile`: two stages; both `FROM`s are digest-pinned (multi-arch index, ≥14 days old); runtime is `USER 10001:10001`; `HEALTHCHECK` on `/health`; **no** `ENV`/`ARG` for `FIREBASE_AUTH_EMULATOR_HOST`, `AWS_ENDPOINT_URL` or `DATABASE_URL`; no Poetry in the runtime image; hadolint clean; a standalone container serves `/health` 200. | `Dockerfile` | pytest: `test_local_stack_config.py::test_dockerfile_*` (incl. `test_dockerfile_bakes_no_emulator_or_endpoint_env`). Evidence: `docker run --rm --entrypoint id orbit-api:local -u` → `10001`; `docker run --rm --entrypoint sh orbit-api:local -c 'command -v poetry'` → empty; hadolint output clean; `docker run -d -p 127.0.0.1:18080:8000 orbit-api:local` then curl `/health` → 200. |
| AC14 | Trivy image scan of the API image: 0 unwaived HIGH/CRITICAL. Any new `.trivyignore` entry is restricted to a finding with **no fixed version available**, and carries a dated reason/revisit-by comment. Fixable findings are fixed by a base-digest bump, never ignored. | `Dockerfile`, `.trivyignore` (conditional) | CI `local-stack` Trivy step green. Local evidence: `~/.claude/hooks/trivy-scan.sh image --severity HIGH,CRITICAL --exit-code 1 orbit-api:local` → 0. `git diff main -- .trivyignore` is either empty or each added line has its reason comment and a "no fixed version" note. (The emulator image is scanned advisory only, per OQ10.) |
| AC15 | Checkov reports no new unwaived failures on `infra/` (including `envs/local`, `modules/data_keys`, `modules/app_identity`). Every new `#checkov:skip` carries an inline reason. | `infra/**` | Evidence: `~/.claude/hooks/checkov-scan.sh -d infra` and `-d infra/envs/local` summaries; CI `containers-iac` + `local-stack` Checkov steps green. |
| AC16 | `.dockerignore` is an allowlist (first rule `*`). With a canary `.env.local` and `.pipeline/` present, the built image contains neither, and no `.git`. | `.dockerignore` | pytest: `test_local_stack_config.py::test_dockerignore_is_allowlist`. Evidence: `docker run --rm --entrypoint sh orbit-api:local -c 'ls -a /app'` shows only the allowlisted paths. |
| AC17 | Every compose `ports:` entry binds `127.0.0.1` with the mappings above. dev-up's `loopback-assert` step aborts if any host listener is not loopback-only. While the stack is up, host ports **9099** and **8000** stay free (test-suite emulator fixture, smoke hook). | `docker-compose.yml`, `scripts/dev-up.sh` | pytest: `test_local_stack_config.py::test_ports_loopback_and_mapped`. Evidence: `lsof -nP -iTCP -sTCP:LISTEN` with the stack up (only 127.0.0.1/[::1] on 8080/5433/6380/9100/5001; nothing on 9099/8000); `psql -h 127.0.0.1 -p 5433` and `redis-cli -p 6380 ping` work from the host. |
| AC18 | Image provenance and parity. See the itemized list below the table. | `docker-compose.yml`, `Dockerfile`, `docker/firebase-emulator/Dockerfile` | pytest: `test_local_stack_config.py::test_images_digest_pinned`, `::test_postgres_major_matches_rds_engine_major`, `::test_firebase_tools_matches_ci`. Evidence: Mac dev-up (arm64) + CI `local-stack` docker build/pull on amd64. Digest push dates and the chosen postgres patch, with the reason it is the newest eligible one, are noted in the T4/T5/T6 evidence. |
| AC19 | In-repo Firebase emulator image: pinned base digest + pinned firebase-tools; `USER node`; HEALTHCHECK; runs `--only auth --project demo-orbit-test`; imports and exports `/data` (UIDs persist, AC4); not a community image. The JDK decision is recorded with evidence: none needed, or the contingency JRE plus the reason. | `docker/firebase-emulator/{Dockerfile,firebase.json,entrypoint.sh}`, `docs/local-development.md` | Evidence: `docker build`; container `healthy`; `curl -sf http://localhost:9100/emulator/v1/projects/demo-orbit-test/config` → 200; a transcript of the no-JRE start attempt; the docs section naming the decision. |
| AC20 | Seeds. The dev Firebase user is created-or-signed-in idempotently (the `seed_dast_user.py` pattern). Dev demo data (bootstrap, ≥1 fuel entry, ≥1 done set, ≥1 weight for today) goes through the **API** with check-before-insert. No migration is added (`migrations/versions/` unchanged; "new users start empty" holds). The UI-test user is seeded into the compose emulator via the existing `seed_ui_test_user.sh`. | `scripts/seed_dev_data.py`, `scripts/dev-up.sh` | Evidence: dev-up seed step output; AC2's counts; `git diff main --stat -- migrations/` empty; `FIREBASE_AUTH_EMULATOR_HOST=localhost:9100 scripts/seed_ui_test_user.sh` → exit 0 ("already present … signs in"). |
| AC21 | Input-surface controls for every A1 input source (validation **and** rate limit). See the per-source list below the table. | `scripts/dev/local_aws.py`, `scripts/seed_dev_data.py`, `scripts/dev-{up,down}.sh`, `docker-compose.yml` | pytest: `tests/unit/test_dev_scripts.py`, one test per contract row plus the guard-before-client test; `test_local_stack_config.py::test_compose_env_file_single_mechanism`. Evidence: `dev-up.sh --bogus; echo $?` → 2. |
| AC22 | No secret material in state, image or output. The Postgres password string does not occur in `infra/envs/local/terraform.tfstate` (or the moto S3 state object after T3), in `docker history`/`docker inspect` of `orbit-api:local`, or in dev-up/seed output (DSN shown as `://user:***@`). | `scripts/dev/local_aws.py::_redact_dsn`, `scripts/seed_dev_data.py`, `scripts/dev-up.sh`, `modules/secrets` (`ignore_changes`) | pytest: `test_dev_scripts.py::test_redact_dsn`. Evidence: `grep -c "$POSTGRES_PASSWORD"` over the tfstate, `docker history --no-trunc` (T4/T6) and the full dev-up + seed transcripts (T7) → all `0`. |
| AC23 | Repo hygiene. `.gitignore` covers `.env.local`, `**/.terraform/`, `*.tfstate.*`, `.local/` and `*_override.tf`. `.env.local.example` contains only `CHANGE_ME` sentinels for secrets, and `validate-env` refuses them. Gitleaks is clean on the branch. | `.gitignore`, `.env.local.example` | pytest: `test_local_stack_config.py::test_gitignore_covers_local_secrets`, `test_dev_scripts.py::test_sentinel_refused`. Evidence: `git check-ignore .env.local infra/envs/local/.terraform infra/envs/local/zz_probe_override.tf` all match; CI `secrets` job green. |
| AC24 | CI: exactly one new job, `local-stack`. The seven active jobs are byte-identical to `main`. The new job has `contents: read`, no secrets or OIDC, SHA-pinned actions, digest-pinned images, and a moto service container (`MOTO_IAM_LOAD_MANAGED_POLICIES=true`). It runs `fmt -check`, hadolint (both Dockerfiles), `ensure-state-backend` (bucket only, when the backend exists), `init`/`validate`/`plan`, **the two AC8 account-guard probes**, apply → plan (exit 0) → destroy → apply → destroy, docker build + Trivy image, and Checkov `envs/local`, each with a liveness artifact check. | `.github/workflows/pipeline-ci.yml` | Diff review: `git diff main -- .github/workflows/pipeline-ci.yml` is additions only, inside the new job. The `local-stack` job is green on the PR (deployment stage links the run). |
| AC25 | `build-provenance.yml` stays inert. Its gate requires a root `Dockerfile` **and** `vars.DEPLOY_ENABLED == 'true'`. With the variable unset it logs the skip, assumes no role and pushes nothing. | `.github/workflows/build-provenance.yml` | Diff review of the gate step. After merge, the workflow run on `main` shows "inert until E1" and every later step skipped (noted in the PR as a post-merge check). |
| AC26 | iOS build configuration. See the itemized list below the table. | `ios/Orbit/Config/*.xcconfig`, `ios/Orbit/project.yml`, `ios/Orbit/Resources/Info.plist`, `ios/Orbit/Tests/UITests/AuthFlowUITests.swift` | Evidence: `xcodebuild -showBuildSettings -configuration Debug\|Release \| grep ORBIT_` (values as stated, including Release's unchanged base URL); `xcodebuild build` + `test -only-testing:OrbitTests` green; `bash scripts/ci/store-compliance.sh` → critical 0; `grep -c NSAppTransportSecurity ios/Orbit/Resources/Info.plist` → 0. **Reduced assurance:** the Swift side is not gate-verified. |
| AC27 | **iOS done-flow proven in-run.** `SmokeUITests.testFullSmokeChainAgainstTheRealAPI` (register → quick-add food → toggle set (score ticks, Body glows) → log weight → palette/units persist across relaunch → delete account cascades) passes on the iOS Simulator against the **containerized** API. No launch-env overrides, so the Debug xcconfig is proven too. Compose is up; the pytest suite is idle. | `ios/Orbit/Tests/SmokeUITests.swift` (unchanged), the compose stack | Evidence: `xcodebuild test -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OrbitUITests/SmokeUITests -resultBundlePath .pipeline/a1-evidence/smoke.xcresult` → TEST SUCCEEDED. `docker compose --env-file .env.local logs api` excerpt shows 2xx for `POST /me/bootstrap`, `POST /fuel/entries`, `POST /train/sets`, `POST /weight`, `PATCH /profile` and `DELETE /me` in that window. A single failure is re-run alone before being treated as a regression. The PR surfaces the reduced-assurance stamp. |
| AC28 | Documentation. See the itemized list below the table. | `docs/**`, `CLAUDE.md`, `README.md`, `infra/README.md`, `infra/envs/local/README.md`, `ios/Orbit/README.md`, `scripts/README.md`, `tests/README.md`, `plans/A2-production-terraform-authoring.md` | Doc review against this checklist (each item present). `bash ~/.claude/hooks/check-doc-identifiers.sh` clean, if the docs stage runs it. |
| AC29 | Footprint and timing **measured and recorded**, not prescribed. `docs/local-development.md` holds: per-container steady-state memory (`docker stats --no-stream`) with the stack idle; peak during dev-up; the final `mem_limit` values and how they were derived; `dev-up.sh` wall time for the cold first run and a warm re-run; the machine (M2, 8 GB; Colima 4 CPU / 3 GB / 20 GB). No minimum-RAM figure is claimed, and no `perf.budget.*` is emitted. | `docs/local-development.md`, `scripts/dev-up.sh` (report step) | Evidence: dev-up report output and `docker stats` transcript, matching the doc table. No `.perf.budget.*` key exists in any JSON artifact this run. |
| AC30 | No regression. The backend suite `pytest --cov=src --cov-fail-under=80` is green, with the existing tests untouched and hermetic on testcontainers (run with compose **down**). The native pipeline smoke check prints `PASS — http://localhost:8000/health responded 200` both with the compose stack **down** and **up** (no port collision). | `tests/**`, `.pipeline/smoke.env` (unchanged) | Evidence: pytest summary (count ≥ the pre-A1 count plus the new tests; coverage ≥ 80%); `bash ~/.claude/hooks/smoke-check.sh` run twice (stack down, then stack up), both PASS. |
| AC31 | Live-only gaps recorded, never faked. Docs and the PR description list each gap as **owed to E1/E2**: IAM enforcement, VPC/SG/NAT, real RDS/ElastiCache behaviour, Lambda cold start/concurrency/VPC, front door + WAF, alarm → SNS delivery, quotas and eventual consistency, CloudWatch log delivery. No AC claims any of them. | `docs/local-development.md`, PR description | Doc review; the PR-description section is present (documentation/deployment stage). |
| AC32 | Security reconciliation for the change set. ASVS L1/L2 for the triggered chapters (V2, V13, V15, V16) is met or recorded-waived. Every STRIDE mechanism in plan.md § Threat Model is present as named, including its enabling condition (e.g. the I1 `lsof` assertion; the E1 Layer A probes, plus Layer B only if probe 1 passed; the S1 test; the T4 single env-file mechanism; the T6 lockfile proven by T3's concurrent-plan probe). S2 is checked as worded: the emulator host is mitigated and the Release base URL is the pre-existing value, not claimed. | change set; `.pipeline/security-report.md` | **Delegated to security** (security-stage deliverable; gate conjunct). |

## AC8 — provider guard layers and probes

**Layer A** — always required, and proven by probes:
- **Endpoint pinning:** all 9 endpoints (`secretsmanager ssm kms logs iam s3 sns dynamodb sts`)
  come from `var.moto_endpoint`.
  - That variable is validated by `^http://(localhost\|127\.0\.0\.1\|moto):[0-9]{2,5}$`.
  - **Regex probe:** `plan -var moto_endpoint=https://example.com` must fail validation.
- **Static credentials:** static dummy credentials win over ambient credentials.
  - **Probe 2:** export `AWS_ACCESS_KEY_ID=AKIAEXAMPLEPROBE0000`,
    `AWS_SECRET_ACCESS_KEY=probe/not/real` and `AWS_PROFILE=nonexistent-probe`. `plan` must
    **still succeed**, which is only possible against moto.

**Layer B** — claimed only if probe 1 passes:
- `allowed_account_ids = ["123456789012"]`, with `skip_credentials_validation` and
  `skip_requesting_account_id` left unset.
- **Probe 1:** a scratch `infra/envs/local/zz_probe_override.tf` sets
  `allowed_account_ids = ["000000000000"]`. `plan` must **fail** with the provider's
  account-not-allowed error. The file is then deleted; `*_override.tf` is gitignored.
- If probe 1 does not fail, Layer B is recorded as **unclaimed** in `docs/local-development.md` and
  the security hand-off. The criterion still passes on Layer A, plus that record.

**Also required:** moto runs with `MOTO_IAM_LOAD_MANAGED_POLICIES=true`, so the observability
X-Ray attachment applies.

## AC9 — remote state outcomes

**Either (a): the S3 backend lands.**
- `envs/local` state lives in moto S3 bucket `orbit-local-tfstate`, key
  `envs/local/terraform.tfstate`.
- The backend uses **`use_lockfile = true`**:
  - no `dynamodb_table` anywhere in `backend.moto.hcl`;
  - **no DynamoDB table created** (nothing else needs one);
  - `envs/local` requires Terraform ≥ 1.11.
- `local_aws.py ensure-state-backend` creates **only** the bucket (versioned, SSE-S3) and is
  idempotent.
- **Locking is proven.** While a lock-holding Terraform process runs, a concurrent
  `terraform plan -lock-timeout=0s` fails with "Error acquiring the state lock", and the object
  `envs/local/terraform.tfstate.tflock` exists in the bucket. After the holder exits, `plan`
  succeeds and the `.tflock` object is gone.
- AC5's full cycle passes under this backend.

**Or (b): the backend step failed.**
- The local backend is retained.
- The failure is recorded in `docs/local-development.md`.
- `plans/A2-production-terraform-authoring.md` § Inherited row 3 is marked **owed**.

## AC18 — image provenance and parity

- Every compose `image:` and Dockerfile `FROM` is `tag@sha256:<64 hex>` of a multi-arch index,
  using the newest digest ≥14 days old.
- **Postgres** is the **newest 16.x alpine** image whose multi-arch digest is ≥14 days old (owner
  decision 2026-10-20).
  - Its **major** (16) equals the major of `modules/data` `engine_version`.
  - The minor is deliberately not compared.
  - The prod bump from 16.6 is owed to A2.
- Redis is 7.2.x, the documented substitute for the nonexistent OSS 7.1.
- Emulator firebase-tools equals `pipeline-ci.yml` `FIREBASE_TOOLS_VERSION`.
- Images run on arm64 (Mac) and build or pull on amd64 (CI).

## AC21 — input sources and their controls

Each source has a validation contract and a rate-limit line.

| Input source | Validation | Rate limit |
|---|---|---|
| `.env.local` | Keys allowlisted. `POSTGRES_USER`/`POSTGRES_DB` match `^[a-z_][a-z0-9_]{0,62}$`. `POSTGRES_PASSWORD` matches `^[A-Za-z0-9_-]{16,128}$` and is not `CHANGE_ME`. `ORBIT_DEV_USER_EMAIL` uses the anchored email regex in plan.md, ≤254 chars. `ORBIT_DEV_USER_PASSWORD` matches `^[\x21-\x7E]{12,128}$` and is not `CHANGE_ME`. Malformed input → exit 2, naming the key and never echoing the value. Parsed, never `source`d. Compose consumes it only via `--env-file`, with `${POSTGRES_*:?}` required interpolation. | `rate_limit_waiver: local operator config file on the developer's own machine; no untrusted caller` |
| `AWS_ENDPOINT_URL` for host scripts | Must match `^http://(localhost\|127\.0\.0\.1):[0-9]{2,5}$`, checked **before** any boto3 client is built; otherwise exit 2. | `rate_limit_waiver: local operator CLI; no untrusted caller` |
| `seed_dev_data.py` API base / emulator host | Loopback regexes per plan.md; otherwise exit 2. | `rate_limit_waiver: local operator CLI` |
| CLI arguments | `local_aws.py` subcommand ∈ {`validate-env`, `ensure-state-backend`, `seed-secrets`} via argparse choices. `dev-up.sh` accepts only `--rebuild`. `dev-down.sh` accepts only `--clean`. Unknown → usage + exit 2. | `rate_limit_waiver: local operator CLI` |
| The containerized API's HTTP surface | Not new. Existing contracts and two-tier limits are unchanged, so no new criterion is needed. | Existing two-tier limits |

## AC26 — iOS build configuration

- `Debug.xcconfig` sets `ORBIT_API_BASE_URL = http:/$()/localhost:8080` and
  `ORBIT_FIREBASE_AUTH_EMULATOR_HOST = localhost:9100`.
- `Release.xcconfig`:
  - leaves the emulator host **empty**;
  - carries Release's `ORBIT_API_BASE_URL` as the **pre-existing** `http://localhost:8001`
    literal, unchanged from today. This is **not** claimed as mitigated; E1/E3 replace it with the
    real HTTPS origin.
- `Info.plist` reads both via `$(…)`.
- **No ATS key is added.**
- `AuthFlowUITests.launchApp()` overrides only when the runner env provides `ORBIT_UITEST_*` (via
  `TEST_RUNNER_`).
- The Debug build succeeds, the `OrbitTests` unit suite is green, and `store-compliance.sh`
  reports critical = 0.

## AC28 — documentation checklist

1. **`docs/local-development.md`, written as a learning document.** It covers:
   - what each local piece stands in for (moto → AWS APIs; compose Postgres/Redis → RDS/ElastiCache; emulator → Firebase Auth; `migrate` → A2's migration function);
   - a host-vs-container port table;
   - the `docker compose --env-file .env.local` invocation rule and why;
   - native vs compose stacks and the **two emulator user stores**;
   - how Terraform state works here: local state first, then moto S3 with the **S3 native lockfile**. It covers the shared-fate property, `force-unlock`, and **why not DynamoDB, including the stated deviation from `iac-conventions`**;
   - the recovery-window lesson;
   - the `MOTO_IAM_LOAD_MANAGED_POLICIES` finding;
   - the account-guard probe outcome (Layer B claimed or unclaimed);
   - why moto, not LocalStack;
   - **Postgres: newest 16.x locally with major parity; prod still 16.6, bump owed to A2**;
   - **`dev-down.sh --clean` as the first thing to try when alembic misbehaves**;
   - the live-only gaps list;
   - the Release base URL being a pre-existing placeholder owed to E1/E3;
   - troubleshooting under the memory constraint.
2. **Updated files:** `CLAUDE.md` (how to run), `README.md` (quick start), `infra/README.md`, the new `infra/envs/local/README.md`, `ios/Orbit/README.md`, `docs/system_architecture.md` (local topology), `docs/mac-session-handoff.md` (new `TEST_RUNNER_ORBIT_UITEST_*` recipe, plus `docs/a1-run-start.md`'s durable pre-flight folded in), `docs/roadmap.md` (A1 entry), `scripts/README.md` and `tests/README.md`. Every compose command in them uses the `--env-file .env.local` form.
3. **`docs/a1-run-start.md` is deleted.** Its durable parts move per its own closeout instructions.
4. **`plans/A2-production-terraform-authoring.md` § Inherited from A1:**
   - rows 3 and 4 are resolved to their actual outcome;
   - **new owed rows are added:**
     - (A) bump `modules/data` `engine_version` 16.6 → a currently supported RDS 16.x;
     - (B) align the prod `backend.tf.template`/`backend.hcl.example` to `use_lockfile`, dropping `dynamodb_table`, and decide whether the E1 bootstrap still needs a lock table.

## Trace to PROJECT.md / CLAUDE.md "What done means"

| Done criterion | AC |
|---|---|
| Smoke passes | AC30 |
| Done-flow against the real API | AC27 |
| Ownership, bounded queries, validation | AC12 + AC30 (unchanged code, unchanged tests) |
| Security clean | AC32 (delegated), AC14, AC15 |
| Coverage ≥ 80% | AC30 |
| Docs + PR description | AC28, AC31 |
| Reduced-assurance stamp | AC26, AC27 |
| Perf p95 < 300 ms | **N/A this run.** No request-path change (plan.md OQ8, kept at the checkpoint). |
