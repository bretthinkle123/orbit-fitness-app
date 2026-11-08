# Local development environment

How to run Orbit end to end on one machine, what each local piece stands in for, what the
local stack **cannot** prove, and the numbers measured while building it. Written as a
learning document: it explains why things are the way they are, not just the commands.

Every number in this file was measured on the machine described below, on the date of the A1
run (2026-10-19 to 2026-11-07). Where a figure is a range, the range is the honest answer.
**There is no minimum-RAM figure in this document and none should be inferred from it.**

## The one-minute version

```sh
cp .env.local.example .env.local      # then replace every CHANGE_ME (openssl rand -hex 24)
scripts/dev-up.sh                     # builds the images, brings the stack up, seeds a dev user
# API: http://localhost:8080   Simulator: Debug build   stop: scripts/dev-down.sh
scripts/dev-down.sh                   # stop; volumes (Postgres data, emulator users) are kept
scripts/dev-down.sh --clean           # stop AND delete the volumes (full reset)
```

`dev-up.sh` is idempotent and convergent: every step can be repeated, and a run that failed or
was interrupted is fixed by running it again.

**Images.** Every run rebuilds the `api` image (`orbit-api:local`) before `migrate`, using
Docker's layer cache, so edits to `src/` or `migrations/` always reach both the migration and the
running API, and an unchanged tree rebuilds in seconds. It has to come first: the `migrate`
service only names that image (it has no `build:`), so without it Compose would try to pull
`orbit-api:local` from a registry and fail. The Firebase emulator image is built only when it is
missing. `scripts/dev-up.sh --rebuild` rebuilds **both** images with `--no-cache`, from nothing.
Use it when the cache is suspect or after editing `docker/firebase-emulator/`. It takes minutes
rather than seconds: in the 2026-11-08 measurements an uncached api build took 34 s to 165 s and
the emulator's `npm install` 13 s, and one earlier emulator build took about 7 minutes.

## Prerequisites

| Need | Why | How |
|---|---|---|
| Docker (Colima on the Mac) | runs the containers | `colima start` |
| **docker compose plugin** | `docker compose …` is a plugin, not part of the Docker CLI | `brew install docker-compose` (a host with only the `docker` formula has no `docker compose`) |
| **Terraform 1.11 or newer** | S3-native state locking needs 1.11; CI pins 1.15.9 | HashiCorp's binary or `brew` |
| **a venv with boto3 and requests** | `dev-up.sh` runs `scripts/dev/local_aws.py` and `scripts/seed_dev_data.py` from `.venv/bin/python` | `python3.12 -m venv .venv && .venv/bin/pip install boto3 requests` (a full `poetry install` also works) |
| `.env.local` | Postgres credentials and the dev user | copy `.env.local.example`; it is gitignored |
| `xcodegen`, Xcode | only for the iOS client | see `ios/Orbit/README.md` |

For the backend **pytest suite on Colima** you additionally need:

```sh
source .venv/bin/activate
PYTHONPATH=src TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock \
  pytest --cov=src --cov-fail-under=80
```

- `PYTHONPATH=src` because a venv synced with `poetry sync --no-root` does not install the
  `orbit` package itself, and `tests/conftest.py` imports `orbit.*`.
- `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock` because testcontainers' Ryuk
  helper otherwise tries to bind-mount Colima's host-side socket path and fails with
  "operation not supported", leaving the integration modules erroring at setup.

To give disk back to the host after heavy Docker work, run `colima ssh -- sudo fstrim -a`:
the Colima disk image is sparse and does not shrink by itself, so deleted images only free
host space after a trim. The machine this was built on ran at 90 to 93% disk throughout.

## What each local piece stands in for

