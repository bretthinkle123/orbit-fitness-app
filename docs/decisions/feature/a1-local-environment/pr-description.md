# A1: one-command local environment (moto, Postgres, Redis, Auth emulator, containerized API)

Branch `feature/a1-local-environment`, base `main` at `ade7efe`. Plan and threat model: `.pipeline/plan.md` (retained at `docs/decisions/feature/a1-local-environment/plan.md`, with `acceptance.md` and `security-report.md` beside it).

> ## DO NOT MERGE YET: a second small round is owed first
> On or after **2026-11-10T06:33Z** a follow-up round must bump `pyasn1` to 0.6.5 and then remove the 4 temporary pyasn1 `.trivyignore` lines, the 2 strict xfails in `tests/unit/test_dependency_cve_floors.py`, and the owner's `pyasn1` OSV waiver. That clears CI's `osv` failure (see "MERGE BLOCKER" below). **This PR must not merge before that round.** The two base-image cooldown entries (openssl/apt) follow on or after 2026-11-19T17:07Z (A2 row C).

## Summary

- `scripts/dev-up.sh` / `scripts/dev-down.sh` bring a full local stack up and down: compose services `moto`, `postgres`, `redis`, `firebase-emulator` (built in-repo), `migrate` and `api`. `dev-down.sh` keeps volumes; `--clean` wipes them. Host ports: API 8080, Postgres 5433, Redis 6380, emulator 9100, moto 5001; all bound to loopback.
- New Terraform root `infra/envs/local` applies the shared modules to moto with an S3 backend using S3-native locking (`use_lockfile`). New modules `app_identity` and `data_keys` were split out (split, never fork); `modules/secrets` gained a `recovery_window_in_days` variable (default 30, so prod is unchanged).
- The API reads its database DSN through the unchanged secrets facade from moto Secrets Manager. No environment branches were added to app code (`tests/unit/test_no_env_branches.py`).
- iOS: Debug points at the stack through `ios/Orbit/Config/*.xcconfig`; Release keeps its pre-existing placeholder URL.
- `dev-up.sh` builds the api image on every run (layer cache; `--rebuild` means `--no-cache` for both images) in an `api-build` step that runs before `migrate`.
- CI: one new `local-stack` job in `.github/workflows/pipeline-ci.yml`; the existing integration tests are untouched.
- Docs: `docs/local-development.md` (image-less and warm timings, `--rebuild`, Debug-build note) (how it works, measured footprint, live-only gaps), `docs/system_architecture.md` section 4a, `infra/envs/local/README.md`, new READMEs for `docker/`, `docker/firebase-emulator/`, `scripts/dev/`, `infra/envs/`, `infra/modules/app_identity/`, `infra/modules/data_keys/`, `ios/Orbit/Config/`. The `.trivyignore` header and the accepted-risk section of `docs/local-development.md` were corrected in the documentation pass (cooldown CVEs are no longer described as no-fix).

## Assurance: REDUCED (swift adapters absent)

`run-summary.json` `.assurance` is `reduced (swift adapters absent)`. **The iOS portion is NOT gate-verified**; the deterministic gates analyzed little Swift. Treat the whole run as reduced-assurance for iOS until Swift gate adapters land. The iOS proof is:

- **AC27**: the in-run Simulator done-flow, `SmokeUITests.testFullSmokeChainAgainstTheRealAPI`, 1/1 passed on iPhone 17 Pro against the containerized API with no overrides; the API request log shows 2xx for bootstrap, fuel, sets, weight, profile and `DELETE /me` (evidence `t10-rerun-api-requests.txt`, `t10-rerun-summary.json`).
- **AC26**: the OrbitTests run. **Unreconciled counts:** the xcresult reports 208 tests (208 passed), while the XCTest log line says "Executed 50 tests, with 0 failures". Both show 0 failures; why they differ was not determined. Do not read either figure as the definitive test count.

## Acceptance criteria

32 total: **31 test-covered + 1 delegated to security** (AC32, reconciled by security: clean). Read from `test-results.json` `criteria_covered.by_id`. Composition caveats:

- **AC14 is "covered as amended"** by the owner cooldown decision: the criterion says fixable findings are never ignored, yet 6 fixable CVEs are ignored under temporary exceptions (see below). Disclosed in `test-results.json`.
- **AC8** is covered per the owner's probe-2 amendment, not the approved wording.
- **AC25**: the deploy gate requires the Dockerfile and `DEPLOY_ENABLED`; a **post-merge check on the `main` run is still owed**.
- **AC1** was re-proven on a genuinely image-less machine after code review found the earlier fresh-checkout proof was masked by a cached image (102 s).
- **AC3**: its convergence transcripts (interrupted run, moto restart, mid-apply moto kill) **pre-date the `api-build` step**. They are supported by the new stub-based tests (`test_dev_up_flow.py`) and the image-less and warm runs, but the interrupted-run and moto-restart scenarios were **not re-run on the new code**.
- AC27 and AC26 (carried forward; no iOS code changed in the review round) are proven by in-run Simulator evidence, not by a gate (see Assurance).

