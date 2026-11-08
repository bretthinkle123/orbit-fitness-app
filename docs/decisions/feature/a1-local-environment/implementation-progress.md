# Implementation progress (A1) - terse working state

## T1 (in progress)
Verified assumptions (this session):
- terraform v1.15.9 (>=1.11 OK for use_lockfile later).
- :5000 held by ControlCenter (lsof), :5001 free. 
- moto 5.1.22 multi-arch INDEX digest (registry API, sha256 of index body == Docker-Content-Digest):
  sha256:1e3802c95726373544967b428201c548f0247c15b00db2d96a5ba0a77d8643b8
  (`docker buildx` is NOT installed on host; used registry API via curl instead.)
- ENV GAP: `docker compose` plugin was NOT installed on host (only docker CLI). Installed
  `brew install docker-compose` (5.6.0, no deps) + symlink ~/.docker/cli-plugins/docker-compose.
  Host change outside repo; reversible (`brew uninstall docker-compose; rm ~/.docker/cli-plugins/docker-compose`).
Done so far: docker-compose.yml (moto only), .gitignore additions, modules/secrets recovery_window_in_days,
 modules/app_identity (+ root repoint + moved block), infra/envs/local/{versions,variables,providers,main,outputs}.tf,
 .env.local created (gitignored, random POSTGRES_* values).
NEXT: compose up moto -> confirm /moto-api/ health -> lock file -> terraform cycle -> guard probes -> infra-validate -> pytest.

T1 evidence so far (transcripts in .pipeline/a1-evidence/t1-*.txt):
- moto /moto-api/ EXISTS in 5.1.22 (200 via host :5001 and in-container) -> healthcheck uses it (no TCP fallback needed).
- Cycle on provider 6.52.0, local backend, skip_credentials_validation/skip_requesting_account_id UNSET: apply (9 added) ->
  plan -detailed-exitcode 0 -> destroy -> apply -> destroy ALL clean. No module fork needed.
- Regex probe: FAILS validation as required.
- Probe 1 (Layer B): plan fails "AWS account ID not allowed: 123456789012" -> Layer B CLAIMED (holds).
  zz_probe_override.tf gitignored (.gitignore:272), removed after.
- Probe 2 AS WRITTEN (AKIA... + nonexistent AWS_PROFILE) does NOT succeed: "Error: loading configuration: failed to get
  shared config profile, nonexistent-probe" (fails CLOSED before any network call). shared_*_files=[] doesn't help.
  Variants that DO succeed vs moto (exit 2 = changes pending): 2a env keys only; 2b AWS_PROFILE=existing profile w/ other
  creds+region; 2c AWS_ENDPOINT_URL* envs -> example.com; 2d AWS_REGION. => static creds + explicit endpoints win; only a
  NONEXISTENT profile errors. Reported to orchestrator as plan deviation (probe 2 wording/CI step need amendment).
NEXT: infra-validate.sh, pytest, smoke, compose down, surface-delta.