| Local piece | Stands in for | Fidelity, honestly |
|---|---|---|
| **moto** (`motoserver/moto:5.1.22`, container `moto`) | the AWS APIs Terraform and the app call: Secrets Manager, SSM, KMS, CloudWatch Logs, IAM, S3, SNS | An SDK-level mock. It stores and returns what you give it. It does not enforce IAM or resource policies, and it keeps everything **in memory** |
| **compose `postgres`** (16.x alpine) | RDS PostgreSQL | Same major version as `modules/data`. It is plain Postgres: no multi-AZ, no `rds.force_ssl`, no RDS parameter group |
| **compose `redis`** (7.2.x alpine) | ElastiCache Redis | A rate-limit store only. 7.2 is the nearest real OSS release to the 7.1 ElastiCache runs (there is no OSS 7.1 image). Persistence is off |
| **`firebase-emulator`** (built in this repo) | Firebase Auth | The same emulator `firebase-tools` ships. Not a real project: no email delivery, no quotas, no real token signing keys |
| **`migrate`** (`alembic upgrade head`, compose profile `tools`) | A2's separate migration function | Same migrations; run by `dev-up.sh` before the API starts |
| **`api`** (`orbit-api:local`) | the Lambda function A2 will define | Plain uvicorn. No Lambda adapter; A2 adds the runner |
| **Terraform `infra/envs/local`** | `infra/` applied to AWS | The same modules, pointed at moto. `data` and `network` are not composed (see below) |

### Why moto, not LocalStack

LocalStack ended Community-edition support on 2026-03-23 and now requires an auth token merely
to start; its remaining free plans are non-commercial only. Orbit is proprietary and has a
monetization phase, so the free tier does not legitimately apply, and the briefs all say
"cost $0". moto is Apache-2.0 and needs no account. The trade is fidelity: moto has no
`tflocal` wrapper (every AWS provider endpoint is set explicitly) and several LocalStack
capability claims in older briefs were never re-verified against it.

### Why `envs/local` composes only four modules

`app_identity` + `secrets` + `observability` + `data_keys`. Not `data`, because RDS and
ElastiCache are compose containers here; not `network`, because VPC, security groups and NAT
have no local equivalent. The KMS keys were split out of `modules/data` into `modules/data_keys`
so they can still be created against moto. The rule throughout: **split a module, never fork
it**. Local differences are module variables (`recovery_window_in_days`) or provider
configuration, never a second copy of a module.

## Ports: host versus container

Container ports stay canonical; only the host side moves. Every published port is bound to
`127.0.0.1`, and `dev-up.sh` aborts if `lsof` shows any of them listening beyond loopback
(checked on the Mac; Colima forwards loopback-bound publishes correctly, so no fallback was
needed).

| Service | Host (compose) | Container | Why the host port moved |
|---|---|---|---|
| `api` | **8080** | 8000 | 8000 is kept free for the pipeline smoke check |
| `postgres` | **5433** | 5432 | brew `postgresql@16` holds 5432 |
| `redis` | **6380** | 6379 | brew `redis` holds 6379 |
| `firebase-emulator` | **9100** | 9099 | 9099 is reserved for the test suite's own emulator |
| `moto` | **5001** | 5000 | macOS AirPlay Receiver (Control Center) holds 5000 |

Between containers the names are canonical (`postgres:5432`, `redis:6379`, `moto:5000`,
`firebase-emulator:9099`). The **native** (no-container) stack keeps its old ports: API 8001,
Postgres 5432, Redis 6379, emulator 9099.

## The `--env-file` rule, and why

Every compose command is written `docker compose --env-file .env.local …`, run from the repo
root. Inside the scripts that is one shell function, `dc()`.

`docker-compose.yml` interpolates `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` with
the **required** form `${VAR:?set VAR in .env.local}`. A command that forgets the env file
therefore fails immediately instead of interpolating blanks, which would make Compose think
postgres's configuration changed and try to recreate it with an empty password. Try it:
`docker compose config` with no `--env-file` exits 1 with "required variable POSTGRES_DB is
missing a value". `--env-file` was chosen over the COMPOSE_ENV_FILES variable because it
works on every Compose v2, is visible at every call site, and an exported variable silently
does nothing in a fresh terminal.

## Native stack versus compose stack, and the two emulator user stores

There are two complete ways to run the app locally and they do not share state:

| | Native stack | Compose stack |
|---|---|---|
| API | `uvicorn … --port 8001` | container on **8080** |
| Postgres / Redis | brew, 5432 / 6379 | containers, 5433 / 6380 |
| Firebase emulator | host `firebase emulators:start`, port **9099** | container, host port **9100**, volume `fbauth` |
| Secrets | `DATABASE_URL` env var | DSN fetched from moto Secrets Manager |
| Used by | the pytest suite (its own emulator fixture), the old Simulator recipe | `dev-up.sh`, the Debug iOS build |