## Testing

- Hermetic suite: 335 tests, 335 passed, 0 failed, **2 strict xfails** (pyasn1 cooldown cases, intended; they expire 2026-11-10 and must be removed at the bump). 222 unit, 113 integration, 0 e2e. The code-review round added `tests/unit/test_dev_up_flow.py` (6, runs the real `dev-up.sh` against stub docker/terraform/lsof/curl), +3 and +9 in `test_dev_scripts.py`, and +2 in `test_secrets_facade_moto.py`; each was seen failing on the unfixed code first.
- Coverage (combined): **97.71% lines, 91.51% branches**.
- Perf: n/a (no budget; dev-up time recorded, not gated).
- **Test quality (advisory):** `quality_ok` is `false`; **mutation score unmeasured** (no mutation tool configured; the diff is mostly shell/HCL/YAML/Dockerfile). Adversarial gaps noted (from `test-quality.json`, written before the review round): `dev-up.sh`/`dev-down.sh` were proven only by run transcripts (`dev-up.sh` now has the stub harness); the AC9 state-lock probe is a one-off transcript; `test_local_stack_config.py` checks are text/regex over files, not parsed configs.

## Supply chain

- Lockfile: `poetry.lock` re-locked with no `pyproject.toml` change (intended CVE bumps: certifi, msgpack, pyasn1 left at 0.6.4 by the cooldown); security flagged it as a warning only.
- CycloneDX SBOM generated (`sbom.cdx.json`), 80 components.
- The CI `pip install boto3==...` step in `local-stack` has no `--require-hashes` (ASVS 15.2.4 hygiene, low, unresolved).

## /code-review round (high): 10 findings, owner chose "Fix now, bump pyasn1 later"

| # | Finding | Disposition |
|---|---|---|
| 1 | `migrate` ran before the api image was built (compose has `image:` and no `build:` there, so a machine without the image tried to pull it and failed; this masked AC1) | **Fixed.** New `api-build` step before `migrate`. Reproduced live first (pull access denied, exit 1) |
| 2 | pyasn1 CVEs (vulnerable pin held back by the cooldown) | **Handled by the pyasn1 round** owed on or after 2026-11-10T06:33Z |
| 3 | Debug builds point at the compose stack, so a physical-device Debug build cannot reach it | **Kept by design**; doc note added (`docs/local-development.md`, `ios/Orbit/README.md`) with the override path |
| 4 | A plain re-run served stale code (image built only if absent or with `--rebuild`; with `--rebuild` migrate still used the old image) | **Fixed.** `dc build api` on every run; `--rebuild` means `--no-cache` for both images |
| 5 | Readiness loop in `test_secrets_facade_moto.py` busy-spun on non-200 answers | **Fixed.** Extracted `_wait_until_ready`; sleeps on every miss |
| 6 | `seed_dev_data.py` parsed JSON before checking status | **Fixed.** Status first; only a 400 is parsed, tolerant of non-JSON bodies |
| 7 | Dev-only seed script in the repo | **Kept: false positive** (`requirements.md` allows a dev-only seed) |
| 8 | Duplication | **Deferred** (cleanup) |
| 9 | Moto-reset detected by grepping free text | **Fixed.** `ensure-state-backend --report` prints `state_bucket_created=<0\|1>`; anything else stops the run |
| 10 | Duplicate Checkov runs (one on unpinned `:latest`) and no shared Trivy cache in CI | **Deferred** (CI tidy-up) |

**Deviation from the approved plan:** `plan.md` section api-up still describes the old "build only if missing or `--rebuild`" behavior. It is the approved plan and was left unedited; the shipped behavior is the always-build described above.

## Owner decisions and waivers (recorded verbatim in `docs/decisions/feature/a1-local-environment/operator-kickoff.md`)

