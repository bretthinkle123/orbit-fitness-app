# Operator kickoff constraints — A1 (2026-10-19)

_Transcribed verbatim from the owner's kickoff messages by the orchestrator. Operator's own
words: input, never a gate. Where this file and requirements.md agree, requirements.md holds
the rationale; items here NOT in requirements.md (memory sequencing, honesty constraints,
footprint recording) are additive operator constraints planning must honor._

## Overrides of the brief (rationale in requirements.md)
- Emulator is moto, NOT LocalStack — LocalStack's free tier became non-commercial-only and
  Orbit is proprietary/monetized. Read every "LocalStack" in the briefs as "the local AWS
  emulator" and verify capability rather than inheriting the claim.
- A1 ships a PLAIN UVICORN image. All Lambda work is A2's (see A2 § "Inherited from A1").
- Compose host ports shift: Postgres 5433, Redis 6380, Firebase emulator 9100. Container
  ports stay canonical. 9099 is reserved for the test suite's own emulator fixture — do not
  take it.
- Terraform state: plain local backend first; S3+DynamoDB on moto as a later discrete step.
- CI: leave the 106 testcontainers integration tests alone; add ONE new job for
  terraform/hadolint/Trivy/Checkov.
- dev-up.sh idempotent and re-runnable; dev-down.sh preserves volumes, --clean wipes.
- No pass/fail dev-up time budget — measure and record only. Do not emit a perf.budget.

## Verified findings to honor (proven by spike, not assumed)
- aws_secretsmanager_secret needs recovery_window_in_days = 0 for envs/local, as a MODULE
  VARIABLE, never a fork. moto emulates the real recovery window, so destroy→apply otherwise
  fails with ResourceExistsException — which would break the idempotent dev-up decision.
- Module split: secrets + observability apply as-is; data MUST be split (IAM/KMS supported,
  RDS/ElastiCache are compose containers); network is excluded from envs/local entirely.
- Every AWS provider block needs all 8 endpoints set explicitly — moto has no tflocal.
- Firebase emulator image: build in-repo from a pinned base digest + pinned firebase-tools.
  No official image exists; do not adopt a community one.

## Honesty constraints
- iOS acceptance is proven IN-RUN on this Mac, not deferred to a later session.
- Live-only gaps (IAM enforcement, VPC/NAT, real RDS/ElastiCache behavior, Lambda cold
  starts, alarm→SNS delivery, quotas) are recorded, never faked locally.

## Environment (already done — do not redo)
- venv synced to poetry.lock. ACTIVATE IT FIRST: `source .venv/bin/activate`. Without it
  alembic won't resolve and every DB-backed integration module errors at setup.
- .pipeline/ bootstrapped; ASVS waivers 6.3.3 and 6.2.x recorded.
- .pipeline/smoke.env wired to src.orbit.main:app on :8000, SMOKE_STARTUP_WAIT=12.
- brew postgresql@16 (5432) + redis (6379) running; Colima running at 4 CPU / 3 GB on an
  8 GB host — memory is the binding constraint.

## MEMORY IS THE BINDING CONSTRAINT (verbatim)
8 GB host, 3 GB Colima VM, and A1 brings up api + postgres + redis + a JVM Firebase
emulator + moto simultaneously.

If compose thrashes or a container is OOM-killed:
- DO NOT raise Colima's memory. 6 GB on an 8 GB host starves macOS, Xcode and the
  Simulator and makes things actively worse. 3 GB is a deliberate ceiling, not an
  oversight.
- Instead reduce concurrent load: shut down the iOS Simulator during backend stages
  (`xcrun simctl shutdown all`), and don't run the integration suite while the full
  compose stack is up.
- The JVM emulator is the largest single line. If memory is the blocker, measure it first
  before blaming compose as a whole.
- Sequence the iOS acceptance work as its own phase, with compose up but the test suite
  idle.

Record the observed footprint (per-container memory at steady state, and dev-up.sh wall
time) in docs/local-development.md. Do NOT invent a minimum-RAM figure — measure and
report it, so the next machine inherits a number rather than a guess.

Pressure history: docs/mac-session-handoff.md traces UI-test wait-expiry flake on this
machine directly to disk/memory pressure. If a single UI test fails, re-run it alone
before treating it as a regression.

## Plan-checkpoint decisions (2026-10-20T02:52:57Z)
Owner reply to the orchestrator's recommendation audit: "go" — read as: adopt both recommended
changes, keep every other proposed default (OQ1–OQ10, OQ12, sts endpoint) as written.
- Postgres: local container pinned to the newest 16.x (digest >=14 days old) instead of the 16.6
  RDS-parity pin; infra/modules/data engine_version 16.6 bump recorded as owed to A2.