**The two emulators have separate user stores.** A user registered against the emulator on
9099 does not exist on 9100 and vice versa. `dev-up.sh` seeds the dev user and the XCUITest
seeded user (`scripts/seed_ui_test_user.sh`) into the compose emulator. The container
emulator persists its users in the `fbauth` volume (exported on a graceful stop, imported on
start, under `/data/state`), so UIDs survive `dev-down.sh` and are wiped by `--clean`.

### Why the API gets its database password from moto

`DATABASE_URL` is deliberately absent from the `api` and `migrate` environments. The app then
falls through to the secrets facade (`get_secret`) for the secret named `orbit/database-url`, the same path production runs
(`resolve_database_url` → secrets facade → Secrets Manager). Locally the secret is written by
`scripts/dev/local_aws.py seed-secrets` (the out-of-band step prod does at deploy), never by
Terraform, so the password does not land in Terraform state. The facade caches a secret for
900 s, so after moto loses its state `dev-up.sh` restarts a running `api`.

## moto is in memory: state is rebuilt on every bring-up

Everything in moto, including the Terraform state bucket, the 20 Terraform-managed
resources and the seeded database secret, disappears whenever the moto container is
recreated or restarted. That includes changing its `mem_limit`. This is by design and
`dev-up.sh` copes: every run executes `ensure-state-backend`, `terraform init`, `apply` and
`seed-secrets`, and restarts `api` when it sees that moto was reset. Postgres data and
emulator users live in volumes and are unaffected.

## How Terraform state works here

`infra/envs/local` uses an **S3 backend on moto with S3-native locking** (`use_lockfile = true`,
no DynamoDB). `scripts/dev/local_aws.py ensure-state-backend` creates the one bucket
(`orbit-local-tfstate`, versioned, SSE-S3) because Terraform cannot create its own backend.

- **The lock.** Before a state-mutating operation Terraform writes
  `envs/local/terraform.tfstate.tflock` using an S3 conditional write (`If-None-Match: *`).
  A second writer gets `PreconditionFailed`, which Terraform reports as an
  "Error acquiring the state lock". The object is deleted when the operation ends.
  Proven in the A1 run, with a holder started as `sleep 40 | terraform apply -input=true` (the
  open-but-silent stdin keeps it waiting at its approval prompt):

  ```text
  while held:   bucket lists envs/local/terraform.tfstate and envs/local/terraform.tfstate.tflock
  terraform plan -lock-timeout=0s
    Error: Error acquiring the state lock
    Error message: operation error S3: PutObject, https response error StatusCode: 412 ...
    api error PreconditionFailed: At least one of the pre-conditions you specified did not hold
    Lock Info:  ID: b13dcaaa-4bdd-584f-7dc6-4c042f7d8fac  Operation: OperationTypeApply ...
  after the holder exited: only terraform.tfstate remains; plan runs again
  ```

- **Shared fate.** The state, its lock and the resources it describes all live in the same
  moto, so they vanish together. That is why a moto restart is harmless to Terraform: there is
  no stale state describing resources that no longer exist. (The one exception is a leftover
  local `errored.tfstate` after moto dies mid-apply; `dev-up.sh` removes it.)
- **`force-unlock`.** If a Terraform process is killed while holding the lock and moto is still
  up, `terraform -chdir=infra/envs/local force-unlock <LOCK_ID>` clears it (the ID is in the
  error message). In practice `dev-down.sh` then `dev-up.sh` is quicker.
- **Why not DynamoDB.** `dynamodb_table` is deprecated from Terraform 1.11, adds a resource to
  the chicken-and-egg bootstrap, and puts one more moto service in the critical path. The
  conditional-write lock was verified against moto 5.1.22. **This deviates from the project's
  `iac-conventions` guidance and from the prod template** (`infra/backend.tf.template` still
  describes S3 + DynamoDB); aligning prod is owed to A2 (see below).