- **AC8 probe-2 amendment (2026-10-20):** the approved probe 2 (`AWS_PROFILE=nonexistent`) cannot succeed because the provider fails closed before any network call. Replaced by probe 2 (existing scratch profile, plan still targets moto) plus probe 2-neg (nonexistent profile fails closed).
- **Postgres 16.15 locally, prod still 16.6** (A2 row A): local pins the newest 16.x with a digest at least 14 days old; `modules/data` `engine_version` is untouched.
- **`use_lockfile` instead of DynamoDB** for local state (A2 row B): the prod template still describes S3 + DynamoDB and deviates from `iac-conventions` until A2 aligns it.
- **ASVS waivers** 12.2.1, 12.3.1, 13.2.1 (dev-only loopback stack, synthetic data; TLS/service auth at the A2/E1 front door), and the **OSV waiver `pyasn1`** (the waiver id is a package name, covering all 4 pyasn1 GHSAs at CVSS 7.5).
- **5 owner-accepted no-fix CVEs** added to `.trivyignore`, revisit-by 2026-12-08: sqlite CVE-2026-119373, -119374, -119379; zlib1g CVE-2026-76844, -85091. (Together with the earlier set, 20 no-fix ids are listed.)
- **6 TEMPORARY cooldown exceptions** (A2 row C): fixes exist but are inside the 14-day cooldown. pyasn1 CVE-2026-119194/-119195/-119196/-119197 (bump to 0.6.5 **on or after 2026-11-10T06:33Z**); CVE-2026-84782 (openssl/libssl3, reachable via Python `ssl`) and CVE-2026-109518 (apt) (move both `FROM` lines to base 3.12.16 `sha256:935c3c5b...` **on or after 2026-11-19T17:07Z**). Then delete the 6 `.trivyignore` lines, the pyasn1 xfail, and retire the OSV waiver.

## MERGE BLOCKER: CI `osv` job will fail (do not merge before the pyasn1 round)

CI's `osv` job reads only a committed `osv-scanner.toml`, **not** `waivers.json`, so it WILL fail on the 4 pyasn1 GHSAs (GHSA-2qm8-x737-gmw5, GHSA-9m75-vc3g-4x39, GHSA-fm9c-5rcf-2q5p, GHSA-mm57-4v3p-rchx). Either:

1. **(preferred)** bump pyasn1 to 0.6.5 on or after **2026-11-10T06:33Z**, or
2. the owner commits an `osv-scanner.toml` with `[[IgnoredVulns]]` entries and `ignoreUntil = 2026-11-10`.

## CI: `local-stack` job has never run on GitHub