T1 done: docker-compose.yml, .gitignore, infra/modules/{secrets,app_identity}, infra/{main,outputs}.tf, infra/envs/local/*.tf + lock; next T2.
- infra-validate.sh exit 0; root plan shows recovery_window_in_days=30 x2, app_identity role created (no state => moved is no-op).
  Hook also added the darwin h1 hash to infra/.terraform.lock.hcl (byproduct, harmless).
- AC6 out-of-range (3) fails validation; only modules/secrets/main.tf declares aws_secretsmanager_secret.
- pytest: 142 passed, 97.61% cov - ONLY with env: `PYTHONPATH=src` (orbit pkg not installed in venv; poetry --no-root sync)
  and `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock` (colima: ryuk docker.sock mount fails otherwise).
  Without both, 87 integration tests ERROR at setup. (Pre-existing env facts, not caused by T1.)
- smoke-check PASS; moto stopped+removed; :8000 free; no dangling images/containers.

T2 done: infra/modules/data_keys/{main,variables,outputs}.tf (new), modules/data (keys removed; vars rds_kms_key_arn/redis_kms_key_arn;
 aws_account_id var removed as now unused; db_kms_key_arn output removed; engine_version untouched), infra/main.tf (data_keys + 4 moved blocks),
 infra/envs/local/{main,outputs}.tf (observability + data_keys), docker-compose.yml unchanged (flag already there from T1); next T3.
- Finding PROVEN: without MOTO_IAM_LOAD_MANAGED_POLICIES apply fails "NoSuchEntity: Policy arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess does not
  exist or is not attachable" (t2-apply-noflag.txt). With flag: 20 added incl. app_xray_write; plan no-op exit 0; destroy/apply/destroy clean.
- moto memory (docker stats --no-stream, t2-moto-memory.txt): flag OFF 167.9MiB after (failed) apply; flag ON: 39MiB fresh, 88MiB after first IAM call
  (managed policy load ~ +48MiB), 215.6MiB after full 20-resource apply, 199MiB after 3 cycles. Not a significant line vs. the 3GB VM.
- Probes re-run: probe 1 still fails w/ "AWS account ID not allowed"; probe 2 literal still fails closed (nonexistent profile); variant 2b succeeds. Not changed.
- Checkov: infra 143 pass/0 fail/35 skip; envs/local 86/0/15. infra-validate 0; engine_version diff vs main empty; pytest 142 pass 97.61%; smoke PASS.
- moto stopped, no containers/dangling images, :8000 free.

T3 in progress: wrote scripts/dev/{__init__,local_aws}.py, .env.local.example, tests/unit/test_dev_scripts.py, test_local_stack_config.py,
 infra/envs/local/{backend.tf,backend.moto.hcl}. NOTE honest sequencing: local_aws.py was written BEFORE its tests (not strict red-first); backend
 test was red (file absent) then green. Unit tests green. NEXT: compose up moto, ensure-state-backend x2, init -migrate-state, cycle, lock proof, probes (amended pair).

T3 done: scripts/dev/{__init__,local_aws}.py, .env.local.example, infra/envs/local/{backend.tf,backend.moto.hcl}, tests/unit/{test_dev_scripts,test_local_stack_config}.py; next T4 (or T8 wiring).
- S3 backend LANDED (AC9 option a); no fallback needed. ensure-state-backend run twice: 2nd "unchanged". init -migrate-state -force-copy moved a real
  local state (20 resources) to s3://orbit-local-tfstate/envs/local/terraform.tfstate (55KB); plan after = no changes.
- Remote cycle: destroy/apply/destroy/apply clean; plan no-op exit 0.
- LOCK PROOF (t3-lock-*.txt): holder = `sleep 40 | terraform apply -input=true &` (worked as documented). While held: bucket listing shows
  envs/local/terraform.tfstate.tflock; concurrent `plan -lock-timeout=0s` exit 1 "Error acquiring the state lock ... PreconditionFailed (412)" with holder Lock ID.
  After holder exit (EOF at prompt): .tflock gone, plan works.
- Guard probes under remote backend (t3-guard-probes-remote-backend.txt), AMENDED pair per owner: regex FAIL ok; probe 1 FAIL "AWS account ID not allowed";
  probe 2 (fake ambient keys + existing scratch profile via scratch AWS_SHARED_CREDENTIALS_FILE/AWS_CONFIG_FILE) plan SUCCEEDS (detailed exit 2 = changes pending);
  probe 2-neg (nonexistent profile) fails closed "failed to get shared config profile". FOR T8: CI must accept plan -detailed-exitcode 0 OR 2 as success; create scratch
  profile files with mktemp; not yet wired (T8).
- Pytest 209 passed (67 new unit), cov 97.61% (scripts/ not in --cov=src); infra-validate 0; checkov envs/local 86/0/15; smoke PASS; moto down, no state files, :8000 free.
- Caveat: moto is in-memory, so after a compose restart the bucket is gone; `terraform init` against s3 backend then fails until ensure-state-backend runs (T7's dev-up must order that).

T4 in progress: tests appended to tests/unit/test_local_stack_config.py (RED first: 8 failed), then Dockerfile, .dockerignore, build-provenance.yml gate -> tests green.
 Base: python:3.12.14-slim-bookworm index sha256:392307d2...23564e (pushed 2026-09-19, 31d). Newest 3.12.15 (34386ef0..., pushed 2026-10-06T11:07Z) was 13d18h old at
 2026-10-20T04:57Z => NOT >=14d yet (eligible ~2026-10-20T11:07Z). Index confirmed multi-arch (amd64/arm64/...).
 Tools absent on host: hadolint, trivy, buildx (use docker run hadolint/hadolint; trivy via ~/.claude/hooks/trivy-scan.sh). Legacy builder: COPY --from/--chown OK, no RUN --mount used.

T4 done: Dockerfile, .dockerignore, .github/workflows/build-provenance.yml (gate: -f Dockerfile AND vars.DEPLOY_ENABLED via env), .trivyignore (+16 unfixed CVE ids), tests/unit/test_local_stack_config.py (+8 tests); next T5.
- Build: legacy builder OK (no buildx needed), 39s, context 418kB (allowlist works). Image arm64, `docker image ls` size 394MB (397MB first build before pip removal). Wheels resolve w/o compiler (slim has none; build ok).
- Canary: .env.local + .pipeline + .git present on host -> `ls -a /app` = .venv alembic.ini migrations src; find for .env*/.git/.pipeline/*.tfstate = none. uid 10001, no poetry, no pip, `import orbit.main` ok.
- AC22 image half: canary POSTGRES_PASSWORD occurrences in docker history --no-trunc / inspect / save = 0/0/0.
- Standalone run: /health 200, health=healthy, IDLE MEM 90.2 MiB (docker stats --no-stream), CPU 0.3%.
- hadolint (docker run hadolint/hadolint): clean exit 0.
- Trivy (HIGH,CRITICAL): first scan 75 findings = 63 unfixed (16 unique CVE ids, Debian) + 12 fixable. Python 4 were pip's VENDORED urllib3/msgpack/setuptools copies ->
  removed pip/setuptools/wheel from images (real urllib3 2.8.0 / msgpack 1.2.1 are fine) -> gone. 16 unfixed ids put in .trivyignore with dated reasons.
  REMAINING (open, AC14 not yet 0): 8 FIXABLE Debian findings (perl-base 5.36.0-7+deb12u3->u4 x7, libpcre2-8-0 ->deb12u2) in base 3.12.14 digest.
  Base python:3.12.15-slim-bookworm (index sha256:34386ef0...a07258, pushed 2026-10-06T11:07Z) fixes them: probe build with that digest -> Trivy exit 0 (t4-trivy-probe-3.12.15.txt).
  But it is only 13d18h old at 2026-10-20T04:57Z (<14d rule); eligible after 2026-10-20T11:07Z. Dockerfile left on 3.12.14 (rule-compliant). Fix = replace digest in the 2 FROM lines + header comment, re-scan.
- Tests 217 pass 97.61% cov; smoke PASS; no containers (ryuk self-exits), :8000 free; removed hadolint image, trivy-cache volume, 3.12.15 probe image. Disk 15G free (Colima sparse disk file doesn't shrink).

T5 in progress. FACT CORRECTION: host DOES have Java (/usr/bin/java -> Temurin 21.0.12), contrary to the "no Java on host" premise, so the host-native emulator
 working is NOT evidence that no JRE is needed; only the in-container no-JRE start counts. Host firebase-tools is 15.27.0 (CI pin 15.18.0); ~/.cache/firebase/emulators absent.
 Base: node:24.21.0-trixie-slim (pushed 2026-10-06T05:40Z) is 13d23h old at 05:06Z -> NOT eligible; newest >=14d = node:24.20.0-trixie-slim index sha256:50c3b2f6...e55ae0 (2026-08-27).

T5 done: docker/firebase-emulator/{Dockerfile,firebase.json,entrypoint.sh}, tests/unit/test_local_stack_config.py (+6 tests, red first: 6 failed -> 17 pass); next T6.
- Base node:24.20.0-trixie-slim@sha256:50c3b2f6...e55ae0 (index; amd64/arm64), firebase-tools 15.18.0 (== pipeline-ci.yml), NODE_OPTIONS=--max-old-space-size=192, USER node.
- JDK DECISION BY EVIDENCE: NO JRE needed. In-container start with no Java: healthy in ~9s, /emulator/v1/projects/demo-orbit-test/config -> 200, signUp OK, process list
  (/proc) = docker-init + node firebase only; 0 java processes; no java binary. (t5-no-jre-start.txt, t5-signup-memory.txt, t5-persistence.txt)
  CORRECTION: host DOES have Java (Temurin 21), so host-native evidence proves nothing; the container run is the proof. CI comment about an Auth "JAR" is inaccurate for the Auth emulator
  (no ~/.cache/firebase/emulators on host; nothing downloaded in container).
- MEMORY: emulator idle 291.9-293.5 MiB, after signUp 292-293.8 MiB (docker stats --no-stream; pids 12, cpu ~0.1%) with heap cap 192. Image size 695MB (docker image ls).
  => "JVM emulator is the largest single line" premise is WRONG for Auth-only: it is a Node process ~0.29GiB (still the largest line vs moto ~0.2GiB, api 0.09GiB).
- DEVIATION (found by test): exporting to the volume ROOT fails ("Automatic export to /data failed" - CLI replaces the dir, volume root is a mount point;
  evidence t5-persistence-FAILED-export-to-volume-root.txt). Fixed: state dir is /data/state (--import=/data/state, --export-on-exit=/data/state). Persistence proof:
  signUp localId 80lH2C... -> docker stop (export complete) -> start -> signInWithPassword same localId (t5-persistence.txt). T6 compose must mount fbauth:/data (not /data/state).
- Trivy advisory (OQ10, not gated): 21 HIGH/CRITICAL (os-pkgs 8 HIGH + 3 CRITICAL; lang-pkgs 10 HIGH), 19 fixable (t5-trivy-advisory-summary.txt).
- Host port 9099 never taken (ran on 127.0.0.1:9100). Cleanup: containers+volume removed, pruned, trivy-cache volume removed, fstrim -> 17G free. Suite 223 pass 97.61%; smoke PASS; :8000 and :9099 free.
- NOTE: legacy-builder cache for this image was lost once after rmi of a variant, so a rebuild re-ran npm install (~7 min). Avoid rmi of shared-layer scratch images.

T6 in progress: tests first (RED: 14 failed incl. compose/ports/pins/major/no-DATABASE_URL/memlimits/env-file, redact/seed, no_env_branches), then docker-compose.yml (full stack), local_aws.py
 seed-secrets/_redact_dsn/build_database_dsn, tests/unit/test_no_env_branches.py (AST-excluded docstrings), tests/integration/test_secrets_facade_moto.py -> unit tests green (134).
 Pins: postgres:16.15-alpine@sha256:721873c3...80ea (pushed 2026-09-21, index multi-arch; newest 16.x >=14d), redis:7.2.16-alpine@sha256:29e8589c...6ca0 (2026-09-21), moto 5.1.22 (2026-03-08).
 NEXT: stack-up proofs (config w/o env file fails, secrets path, loopback lsof, measure), then integration test + full suite with stack DOWN.

T6 done: docker-compose.yml (full stack), scripts/dev/local_aws.py (+seed-secrets, _redact_dsn, build_database_dsn), tests/unit/{test_no_env_branches.py,test_local_stack_config.py(+),test_dev_scripts.py(+)},
 tests/integration/test_secrets_facade_moto.py; next T7 (dev-up/dev-down/seed_dev_data).
- Proofs (a1-evidence/t6-*): `docker compose config` w/o --env-file exit 1 "required variable POSTGRES_* is missing"; with it exit 0. Secrets path: ensure-state-backend -> tf init/apply (20 resources) ->
  seed-secrets -> migrate (via moto DSN) -> api up; `exec api env | grep -c DATABASE_URL` = 0; signUp on :9100 then POST /me/bootstrap 200, GET /profile 200, no token 401.
  postgres container ID unchanged across repeated `up -d --wait api` (2d370d16...). Colima DOES forward 127.0.0.1-bound publishes; lsof shows all five on 127.0.0.1 only; no fallback needed.
  AC22: canary POSTGRES_PASSWORD count = 0 in image history, api inspect, api logs, moto S3 state object (55KB). src/orbit diff = 0 lines.
- FOOTPRINT (docker stats --no-stream, full stack steady, after load): api 99-101 MiB, firebase-emulator 152-158 (T5 standalone idle showed 292; stats variance, cache-sensitive), moto 216-243, postgres 23-31,
  redis 3.5-3.8; sum ~0.5 GiB. Colima VM (free -m, 2898 total): used ~970, free ~100-136, buff/cache ~2000, available ~1925. Mac: ~925MB free of 7168MB, swap shown in t6-footprint.txt.
  cgroup memory.peak since start (includes page cache): api 112.5, postgres 85.3, redis 6.0, moto 290.1, emulator 170.0 MiB. No OOM kills, 0 restarts.
  mem_limit = peak x1.5 rounded up to 32m: api 192, migrate 192, moto 448, emulator 448 (uses T5's 293 idle), postgres 192 (above rule: default shared_buffers 128MB), redis 64 (maxmemory 32mb). Old provisional: 384/384/512/64/512/512.
- IMPORTANT for T7: changing mem_limit RECREATED moto -> in-memory state gone (bucket, 20 TF resources, seeded secret); had to re-run ensure-state-backend + tf apply + seed-secrets + restart api (cache TTL 900s, "api restart" needed
  after re-seed). Emulator recreate kept users (fbauth volume). local_aws.py guard also applies to validate-env (needs AWS_ENDPOINT_URL set) per plan - dev-up must export it.
- Tests: 245 passed 97.71% cov (stack DOWN), integration moto test 5 passed; smoke PASS; :8000 free; stack down, volumes kept (pgdata, fbauth); fstrim -> 19G free.

AC14 CLOSED (T4 rework, 2026-10-20T16:54Z): registry re-check python:3.12.15-slim-bookworm index sha256:34386ef0...a07258 pushed 2026-10-06T11:08Z (>14d). Dockerfile both FROMs + header swapped; rebuilt orbit-api:local (60s);
 `trivy-scan.sh image --severity HIGH,CRITICAL --exit-code 1 orbit-api:local` exit 0 (t4-ac14-closed.txt); no-ignore scan = 16 unique ids, 0 fixable, all 16 already in .trivyignore (0 prunable; header notes re-verification). hadolint clean.
 Digest test is pattern-based (no value pinned) -> unchanged, 17 config tests pass. Emulator node base left at 24.20.0 (advisory OQ10): node:24.21.0-trixie-slim (index 173f1258...fb66, pushed 2026-10-06T05:40Z) IS now eligible (>14d); 24.22.0 (2026-10-14) not yet.

T7 in progress: tests first (RED: collection error then 1 fail), then scripts/seed_dev_data.py (+guards, check-before-insert), scripts/dev-up.sh, scripts/dev-down.sh -> unit tests green.
 Design notes: dev-up exports AWS_ENDPOINT_URL only per local_aws call; port preflight treats a listener as ours if the owning compose service is running; moto-restart detection compares moto StartedAt before/after infra-up -> restarts api.
 NEXT: evidence: cold run (after --clean), warm re-run, idempotency counts, interrupt/moto-restart convergence, down/up UID persistence, --clean, AC1 fresh clone, AC22 greps, then suite w/ stack down.

T7 done: scripts/dev-up.sh, scripts/dev-down.sh, scripts/seed_dev_data.py, tests (test_dev_scripts.py +seed tests, test_local_stack_config.py +script tests); next T8 (CI local-stack job incl. amended probe 2/2-neg).
- AC29 TIMING (dev-up own SECONDS / wall): COLD (images present, volumes wiped via dev-down --clean): 48s / 50.5s [infra-up 12, tf-state 4, tf-apply 21, migrate 3, api-up 7, seed 1]. WARM re-run: 17s / 18.7s [tf-apply 6 (0 changes)].
  After down/up (volumes kept): ~33s; after moto restart: 33s; after mid-run moto kill: 38s. Fresh-checkout run #1 (clone+venv, images cached): 20m35s wall, of which infra-up = 1020s UNEXPLAINED (all containers healthy within seconds; compose CLI stalled; host load avg ~13);
  fresh-checkout run #2 (after --clean) 41.7s wall, infra-up 6s -> the stall did not reproduce. No budget set; just recorded.
- AC1: fresh checkout (tracked+untracked-not-ignored files copied, because no commit of A1 exists yet) + .env.local: without .venv preflight fails with the fix command; after venv(boto3, requests) dev-up exit 0, /health 200 (t7-ac1-*). Clone deleted.
- AC2: counts before/after 2nd run equal (uid GxAiPv..., fuel 2, done_sets 2, weight 1); postgres container id unchanged; 0 "recreat" lines; 2nd apply "0 added, 0 changed, 0 destroyed" (t7-idempotency.txt).
- AC3(a): killed after loopback-assert, re-run completed (t7-ac3a*); (b) moto restart -> re-run created bucket+20 resources, restarted api (t7-ac3b*); extra: docker kill moto mid tf-apply -> run1 exit 1 (Failed to save state), run2 converged (t7-killmoto*).
- AC4: dev-down keeps volumes; dev-up -> same UID, 0 rows re-added, counts equal; --clean removes orbit-local_pgdata+fbauth; bad flags exit 2 (t7-ac4.txt). AC22: 0 password/token occurrences in all t7 transcripts (t7-ac22.txt). migrations diff = 0.
- BUGS found while proving (fixed): set -e + `[ ] && continue` as a function's last statement; SIGPIPE under pipefail from `| head -n 1`; lsof no-match exit 1 under pipefail; moto-restart detection via StartedAt missed a restart done before the run -> now keyed on ensure-state-backend "created bucket".
  errored.tfstate left by a mid-apply moto kill is removed by dev-up (stale by construction).
- Suite (stack down): 270 passed, 97.71% cov; smoke PASS; dev-up/dev-down round trip ok; fstrim run; :8000 free; no containers; volumes pgdata+fbauth kept (data from round trip).

T8 done: .github/workflows/pipeline-ci.yml (+160 lines, 0 removed: new job `local-stack` only), docker/firebase-emulator/Dockerfile (hadolint ignore=DL3066 for `USER node`, reasoned), .pipeline surface-delta; next T9 (iOS config) or T10.
- Job: ubuntu-latest, 25 min, permissions contents:read (job+top), no secrets, TF 1.15.9 (setup-terraform@dfe3c3f8...v4.0.1, wrapper off), moto service container (digest, MOTO_IAM_LOAD_MANAGED_POLICIES, 5001:5000). Steps: fmt, wait-moto, ensure-state-backend (venv+boto3==1.43.40),
  init/validate/plan, probe 0 (regex), probe 1 (not allowed), probe 2 (fake ambient keys + EXISTING mktemp profile; exit 0|2 ok) + probe 2-neg (nonexistent profile -> "failed to get shared config profile"),
  cycle (apply, plan -detailed-exitcode, destroy, apply, destroy), hadolint x2 (v2.15.1 digest), build both images, Trivy API gating (0.75.0 digest, honors .trivyignore) + emulator advisory (counts only), Checkov envs/local (3.3.24 digest), liveness (artifact + outcome check).
  Scanner pins: hadolint v2.15.1 2026-07-31, trivy 0.75.0 2026-10-01 (0.76.0 2026-10-14 too new), checkov 3.3.24 2026-10-06 (3.3.25+ too new at 2026-10-20T18:02Z).
- EXERCISED LOCALLY: YAML parses (pyyaml); actionlint (rhysd/actionlint:latest via docker): only 5 findings, all in PRE-EXISTING jobs at lines 146/159/194 (mutation/codeql stubs: if:false, shellcheck on a placeholder) - none in local-stack; additions-only diff vs main.
  Every `run:` step executed in order by a local runner (scratch copy, real moto from compose, same digest-pinned hadolint/trivy/checkov images, TF 1.15.9): ALL success; probes: regex fail ok, probe 1 "not allowed" ok, probe 2 exit 2 ok, probe 2-neg ok; cycle 20 added -> no changes -> destroy -> apply -> destroy;
  Checkov 100 passed/0 failed/17 skipped; Trivy API exit 0; emulator advisory 21 HIGH/CRITICAL; liveness negative (missing artifact) -> exit 1.
- FOUND by dry run: hadolint DL3066 (info) on emulator `USER node` failed the gate -> inline ignore with reason (first dry run kept as t8-local-dryrun-run1-hadolint-finding.txt).
- NOT EXERCISED (cannot): GitHub Actions itself (uses: steps, services-container lifecycle/networking, ${{ }} expression evaluation incl. steps.<id>.outcome [substituted by the runner], runner OS/arch = ubuntu amd64 vs this arm64, BuildKit vs legacy builder, hosted-runner docker.sock mount). NO CI RUN HAS HAPPENED. Branch protection: add `local-stack` after its first green run (PR note).
- Cleanup: dry-run dir removed, :ci tags + scanner images (checkov, trivy 0.75, hadolint, actionlint) removed (shared-layer :local images untouched), stack down, suite 270 pass 97.71%, smoke PASS, :8000 free, fstrim (20G free).

T9 in progress: tests first (RED: 5 failed in test_local_stack_config.py) then ios/Orbit/Config/{Debug,Release}.xcconfig, project.yml configFiles (existing configs only), Info.plist ($(ORBIT_API_BASE_URL) + OrbitFirebaseAuthEmulatorHost), OrbitApp.swift doc comment only, AuthFlowUITests.launchApp() opt-in overrides (TEST_RUNNER_ORBIT_UITEST_*) -> 35 config tests green, check_ui_test_identifier_consistency clean.
 NOTE: Info.plist header PROSE still contains the words "NSAppTransportSecurity key" (pre-existing SC-3 warning kept intact) so `grep -c NSAppTransportSecurity` = 1; the actual <key>NSAppTransportSecurity</key> count = 0 (asserted by test).
 NEXT: xcodegen generate, -showBuildSettings Debug/Release, xcodebuild build Debug + Release (iphonesimulator, no UI tests, no Simulator boot), store-compliance.sh, DerivedData size.

T9 done (iOS = reduced assurance; NOT gate-verified): ios/Orbit/Config/{Debug,Release}.xcconfig (new), project.yml configFiles on Orbit target (Debug+Release only; no third config), Resources/Info.plist, App/OrbitApp.swift (doc comment only), Tests/UITests/AuthFlowUITests.swift (launchApp opt-in), tests (+6 config tests, 5 red first). Next: T10 is the orchestrator's own phase (NOT started).
- Evidence (a1-evidence/t9-*): xcodegen generate ok. showBuildSettings: Debug ORBIT_API_BASE_URL=http://localhost:8080, ORBIT_FIREBASE_AUTH_EMULATOR_HOST=localhost:9100; Release ORBIT_API_BASE_URL=http://localhost:8001 and the emulator-host setting is ABSENT from showBuildSettings (Xcode drops empty xcconfig values; -json confirms key not present).
  BUILT products' Info.plist (authoritative): Debug OrbitAPIBaseURL=http://localhost:8080, emulator host localhost:9100; Release http://localhost:8001, emulator host "" (empty string). NSAppTransportSecurity entry absent in both.
  xcodebuild build Debug + Release (generic iOS Simulator, CODE_SIGNING_ALLOWED=NO): both BUILD SUCCEEDED. Release binary: 0 occurrences of "OrbitFirebaseAuthEmulatorHost"; Debug dylib: 2. store-compliance.sh critical=0. check_ui_test_identifier_consistency clean.
  Sizes: DerivedData (default location, nothing deleted) 4117 MiB -> 5285 MiB (+1.17 GB from the new Release config build); host disk 19G -> 17G free after fstrim.
  NOT RUN (per instruction): xcodebuild test OrbitTests, any UI test, any Simulator boot. `grep -c NSAppTransportSecurity Info.plist` = 1 only because the pre-existing SC-3 header prose names the key; the <key> element count is 0.
- Backend regression: 276 passed 97.71% cov, smoke PASS, :8000 free, stack down, no Simulator booted.

T10 in progress: dev-up ok (47s), stack up. Smoke run1 + run2 FAILED - ROOT CAUSE = MY HARNESS FLAG, not the app: I passed CODE_SIGNING_ALLOWED=NO (copied from T9 build-only), so the app has no keychain entitlement and Firebase Auth's register fails with
 "An error occurred when accessing the keychain..." (register-error label in the UI hierarchy of run2's xcresult). Run1 = wait expiry at the register screen (same unsigned build); run2 = home screen never reached. No API calls beyond /health in either window. Re-running WITHOUT CODE_SIGNING_ALLOWED=NO per tasks.md.
T10 smoke runs so far (all against containers, Debug xcconfig, no overrides): run1/run2 = unsigned harness flag (my CODE_SIGNING_ALLOWED=NO -> keychain error); run3/run4 = "Use Strong Password?" system sheet swallowing the password (submit Disabled) -> home never reached; run5 = got through register, bootstrap 200 + reads 200,
 then the iOS "Save Password?" sheet appeared late and covered the Fuel quick-add chip -> "not hittable". Same system-prompt-late class docs/mac-session-handoff.md describes; Mac under heavy pressure: load avg 22-48, swap 9.8/11.2 GB used, free+inactive ~1.0-1.2 GB, other heavy apps resident (Chrome, Discord, Spotify, Creative Cloud, VS Code) - NOT closed by me (user's apps).

T10 RESULT: AC27 NOT PROVEN - 7 SmokeUITests runs, all FAILED; no 6-request 2xx window obtained. Reduced-assurance: none of this is gate-verified. AC30 smoke-with-stack-up = PASS (t10-ac30-smoke-stack-up.txt). Stack now down, Simulator shut down, suite 276 pass 97.71%, smoke PASS, :8000 free, fstrim ran (20G free).
 Runs: 1+2 unsigned (my flag, keychain error) | 3+4 "Use Strong Password?" sheet ate the password | 5 "Save Password?" sheet covered the quick-add chip after register+bootstrap(200)+reads(200) | 6 failed at SmokeUITests.swift:70 (remaining-kcal wait, after bootstrap 200 + reads 200) | 7 failed at register (AuthFlowUITests:189).
 API 2xx seen in best runs (5,6): GET /catalog/quick-foods, POST /me/bootstrap, GET /fuel, GET /weight, GET /train, GET /body all 200. NEVER reached: POST /fuel/entries, POST /train/sets, POST /weight, PATCH /profile, DELETE /me (so 5 of the 6 required writes are UNPROVEN; only POST /me/bootstrap evidenced).
 No NSURLError -1022 observed (ATS contingency not triggered; no Debug-only plist added). Coverage-gap check: SmokeUITests' chain covers all six requests in design (register->bootstrap, quick-add->fuel entries, set toggle->train sets, weight, palette/units->PATCH /profile, delete account->DELETE /me); none beyond bootstrap executed.
 CAUSE (measured, not tuned around): Mac memory/CPU pressure. At run time: load average 22-48, swap 9.8-11.0 GB of 11-12 GB used (dynamic), free+inactive 0.95-1.3 GB; resident: Chrome (several helpers ~0.4-0.65 GB each), Discord, Spotify, Creative Cloud, VS Code, WindowServer 470M, Colima VM 3.1 GB. iOS system sheets (Strong Password / Save Password) appear late (>3-5 s helper timeouts in AuthFlowUITests) and intercept input - the exact failure class docs/mac-session-handoff.md documents. I did NOT quit the user's apps.
 Containers under real use (docker stats, Simulator booted): api 112 MiB, postgres 49-51, redis 12, moto 217, firebase-emulator 125 (t10-footprint-during-run*.txt) - no OOM, no thrash from compose.
 xcresult: failed bundles kept: run5 (83 MB), run6 (103 MB); others replaced by t10-summary-*.json (kb) to save disk. No passing xcresult exists.
 NEXT (needs owner/coordinator): close heavy apps (Chrome/Discord/Spotify/Creative Cloud/VS Code) per the operator sequencing, then re-run: scripts/dev-up.sh; boot "iPhone 17 Pro" (xcrun simctl bootstatus -b) and let it idle ~30s; xcodebuild test (NO CODE_SIGNING_ALLOWED=NO) ... SmokeUITests; capture api logs. Suggest also considering a wider timeout in dismissStrongPasswordSheetIfPresent/dismissSavePasswordPromptIfPresent (code change - not made, T10 is evidence-only).

T10 RE-RUN (2026-11-08T04:05Z, after the owner freed memory): AC27 PROVEN IN-RUN (reduced assurance; Simulator transcript + API logs, not gate-verified).
 Pre-run host: free+inactive 2147 MiB, swap 4.5 GB used, load 2.07, memory_pressure 54% free (t10-rerun-host-before.txt). After dev-up + sim boot the 1-min load spiked to ~48 (my own boot/compose), waited until <10 before starting.
 Run 1 of max 2: `xcodebuild test ... -only-testing:OrbitUITests/SmokeUITests` (signed, no CODE_SIGNING_ALLOWED=NO, no TEST_RUNNER_ overrides, no test-code edits) -> TEST SUCCEEDED, testFullSmokeChainAgainstTheRealAPI passed in 72.3s. No second run needed.
 API (t10-rerun-api-requests.txt): POST /me/bootstrap 200 (x2: register + relaunch), POST /fuel/entries 201, POST /train/sets 200, POST /weight 201, PATCH /profile 200 (x2: palette + units), DELETE /me 204 - all six 2xx. No NSURLError -1022 (ATS contingency not needed). No tokens/passwords in the extracted lines.
 Footprint during the passing run (Simulator booted): api 102 MiB, postgres 30, redis 3, moto 216, firebase-emulator 124; Mac free+inactive 1.1-1.5 GiB, swap 6.4-6.6 of 7.2 GB used, load 8-14 (t10-rerun-footprint-run1.txt, t10-rerun-host-after.txt).
 Advisory full OrbitUITests suite: NOT RUN - swap 88% used and load 8-14 during/after the smoke run did not look healthy enough; recorded as skipped, not a gate.
 xcresult: .pipeline/a1-evidence/smoke.xcresult (26 MB) + t10-rerun-summary.json; failed-run bundles deleted (summaries kept). AC30: smoke-with-stack-up PASS earlier (t10-ac30-smoke-stack-up.txt), stack-down smoke PASS now.
 End: Simulator shut down, dev-down ok (volumes kept), suite 276 pass 97.71%, smoke PASS, :8000 free, fstrim ran (20G free). T10 DONE.

T11 done: docs/local-development.md (new, measured figures only, no minimum-RAM figure), infra/envs/local/README.md (new), updated CLAUDE.md, README.md, infra/README.md, ios/Orbit/README.md, docs/system_architecture.md (§4a local topology + diagram), docs/roadmap.md (A1 built), docs/mac-session-handoff.md (folded pre-flight, TEST_RUNNER_ recipe, Simulator guidance, pipe-deadlock marked FIXED), scripts/README.md, tests/README.md, plans/A2 (rows 3,4 resolved; new A,B), scripts/mac-preflight.sh (comment now points at the handoff doc); docs/a1-run-start.md DELETED (working tree only; nothing committed or staged). check-doc-identifiers: no warnings for the new/edited A1 docs (remaining warnings are pre-existing, warn-only).
 Final regression (stack down, env vars set, venv untouched): pytest 276 passed, 97.71% cov; git diff main -- src/orbit = 0 lines; migrations diff = 0; engine_version untouched; infra-validate 0; terraform fmt ok; store-compliance critical=0; UI selector check clean; smoke PASS; :8000 free (t11-final-regression.txt).
 Security hand-off: .pipeline/surface-delta.md rewritten as the complete, consolidated delta (no new app input surface; mechanisms list; ASVS rows delegated to AC32; .trivyignore accepted risks incl. CVE-2026-84782 flagged for re-review before E1). pr-description.md NOT written (documentation stage).
 Diff vs plan Files-affected: all planned files present; planned-but-unchanged by design: infra/backend.tf.template + backend.hcl.example (A2 owes the alignment), tests/conftest.py, scripts/seed_ui_test_user.sh (reused unchanged). Extras not itemised in the plan: module files under infra/modules/{app_identity,data_keys}, infra/.terraform.lock.hcl (infra-validate hook adds the darwin hash).
IMPLEMENTATION COMPLETE (T1-T11). AC14 closed; AC27 proven in-run (reduced assurance); AC30 both halves PASS; AC28 docs written; AC32 delegated to security.