- **The `recovery_window_in_days` lesson.** moto emulates Secrets Manager's recovery window, so
  `destroy` followed by `apply` fails with `ResourceExistsException` for the same secret name
  (the deleted secret is still "recovering"). `modules/secrets` therefore takes a
  `recovery_window_in_days` variable (default 30, AWS's own, so prod is unchanged;
  validated as 0 or 7 to 30) and `envs/local` passes 0. A variable, never a fork.

## The account-guard probes (never touch real AWS)

`envs/local`'s provider is pinned to moto in layers, each claimed only as far as a probe proved:

- **Layer A (always).** All nine service endpoints come from `var.moto_endpoint`, validated to
  `^http://(localhost|127\.0\.0\.1|moto):[0-9]{2,5}$`; the credentials are static dummies.
  - Regex probe: `plan -var moto_endpoint=https://example.com` fails validation. **Passes.**
  - **Probe 2**: with fake ambient `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` **and**
    `AWS_PROFILE` naming an *existing* scratch profile (different keys, another region, via
    scratch `AWS_SHARED_CREDENTIALS_FILE`/`AWS_CONFIG_FILE`), `plan` still targets moto.
    **Passes** (detailed exit 0 or 2).
  - **Probe 2-neg**: `AWS_PROFILE` naming a profile that does **not** exist makes the provider
    fail closed ("failed to get shared config profile") before any network call. **Passes.**
  - **Amendment (owner, 2026-10-20).** The plan originally wrote probe 2 with a nonexistent
    profile and expected success. That cannot succeed: the provider always loads the shared
    config, and an unknown profile is an error (setting `shared_config_files = []` does not
    change it). The pair above replaces it; the original wording is superseded, and the CI
    job (`local-stack`) runs the amended pair.
- **Layer B (claimed; the probe passed).** `allowed_account_ids = ["123456789012"]`, with
  `skip_credentials_validation` and `skip_requesting_account_id` left unset so the provider
  really compares the account moto's STS reports. A scratch `zz_probe_override.tf` with a
  different id makes `plan` fail with "AWS account ID not allowed: 123456789012". Layer B holds.

## The `MOTO_IAM_LOAD_MANAGED_POLICIES` finding

moto v5 does not load AWS-managed policies by default. Applying `modules/observability`
without the variable fails: `NoSuchEntity: Policy arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
does not exist or is not attachable`. The compose `moto` service and the CI service container
set `MOTO_IAM_LOAD_MANAGED_POLICIES=true`. Memory cost: moto went from about 40 MiB fresh to
about 88 MiB after the first IAM call (the policies load lazily), and about 216 to 243 MiB
after the full 20-resource apply. Not a significant line in a 3 GB VM.

## Postgres: newest 16.x locally, prod still 16.6

Local Postgres is `postgres:16.15-alpine` (multi-arch index digest, pushed 2026-09-21, the
newest 16.x whose digest was at least 14 days old). `tests/unit/test_local_stack_config.py::
test_postgres_major_matches_rds_engine_major` asserts the **major** (16) equals
`modules/data`'s `engine_version` major; the minor is deliberately not compared. `modules/data`
still says **16.6**, which A1 does not edit; bumping it to a supported RDS 16.x is owed to A2.

## The Firebase emulator image: no JDK

The Auth emulator is a **Node** process inside `firebase-tools`; there is no JVM in it. Java is
needed by the Firestore, Realtime Database and Storage emulators, none of which run here.
Earlier planning text called the emulator "the JVM" and the largest line in the memory budget:
that premise was wrong. Evidence: the container (base `node:24.20.0-trixie-slim`, `firebase-tools`
15.18.0, the CI pin) has no `java` binary; it starts healthy in about 9 s, answers
`/emulator/v1/projects/demo-orbit-test/config` with 200, accepts a `signUp`, and its process
list is only `docker-init` and `node … firebase emulators:start`. (The Mac itself has a Temurin
JDK, so running the emulator natively there proves nothing; the container run is the proof.)

One thing the container taught: the CLI exports state by replacing the export directory, which
fails when that directory is a volume's mount point ("Automatic export … failed"). The entrypoint
therefore exports to a subdirectory (`/data/state`) and the volume mounts at `/data`.

## Measured footprint