Only a local dry run exists (actionlint and a local dry run; the dry run's first pass surfaced a hadolint finding, since fixed). The first GitHub run may surface amd64-only or runner-specific failures (AC5/AC8/AC18/AC24 depend on it). **Operator action:** after its first green run, add `local-stack` to branch protection.

## Measured footprint and dev-up times (machine: MacBook Air M2, 8 GB; Colima 4 CPU / 3 GB)

No minimum-RAM figure is claimed. Per container, steady state (`docker stats`): api 99-112 MiB; postgres 23-51 MiB; redis 3-12 MiB; moto 216-243 MiB (managed policies loaded); firebase-emulator 125-158 MiB in the stack, 292 MiB standalone. The emulator is a **Node process, not a JVM** (earlier planning text was wrong). Nothing was OOM-killed or restarted.

`dev-up.sh` (no budget; recorded only): **image-less cold 102 s** (no `orbit-*` images or builder intermediates; infra-up incl. emulator build 36 s, api-build 34 s uncached, migrate 2 s; builds depend on the network, an earlier from-nothing emulator build took about 7 minutes); **warm 13 s** (12-13 s script, 14-15 s wall). The earlier **cold about 50 s was measured with images already cached**, and the earlier warm figure of about 19 s predates the always-build step; both are superseded. **Unexplained outlier:** one fresh-checkout run (images cached) took **20 min 35 s** (`docker compose up` step 1020 s at host load about 13, all containers healthy within seconds); it did not reproduce (next run 41.7 s). Cause not found.

**T10 history:** the first attempt (2026-10-20) failed 7 SmokeUITests runs under host memory pressure (swap 9.8-11 GB, load 22-48); AC27 was not proven then. After the owner closed heavy apps the re-run passed first time, with no test-code changes.

## Live-only gaps (never faked locally)

IAM enforcement (moto does not evaluate IAM or resource policies); VPC, security groups, NAT; real RDS/ElastiCache behavior (multi-AZ, `rds.force_ssl`, parameter groups); Lambda cold start and concurrency; front door and WAF; alarm-to-SNS and CloudWatch log delivery; service quotas and eventual consistency. Owed to E1/E2.

## Host provisioning

`brew install docker-compose` (5.6.0) was run during T1 and symlinked to `~/.docker/cli-plugins/docker-compose`; the host had no compose plugin. Revert: `brew uninstall docker-compose` and remove the symlink. `colima ssh -- sudo fstrim -av` was also run (non-destructive).

## Advisory, unresolved

- 2 Semgrep false positives remain (`infra/envs/local/providers.tf:18`, `scripts/seed_dev_data.py:91`); no suppression markers added (a marker appended on the first line would break `test_local_terraform_guards.py`). A third (`test_secrets_facade_moto.py:48`) disappeared with the busy-spin fix.
- 3 stale `.trivyignore` entries (CVE-2026-76642, CVE-2026-78408, CVE-2026-78409) match nothing on arm64; delete after an amd64 CI scan confirms.
- Trivy config findings AWS-0176 (MEDIUM) and AWS-0017 (LOW) are pre-existing.
- The emulator image is scanned advisory only (21 HIGH/CRITICAL at time of writing).

## Design review and DAST

- **Design review (FE Layer 4): skipped.** No `ui.env` exists; A1 adds no UI screens.
- **DAST (runtime): skipped.** No `dast.env` exists; A1 adds no app routes. Gating DAST layers run in CI against staging, not here.

## Verification coverage — what was and was NOT verified

### VERIFIED (with evidence source)

- Backend/unit/integration tests: 335 run, 335 passed, 0 failed (`test-results.json`); combined coverage 97.71% lines / 91.51% branches.
- 31 of 32 acceptance criteria covered by cited evidence (`test-results.json` `criteria_covered.by_id`); AC32 delegated to security and reconciled clean (`security-status.json`, `security-report.md`).
- Security cycle 4 (hash 2730aefb…): status clean, 0 critical, 16 warnings (all reported-only); STRIDE 17 mechanisms verified, 0 missing; ASVS L1/L2 reconciled with 9 verified and 3 human waivers (`security-status.json`).
- Scanners executed this pass (`scan-log.jsonl`): Semgrep, Gitleaks, reconcile-scans (re-run cycle 4); OSV, Trivy fs/config/image, Checkov, hadolint (cycle 2, carried forward because their inputs were byte-identical; the hash comparison is in `security-report.md`). SBOM generated (80 components).
- Smoke check: pass (`smoke-status.json`, 2026-11-08T04:20:17Z; predates the review-round code changes, not re-run).
- AC1 on an image-less machine (102 s, health 200) and warm re-run (13 s); `dev-down.sh` keeps volumes (run's evidence directory, `t7-ac1-imageless*.txt`).
- Review-round fixes proven red-then-green; the touched modules passed 11 consecutive runs, and the full suite passed with the stack down (335 passed, 2 xfailed).
- Terraform against moto: idempotent plan, destroy and re-apply, remote state with S3-native lock and a contention probe (transcripts in the run's evidence directory; summarized in `docs/local-development.md`).
- iOS (reduced assurance, in-run evidence only): AC27 Simulator done-flow 1/1 passed; AC26 OrbitTests 0 failures (counts unreconciled, see above).

### NOT VERIFIED (with reason)

- **Swift/iOS gate analysis**: swift adapters absent (`run-summary.json` `.assurance`); no Swift static analysis or gate-level scan of `ios/Orbit/` ran.
- **Full OrbitUITests suite**: advisory, skipped (`test-results.json` notes); only `SmokeUITests` ran.
- **The `local-stack` CI job and amd64 image builds**: never run on GitHub (`test-results.json` notes, `test-quality.json`).
- **AC25 post-merge check on `main`**: owed.
- **CI `osv` job**: will fail until the waiver is mirrored or pyasn1 is bumped (`security-report.md`).
- **Design review (FE Layer 4)**: skipped, `ui.env` not wired; no machine check of visual fidelity (no UI changes expected).
- **DAST**: skipped, `dast.env` not wired; no `dast-review.json`.
- **Mutation testing**: not run, no tool configured; `quality_ok` is false (`test-quality.json`).
- **Shell orchestration**: `dev-up.sh` now has a stub-based flow harness (`test_dev_up_flow.py`); `dev-down.sh` and real Docker/Terraform interplay are still proven by transcripts only. The harness fails open: a new external binary called by the script would run for real from the host PATH (`security-report.md`).
- **Emulator image vulnerabilities**: scanned advisory only; Trivy image scan of the emulator was not executed this pass (`security-report.md`). ast-grep did not run (trigger not met).
- **AC3 convergence on the current `dev-up.sh`**: interrupted-run and moto-restart scenarios not re-run after the `api-build` change (stub tests only).
- **e2e**: none (0). **Perf**: n/a.
- **Per-file coverage**: not analyzed in this pass; a `.coverage` data file exists at the repo root but was not read to name uncovered files, so only the aggregate is reported.
- **Live-only behavior** listed above.
- **Unreconciled iOS test counts** (208 vs 50) and the **unexplained 20 min 35 s** dev-up run.
- **6 fixable CVEs** remain ignored under temporary exceptions until 2026-11-10 / 2026-11-19.
- No acceptance criterion is both uncovered and undelegated.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