- OQ11: S3 backend uses use_lockfile (S3 conditional writes) instead of the deprecated
  dynamodb_table. Evidence: moto 5.1.22 rejects a second If-None-Match:* put_object with
  PreconditionFailed (orchestrator probe, 2026-10-19). Prod backend.hcl.example alignment owed to A2.
- S2 threat row wording: Release keeps today's http://localhost:8001 literal; do not claim it is mitigated.

## Orchestrator interventions (2026-10-20T03:03:18Z)
- plan-approved (approved_at 2026-10-20T02:52:31Z, plan_sha256 3aba8932…) was written by the owner
  BEFORE the owner-checkpoint revision 2; plan.md now hashes 902c2c60…. Marker moved to
  .pipeline/superseded/plan-approved.rev1 (un-approval only). Owner must re-run approve-plan.sh.
- .pipeline/smoke-status.json (pre-flight pass, 2026-10-19T06:20:05Z, predates run-started) moved to
  .pipeline/superseded/ — next-stage.sh treated it as implementation's smoke and routed to run:security.
- Driver defects to fix post-run: (a) ignores plan-audit revision_recommended; (b) trusts a
  smoke-status.json older than run-started; (c) plan-approved existence is not hash-checked against plan.md.

## Host provisioning during T1 (2026-10-20T03:18:32Z) — journaled, not an intervention
- implementation (T1) ran `brew install docker-compose` (5.6.0) and symlinked it to
  ~/.docker/cli-plugins/docker-compose: the host had no compose plugin (and no buildx). Revert:
  `brew uninstall docker-compose` + remove the symlink. Writes no pipeline artifact; changes no gate.
- Backend suite needs PYTHONPATH=src (orbit package not installed in venv) and
  TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock (Colima ryuk mount). With both:
  142 passed, 97.61% coverage. Passed to every later stage prompt; venv left untouched.
- OPEN (owner decision): AC8 probe 2 as written (AWS_PROFILE=nonexistent) fails closed before any
  network call; env-keys / existing-profile / AWS_ENDPOINT_URL variants all stay on moto.

## Post-approval amendment — AC8 probe 2 (2026-10-20T03:30:44Z, owner selection "Amend probe (Recommended)")
Supersedes plan.md/acceptance.md AC8 probe-2 wording (approved bytes left unchanged):
- Probe 2 (must SUCCEED against moto): ambient AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY set to fake values
  PLUS AWS_PROFILE naming an EXISTING scratch profile (scratch AWS_SHARED_CREDENTIALS_FILE/AWS_CONFIG_FILE)
  with different keys and region → `terraform plan` still targets moto.
- Probe 2-neg (must FAIL before any network call): AWS_PROFILE=<nonexistent> → "failed to get shared
  config profile". Kept as a fail-closed check.
- Applies to AC8 evidence, T8's CI local-stack job, and testing's AC8 coverage.

## T4 follow-ups (2026-10-20T05:05:53Z)
- AC14 OPEN, deferred (not waived, rule not relaxed): 8 fixable Debian HIGH/CRIT (perl-base, libpcre2-8-0)
  close with base python:3.12.15-slim-bookworm@sha256:34386ef0… which reaches the 14-day cooldown at
  ~2026-10-20T11:07Z. Orchestrator re-routes the digest bump to implementation after that time.
- Host provisioning: orchestrator ran `colima ssh -- sudo fstrim -av` (non-destructive; returns freed VM
  blocks to the host). Host free 15G → 19G. Repeat after image-heavy tasks.
- For owner review at diff checkpoint: .trivyignore accepts 16 no-fix CVEs incl. CRITICAL CVE-2023-45853
  (zlib1g), CRITICAL CVE-2025-7458 (libsqlite3), HIGH CVE-2026-84782 (libssl3/openssl, reachable via ssl).

## Correction (2026-10-20T05:29:16Z)
- Orchestrator's 2026-10-19 claim "no Java on host" was WRONG (java_home failed; /usr/bin/java is Temurin 21.0.12).
  The no-JRE conclusion stands on T5's in-container proof (0 java processes, healthy, signUp OK), not on host evidence.
- Measured: Auth emulator is a Node process, ~292 MiB idle — largest container, but not a JVM.

## T10 re-run (2026-11-08T04:04:56Z)
- First T10 attempt (2026-10-20): 7 SmokeUITests runs failed; runs 3–7 on late iOS password sheets under
  host memory pressure (swap 9.8–11 GB, load 22–48). AC27 NOT proven; AC30 stack-up half PASSED.
- Owner selection "I'll free memory first (Recommended)": owner quit Chrome, Spotify, Brave/others.
  Pre-run host: swap 4.55 GB, load 2.3, free+inactive ~1.9 GB, memory_pressure 51% free. No test-code changes.