Machine: MacBook Air M2, **8 GB RAM**; Colima VM **4 CPU / 3 GB / 20 GB disk**; the host disk
ran at about 90 to 93% used. All figures are `docker stats --no-stream` unless noted.

### Per container

| Container | Idle / steady | Peak (cgroup `memory.peak`, includes page cache) | Final `mem_limit` | Earlier provisional cap |
|---|---|---|---|---|
| `api` | 99 to 112 MiB | 112.5 MiB | 192m | 384m |
| `migrate` (one-off) | not sampled | not sampled (same image as `api`) | 192m | 384m |
| `postgres` | 23 to 51 MiB | 85.3 MiB | 192m | 512m |
| `redis` | 3 to 12 MiB | 6.0 MiB | 64m | 64m |
| `moto` (managed policies loaded) | 216 to 243 MiB | 290.1 MiB | 448m | 512m |
| `firebase-emulator` | **125 to 158 MiB** in the stack; **292 MiB** idle when run standalone | 170.0 MiB in the stack | 448m | 512m |

How the limits were derived: observed peak × about 1.5, rounded up to a multiple of 32m. Two are
deliberately above that rule: `postgres` (default shared_buffers is 128 MB, so its peak under
write load exceeds an idle peak) and `redis` (its own `maxmemory` is 32mb). The emulator's limit
uses its standalone 292 MiB reading. The emulator's `docker stats` figure varies between 125 and
292 MiB depending on page cache and when it is sampled; report the range, not one number. The
five long-running containers total about 0.5 GiB at steady state.

### The Colima VM (`free -m`, 2898 MB total)

| State | used | free | buff/cache | available |
|---|---|---|---|---|
| nothing of ours running | 407 | 877 | 1797 | 2490 |
| whole stack up, after a small load | about 970 | 100 to 136 | about 2000 | about 1925 |

No container was OOM-killed and none restarted at any point.

### The Mac during the passing iOS done-flow (Simulator booted)

| Moment | free + inactive | swap used | load average |
|---|---|---|---|
| before the passing re-run | 2147 MiB | 4.5 GB | 2.07 |
| during the passing run | 1.1 to 1.5 GiB | 6.4 to 6.6 GB of 7.2 GB | 8 to 14 |
| during the **failed** first attempt | 0.95 to 1.3 GiB | 9.8 to 11.0 GB of 11 to 12 GB | 22 to 48 |

Containers during the passing run: `api` 102 MiB, `postgres` 30, `redis` 3, `moto` 216,
`firebase-emulator` 124.

### `dev-up.sh` wall time (no pass/fail budget; recorded only)

| Run | Script total | Wall |
|---|---|---|
| **image-less** (no `orbit-*` images, no build cache, volumes wiped; 2026-11-08) | 102 s | 104 s |
| **cold** (images present, volumes wiped with `dev-down.sh --clean`) | 48 s | about 50 s |
| **warm** re-run (Terraform apply: 0 changes; api image rebuilt from cache, 0 to 1 s; 2026-11-08) | 12 to 13 s | 14 to 15 s |
| after `dev-down` (volumes kept) then up | about 33 s | |
| after a moto restart / a mid-run moto kill | 33 s / 38 s | |
| fresh checkout, images cached, run 1 | | **20 min 35 s** |
| fresh checkout, after `--clean`, run 2 | | 41.7 s |

The 20 min 35 s outlier is **unexplained**: all containers were healthy within seconds, yet the
`docker compose up` step took 1020 s while the host load average was about 13. It did not
reproduce on the next run. It was not a first build either: those images were cached.

The image-less row is the real first run: the base images were present, but the `orbit-*` images
and the legacy builder's intermediate images were removed first (`docker image prune -f`;
`docker builder prune` reclaims nothing on the legacy builder). Of its 102 s, the `infra-up` step,
which built the emulator image (`npm install` 13 s), took 36 s and the uncached api build 34 s. Those builds depend on the
network: an earlier from-nothing emulator build took about 7 minutes. The warm row was 17 s
(about 19 s wall) before `dev-up.sh` rebuilt the api image on every run, and the cold row predates
that change; the cached rebuild adds 0 to 1 s.

Image sizes (`docker image ls`): `orbit-api:local` about 394 to 405 MB, `orbit-firebase-emulator:local`
695 MB.

## The iOS Simulator against the stack

Debug builds point at the stack through committed xcconfigs (`ios/Orbit/Config/`): API base URL
`http://localhost:8080`, emulator host `localhost:9100`. Release keeps the **pre-existing**
placeholder `http://localhost:8001` and an empty emulator host (the emulator wiring is also
compiled out of Release). That Release URL is a placeholder owed to E1/E3, which replace it with
a real HTTPS origin; it is flagged, not fixed, and not claimed to be protected against anything.
No App Transport Security exception was needed or added (ATS does not apply to localhost here;
no NSURLError -1022 was observed). Native-stack recipe: `docs/mac-session-handoff.md`.

**A Debug build only works against the compose stack.** Debug points the app at API
`http://localhost:8080` and the Auth emulator at `localhost:9100`, so it cannot sign in unless
`scripts/dev-up.sh` is running on the same Mac. On a **physical device** `localhost` is the phone
itself, and the stack's ports are bound to the Mac's `127.0.0.1` only, so a Debug build on a
device cannot sign in at all. This is by design. To point a Debug launch elsewhere, set the
process-environment keys `OrbitAPIBaseURL` and `OrbitFirebaseAuthEmulatorHost`, which take
precedence over the xcconfig. Set both, or auth bypasses the emulator you meant. Set them in
Xcode under Edit Scheme > Run > Arguments > Environment Variables, or with `SIMCTL_CHILD_` for
`xcrun simctl launch`, or with `TEST_RUNNER_ORBIT_UITEST_*` for UI tests. The native-stack
recipe in `docs/mac-session-handoff.md` uses exactly this.

### The done-flow acceptance, and what it took

`SmokeUITests.testFullSmokeChainAgainstTheRealAPI` (register, quick-add food, toggle a set, log
weight, switch palette and units across a relaunch, delete the account) **passed on the iOS
Simulator against the containers**, and the `api` log showed `POST /me/bootstrap` 200,
`POST /fuel/entries` 201, `POST /train/sets` 200, `POST /weight` 201, `PATCH /profile` 200 and
`DELETE /me` 204. This is the in-run Simulator transcript plus API logs; the Swift side is
reduced-assurance and is never called gate-verified.

**History, as guidance.** The first attempt (seven runs) failed: iOS's "Use Strong Password?" and
"Save Password?" system sheets appeared later than the UI-test helpers wait and swallowed input,
while the Mac was swapping 10 to 11 GB with Chrome, Discord, Spotify, Creative Cloud and VS Code
resident. (Two of the seven were self-inflicted: passing `CODE_SIGNING_ALLOWED=NO`, which
removes the keychain entitlement Firebase Auth needs. Do **not** pass it to `xcodebuild test`.)
The re-run passed first time after those apps were quit. **Close heavy apps before Simulator
work against the stack**, boot the Simulator and let it idle about 30 s first, and if a single UI
test fails on a wait expiry re-run it alone before calling it a regression.

## Troubleshooting

- **Alembic or the database misbehaves:** run `scripts/dev-down.sh --clean` then `scripts/dev-up.sh`
  first. It deletes the Postgres and emulator volumes and re-migrates and re-seeds from nothing,
  which is almost always faster than diagnosing a half-migrated dev database.
- **`docker compose` says a required variable is missing:** you forgot `--env-file .env.local`.
- **A host port is in use:** `dev-up.sh` names the process and pid. brew's Postgres (5432) and
  Redis (6379) are not in the way; they are not published ports of this stack.
- **`terraform` complains about the backend or a missing bucket:** moto was restarted; re-run
  `scripts/dev-up.sh` (it recreates the bucket first).
- **The API cannot read its DSN after moto restarted:** re-run `dev-up.sh`, which re-seeds the
  secret and restarts `api`; the facade caches secrets for 900 s.
- **Memory pressure** (the binding constraint on this machine): never raise Colima's memory
  (6 GB on an 8 GB host starves macOS, Xcode and the Simulator). Shut the Simulator down during
  backend work (`xcrun simctl shutdown all`), do not run the pytest suite while the stack is up,
  close other heavy apps, and measure before tuning: `docker stats --no-stream`, vm_stat,
  `sysctl vm.swapusage`, `uptime`. Changing a service's `mem_limit` recreates it (and moto loses
  its state, which `dev-up.sh` rebuilds).