## Security cycle-1 owner decisions (2026-11-08T04:33:31Z, pipeline-initiated escalation; option selections)
- ASVS 12.2.1 / 12.3.1 / 13.2.1: "Yes, I'll record them (Recommended)" — owner runs record-waiver.sh (TTY)
  x3, reason: "dev-only loopback stack, synthetic data; TLS/service auth at the A2/E1 front door".
- 5 new no-fix Debian CVEs (sqlite CVE-2026-119373/119374/119379; zlib1g CVE-2026-76844/85091):
  "Accept, dated (Recommended)" — add to .trivyignore under the existing no-fix rule (dated reason, revisit-by).
- gitleaks FP tests/unit/test_dev_scripts.py:14: "Reword the test value (Recommended)" — replace the literal with
  a non-key-shaped synthetic value; NO suppression marker. (Security's gitleaks:allow edit was blocked by the
  permission classifier; this is a different fix chosen by the owner, not a workaround of that block.)
- Semgrep INFO/WARNING nosemgrep markers (#17–19): not decided; non-blocking (CI Semgrep is --severity ERROR). Left reported-only.

## Cooldown decision (2026-11-08T04:42:07Z, pipeline-initiated escalation; owner selection "Temporary dated exceptions (Recommended)")
- 6 CVEs with fixes inside the 14-day cooldown are owner-accepted TEMPORARILY (the 14-day rule itself is unchanged):
  pyasn1 0.6.4 → 0.6.5 (CVE-2026-119194/119195/119196/119197; GHSAs CVSS 7.5) eligible 2026-11-10T06:33Z;
  base python:3.12.16-slim-bookworm sha256:935c3c5b… (openssl/libssl3 CVE-2026-84782, apt CVE-2026-109518) eligible 2026-11-19T17:07Z.
- Mechanism: owner records an OSV waiver for pyasn1 via record-waiver.sh (TTY); the 6 IDs go into .trivyignore marked
  "FIX EXISTS — blocked by 14-day cooldown; owner-accepted 2026-11-08; bump on <date>".
- Owed follow-ups (recorded in the A2 brief + PR): bump pyasn1 on/after 2026-11-10; bump base digest on/after 2026-11-19;
  then delete those 6 .trivyignore lines and the pyasn1 xfail in tests/unit/test_dependency_cve_floors.py.

## Orchestrator deviation from driver (2026-11-08T05:12:16Z)
- next-stage.sh emitted run:debugging:test (criteria gap: AC26 uncovered — OrbitTests never executed, no failing test).
  Orchestrator instead re-dispatched TESTING to execute `xcodebuild test -only-testing:OrbitTests` (no source edits),
  because the gap is an un-run suite, not a defect. Sent before reading the driver token (process slip, disclosed).
  If OrbitTests fails for a real reason, route to debugging per the driver. Driver gap to consider post-run: distinguish
  "criterion lacks evidence (re-test)" from "criterion fails (debug)".

## Diff-review pre-step decision (2026-11-08T05:25:35Z, owner selection "Fix now, bump pyasn1 later")
- /code-review (high) returned 10 findings. Orchestrator verified #1 (migrate runs on orbit-api:local before it is
  built; migrate service has no build:) — T7's AC1 "fresh checkout" evidence was masked by the cached image.
- FIX now: #1 build-before-migrate, #4 always rebuild api (stale code), #5 readiness busy-spin, #6 json-before-status,
  #9 machine-readable moto-reset signal; doc note for #3 (Debug→emulator breaks physical-device Debug; by design).
- KEEP (decided): #3 design, #7 false positive (requirements.md allows dev-only seed script).
- DEFER: #8 duplication cleanup, #10 duplicate Checkov/Trivy cache (CI tidy-up). #2 handled by pyasn1 bump round.
- Second round owed: pyasn1 0.6.5 on/after 2026-11-10T06:33Z, before merge.

## Loop re-entry (2026-11-08T06:07:45Z)
- Loop previously exited GREEN (status=completed, 3 cycles). Owner-directed code-review fixes changed the tree;
  orchestrator ran loop-guard reset (not a cap-out clear) and re-entered at run:security per the driver.

## Driver gap 4 (2026-11-08T06:12:14Z)
- After the code-review round the loop re-exited GREEN; next-stage.sh emitted checkpoint:diff because a (stale)
  pr-description.md existed from the pre-fix documentation run. Orchestrator re-ran documentation per skill 5b
  ("if the human acts on a finding, the tree changes -> re-run documentation + re-approve"). Driver should compare
  review-manifest reviewed_change_hash to the current tree before skipping documentation.