- **pytest errors at setup on Colima:** see the two environment variables under Prerequisites.

## What local cannot prove (live-only gaps)

None of the following is claimed by any A1 acceptance criterion. Each is **owed to E1/E2**
(the real-AWS runs) and is never faked locally.

- **IAM enforcement.** moto does not evaluate IAM or resource policies. The log-group
  delete-deny policy in `modules/observability` would block the destroy in real AWS; locally the
  destroy succeeds (`dev-down.sh` prints this caveat).
- **VPC, security groups, NAT and private networking.** `modules/network` is not applied locally.
- **Real RDS and ElastiCache behaviour:** multi-AZ failover, `rds.force_ssl`, parameter groups,
  encryption at rest, backups, ElastiCache transit encryption.
- **Lambda behaviour:** cold start, concurrency, VPC attachment. A1 ships a plain uvicorn image.
- **The front door and WAF.**
- **Alarm to SNS delivery**, and **CloudWatch log delivery** (log groups exist in moto, but
  nothing ships the app's logs to them).
- **Service quotas and eventual consistency**, which moto does not model.

## Accepted-risk scanner entries (`.trivyignore`)

The API image scan (HIGH and CRITICAL, gating) is clean with 26 CVE ids listed in
`.trivyignore`, in two groups:

- **20 with no fixed version available** in the Debian base (status affected, fix_deferred or
  will_not_fix): 15 triaged 2026-10-20 and 5 owner-accepted 2026-11-08 (sqlite
  `CVE-2026-119373`/`119374`/`119379`, zlib1g `CVE-2026-76844`/`85091`). Each carries a dated
  reason and a revisit-by date (2026-11-20 or 2026-12-08).
- **6 temporary cooldown exceptions** (owner-accepted 2026-11-08) that DO have a fix, still
  inside the 14-day dependency cooldown: pyasn1 `CVE-2026-119194` to `119197` (fix 0.6.5,
  eligible 2026-11-10T06:33Z) and `CVE-2026-84782` (openssl/libssl3) plus `CVE-2026-109518`
  (apt) (fix in base `python:3.12.16-slim-bookworm`, eligible 2026-11-19T17:07Z). These are
  not no-fix waivers; see "Owed to A2" row C.

The 14-day rule itself is unchanged. Fixable findings are otherwise fixed by bumping the base
digest, never ignored.

**Flag for re-review before E1:** `CVE-2026-84782` (HIGH, `libssl3` and `openssl`) is **reachable
through Python's `ssl` module**; it is an accepted risk only until the base-digest bump. The
CRITICAL `CVE-2023-45853` (zlib, will_not_fix) and `CVE-2025-7458` (sqlite) remain no-fix. The
emulator image is scanned advisory only (21 HIGH/CRITICAL at the time of writing, 19 with a
fix); it is a local-only dev image.

## Owed to A2

Recorded in `plans/A2-production-terraform-authoring.md` § Inherited from A1:

- **A.** Bump `infra/modules/data` `engine_version` from 16.6 to a currently supported RDS 16.x.
- **B.** Align the prod remote-state template (`infra/backend.tf.template`,
  `infra/backend.hcl.example`) to `use_lockfile = true`, dropping `dynamodb_table`, and decide
  whether the E1 bootstrap still needs a lock table (A1's answer for local: no).
- **C.** Clear the temporary cooldown exceptions (owner-accepted 2026-11-08). Bump `pyasn1` to 0.6.5 on/after 2026-11-10T06:33Z. Bump the base digest to `python:3.12.16-slim-bookworm` `sha256:935c3c5b…` on/after 2026-11-19T17:07Z. Then delete the 6 `.trivyignore` lines under "FIX EXISTS — blocked by 14-day cooldown" and the pyasn1 `xfail` in `tests/unit/test_dependency_cve_floors.py`.
- Rows 3 and 4 (remote state; Terraform against an emulator) are resolved to A1's actual outcome:
  remote state landed on moto with S3-native locking; Terraform reconciles cleanly against moto
  (idempotent plan, destroy and re-apply).
