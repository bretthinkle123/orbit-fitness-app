---
status: clean
cycle: 4
ran_at: 2026-11-08T06:09:25Z
scope: diff
since_commit: ade7efe093201238f1732cd1a738ae0cdd7110a9
scanned_change_hash: 2730aefbe0b75322e1d9434609abc121044badcecdd01ffae0edca2f3458b456
critical_count: 0
warning_count: 16
fixed_count: 0
total_findings: 16
semgrep_findings: 2
osv_findings: 4
osv_max_cvss: 7.5
osv_waiver: pyasn1 (human-recorded 2026-11-08T04:59:38Z, approved_by Brett)
trivy_findings: 2
checkov_findings: 0
stride_mechanisms_verified: 17
stride_mechanisms_missing: 0
stride_new_threats: 0
---

# Security report: a1-local-environment (cycle 2)

The change set is 63 files. That is cycle 1's 61 plus `poetry.lock`, which is now modified, and the new file `tests/unit/test_dependency_cve_floors.py`.

Files modified since cycle 1:
- `poetry.lock`
- `Dockerfile`
- `.trivyignore`
- `tests/unit/test_dev_scripts.py`
- `tests/unit/test_dependency_cve_floors.py`
- `docs/local-development.md`
- `plans/A2-production-terraform-authoring.md`

`infra/` is byte-identical to cycle 1. Checkov was re-run anyway.

## Resolved since cycle 1

- **certifi GHSA-6q48-6c7w-9gw2 / PYSEC-2026-4320 (CVSS 9.1).** Fixed. poetry.lock now pins 2026.10.23 (floor 2026.10.18), backed by a pin-guard test. Neither OSV nor the image scan reports it.
- **msgpack GHSA-j586-36cw-2gc2 (7.5).** Fixed: 1.2.3.
- **AC14 / STRIDE T2 / ASVS 15.2.1.** I rebuilt `orbit-api:local` on base `python:3.12-slim-bookworm@sha256:6a0e06f5…`, the 3.12.15 re-push from 2026-10-21, which clears the 14-day cooldown. A CI-equivalent `trivy image --severity HIGH,CRITICAL --exit-code 1` with `.trivyignore` now exits **0 with 0 unwaived findings**. The image still runs as user 10001:10001.
- **Not-yet-fixable Debian CVEs:** the 5 new ones (sqlite CVE-2026-119373/119374/119379, zlib1g CVE-2026-76844/85091) are owner-accepted into `.trivyignore`. Each entry is dated, with revisit-by 2026-12-08.
- **ASVS 12.2.1, 12.3.1 and 13.2.1** now have human waivers in `waivers.json`, recorded 2026-11-08T04:58Z. I honored them.
- **Gitleaks fixture** at `tests/unit/test_dev_scripts.py:14`: reworded to `not-a-real-password-for-tests` with no suppression marker. The dir scan now has 0 in-scope hits. The only remaining hits are the gitignored `.env.local` and copies in `.pipeline/`.

## Scanner execution (cycle 2, all stamped in scan-log.jsonl)

| Tool | Result | Artifact |
|---|---|---|
| Semgrep (same rule packs as cycle 1), 63 targets | 3 findings, the same low-severity false positives as cycle 1 | `.pipeline/semgrep.json` |
| Gitleaks dir | 0 in-scope | `.pipeline/gitleaks.json` |
| OSV (poetry.lock) | 4 IDs, all pyasn1 0.6.4, max CVSS 7.5 | `.pipeline/osv.json` |
| Trivy fs (vuln, secret, misconfig) | 0 with `.trivyignore`; 4 pyasn1 IDs without it, the same set OSV reports | `.pipeline/trivy-fs.json`, `trivy-fs-noignore.json` |
| Trivy config | 2: AWS-0176 MEDIUM, AWS-0017 LOW (both pre-existing) | `.pipeline/trivy-config.json` |
| Trivy image `orbit-api:local` (rebuilt 2026-11-08T05:01Z) | gate exit 0, 0 unwaived; the no-ignore audit shows 23 IDs | `.pipeline/trivy-image.json`, `trivy-image-noignore.json` |
| Checkov `infra/` | 143 passed / 0 failed / 35 skipped | `.pipeline/checkov.json` |
| hadolint (both Dockerfiles) | clean | `.pipeline/hadolint.txt` |
| lockfile-check | WARN: lock re-locked with no `pyproject.toml` change. This is the intended debugging bump | — |
| asvs-sast / store-compliance | 0 / 0 | `.pipeline/asvs-sast.json`, `store-compliance.json` |
| SBOM | 80 components | `.pipeline/sbom.cdx.json` |

**Not run, carried from cycle 1 with the reasons unchanged:**
- **Emulator-image Trivy:** advisory only under OQ10; CI runs it.
- **ast-grep:** its trigger was not met. There is no SQL, RLS, migration or async change.
- **pytest:** that is the testing stage's job.

## OSV waiver: is it valid, and what format is its id?

- **What the owner recorded:** in `waivers.json`, `.osv[0].id` is `"pyasn1"`. That is a **package name, not a CVE or GHSA id**.
- **Why the deploy gate accepts it:** `deployment-gate.sh` compares `security-status.json .osv_waiver.id` as an exact string against `waivers.json .osv[].id`. So `osv_waiver.id = "pyasn1"` validates. The gate does not require an advisory-id format.
- **What it covers:** the gate lifts the whole CVSS ≥ 7 floor for any non-null `osv_waiver`; it does not check per CVE. I claimed the waiver only because **every** remaining finding at 7.0 or above is pyasn1 0.6.4: GHSA-2qm8-x737-gmw5, GHSA-9m75-vc3g-4x39, GHSA-fm9c-5rcf-2q5p and GHSA-mm57-4v3p-rchx, all 7.5, all fixed in 0.6.5. A new non-pyasn1 finding at 7.0 or above would have to be reported unwaived.
- **Where the waiver does not reach:** CI's `osv` job reads only a committed `osv-scanner.toml`, never `waivers.json`. **CI will fail on these 4 IDs** until either pyasn1 is bumped (eligible 2026-11-10T06:33Z) or the owner commits an `osv-scanner.toml` `[[IgnoredVulns]]` entry for the 4 GHSAs with `ignoreUntil` 2026-11-10 (row 16).

## Complete findings inventory (cycle 2)

| # | source | id | severity | exploitable | location | disposition |
|---|---|---|---|---|---|---|
| 1 | osv | GHSA-2qm8-x737-gmw5 (pyasn1 0.6.4) | HIGH 7.5 | DoS only | poetry.lock (via pyasn1_modules) | reported-only: human OSV waiver `pyasn1`; bump to 0.6.5 on or after 2026-11-10 |
| 2 | osv | GHSA-9m75-vc3g-4x39 (pyasn1) | HIGH 7.5 | DoS only | poetry.lock | reported-only (waived) |
| 3 | osv | GHSA-fm9c-5rcf-2q5p (pyasn1) | HIGH 7.5 | DoS only | poetry.lock | reported-only (waived) |
| 4 | osv | GHSA-mm57-4v3p-rchx (pyasn1) | HIGH 7.5 | DoS only | poetry.lock | reported-only (waived) |
| 5 | trivy | CVE-2026-84782 libssl3/openssl 3.0.22-1~deb12u1 | HIGH | reachable via Python `ssl` | orbit-api:local | reported-only: owner-accepted temporary entry; fixed in base 3.12.16 `sha256:935c3c5b…`, eligible 2026-11-19T17:07Z |
| 6 | trivy | CVE-2026-109518 apt 2.6.1 | HIGH | no (not used at runtime) | orbit-api:local | reported-only: owner-accepted temporary entry; same base bump |
| 7 | trivy | 18 owner-accepted no-fix Debian IDs, all still unfixed on today's DB: CVE-2023-45853, CVE-2025-69720, CVE-2025-7458, CVE-2026-11822, -11824, -16742, -41992, -53613, -53615, -54369, -78410, -9538, -119373, -119374, -119379, -76844, -85091 | CRITICAL ×2, HIGH | no evidence | orbit-api:local (debian 12.15) | reported-only (dated `.trivyignore` entries) |
| 8 | trivy | Stale `.trivyignore` entries CVE-2026-76642, CVE-2026-78408 and CVE-2026-78409 still match nothing (arm64) | LOW | no | .trivyignore | reported-only (confirm on amd64 in CI, then delete) |
| 9 | manual-6d | Stale `.trivyignore` header comment: it still calls CVE-2026-84782 a no-fix accepted risk and says "Fixable findings are NOT listed here", but the new cooldown section does list fixable ones | LOW | no | .trivyignore (A1 section header) | reported-only (documentation drift) |
| 10 | semgrep | aws-provider-static-credentials | WARNING | no (moto dummy credentials, E1 Layer A) | infra/envs/local/providers.tf:18 | reported-only (false positive; owner left the marker undecided; CI Semgrep runs `--severity ERROR`) |
| 11 | semgrep | request-with-http | INFO | no (loopback-guarded) | scripts/seed_dev_data.py:91 | reported-only (false positive) |
| 12 | semgrep | request-with-http | INFO | no (test against local moto) | tests/integration/test_secrets_facade_moto.py:48 | reported-only (false positive) |
| 13 | trivy (config) | AWS-0176 | MEDIUM | no | infra/modules/data/main.tf:50 | reported-only (pre-existing; CKV_AWS_161 rationale) |
| 14 | trivy (config) | AWS-0017 | LOW | no | infra/modules/network/main.tf:138 | reported-only (pre-existing; CKV_AWS_158 rationale) |
| 15 | manual-6g | ASVS 15.2.4 hygiene: `pip install boto3==1.43.40` without `--require-hashes` | LOW | no | .github/workflows/pipeline-ci.yml (local-stack, "State bucket" step) | reported-only |
| 16 | manual-6g | CI merge gate: the `osv` job will fail on rows 1-4. `waivers.json` is local-only and there is no committed `osv-scanner.toml` | WARNING (process) | no | .github/workflows/pipeline-ci.yml:231-252 | action-required (owner) |
| 17 | manual-6g | OSV waiver id is a package name (`pyasn1`), not an advisory id. The gate accepts it, but the scope of a package-wide waiver is implicit | LOW | no | .pipeline/waivers.json | reported-only (retire it at the pyasn1 bump, per A2 row C) |
| 18 | lockfile | poetry.lock re-locked with no `pyproject.toml` change | WARNING | no | poetry.lock | reported-only (intended CVE bump; content-hash unchanged) |

## Fixes applied (cycle 2)

None by security this cycle. Debugging and the owner made the cycle-1 remediations listed above. I confirmed each one by re-scanning.

## Could not remediate

None.

## Action required

1. **Owner, needed for green CI:** commit an `osv-scanner.toml` with `[[IgnoredVulns]]` entries for GHSA-2qm8-x737-gmw5, GHSA-9m75-vc3g-4x39, GHSA-fm9c-5rcf-2q5p and GHSA-mm57-4v3p-rchx. Give each `ignoreUntil = 2026-11-10` and a reason citing the 2026-11-08 cooldown decision. The alternative is to wait for the pyasn1 0.6.5 bump on or after 2026-11-10T06:33Z. I did not write it: it is the owner's risk acceptance, and cycle 1's suppression edits were blocked by the permission classifier.
2. **On or after 2026-11-10:** bump pyasn1 to 0.6.5. Then remove its four `.trivyignore` lines, remove the xfail in `tests/unit/test_dependency_cve_floors.py`, and retire the `pyasn1` OSV waiver (A2 row C).
3. **On or after 2026-11-19:** move both `FROM` lines to base `python:3.12.16-slim-bookworm@sha256:935c3c5b…`. Then delete the CVE-2026-84782 and CVE-2026-109518 lines (A2 row C).
4. **Hygiene:** fix the stale `.trivyignore` header comment (row 9). Delete CVE-2026-76642, CVE-2026-78408 and CVE-2026-78409 once CI's amd64 scan confirms they no longer match (row 8).

## 6d STRIDE mechanism verification

All 17 non-accepted rows verified.
- **T2** is now effective: the API image gate exits 0, and every suppressed fixable CVE is explicitly labeled, dated and owner-accepted.
- **All other rows** are as in cycle 1, re-confirmed against the unchanged files: I1, S1, E1, I2, I3, I4, I5, T1, E2, T3, T4, T6, S2, D1, D2, T5.
- **T1 (supply-chain pins):** both `FROM` lines are digest-pinned to the 3.12.15 re-push from 2026-10-21, which is at least 14 days old.
- **R1 and E3** are accepted risks.

## 6g ASVS 5.0.0

- **Triggered chapters:** V2, V12, V13, V15, V16.
- **Met (9):** 2.2.1, 13.3.1, 13.3.2 (authored), 13.4.1, 13.4.2, 15.2.1, 15.2.2, 15.2.4, 16.2.5.
  - 15.2.1 counts as met because no component is past its documented remediation window: the 14-day cooldown plus dated bumps on 2026-11-10 and 2026-11-19, recorded in the A2 brief row C.
- **Waived by a human, and honored:** 12.2.1, 12.3.1, 13.2.1.
- **Missing:** none. `asvs.reconciled = true`.

## Input / data surface, STRIDE delta

These are unchanged from cycle 1.
- **Input surface:** 4 declared and 4 implemented; none uncontrolled.
- **Data surface:** the DSN stored in moto Secrets Manager is protected by the secrets module's KMS CMK; nothing unprotected.
- **STRIDE delta:** none. This cycle's changes add no new surface: version bumps, an image base change, a test and docs.

## Cycle 3: currency re-scan (2026-11-08T05:11:22Z)

- **Change set:** 64 files, up from 63. The only new file is `tests/unit/test_local_terraform_guards.py`.
- **New hash:** `scanned_change_hash: 55e3d4ebc70fc2b33787187ee74e7b5e288ede944bac2a1ce5beb23af3f5ad3a`. Cycle 2's was `8f1efc97…`.

### Verification that nothing else changed

Three infra files had mtimes newer than the cycle-2 scan: `infra/envs/local/main.tf`, `providers.tf` and `variables.tf`, touched at 05:06:55Z–05:06:58Z.
- I recomputed the change hash using the same diff-plus-untracked-content algorithm, leaving out only the new test file. The result was exactly cycle 2's `8f1efc971d38fbdd4f034d4949ddb8cc74b4b247ccc15174ad4ee3c2a8f7e467`.
- So every other file is byte-identical to cycle 2. Those three infra changes are mtime-only, with no content change.
- Because of that, OSV, Trivy (image, fs and config) and Checkov are **carried forward from cycle 2**. Their counts and artifacts are unchanged, and they are omitted from `scan_artifacts` this pass.

### Scans run this cycle

| Tool | Scope | Result |
|---|---|---|
| Semgrep (same rule packs) | full 64-file change set (a superset of the new file, so `semgrep.json` stays coherent for the reconcile scope check) | 3 findings, the same false positives as cycle 2 (rows 10-12). **0 in `test_local_terraform_guards.py`**, which appears in `paths.scanned`. |
| Gitleaks dir | tree | 0 in-scope hits. Only the gitignored `.env.local` and `.pipeline/` copies match. |
| reconcile-scans.sh | — | `reconciled: true`, no count mismatches, no scope gaps |

### Review of the new file

- It is read-only. It parses `infra/*.tf` and `.trivyignore` with `re` and `Path.read_text`. It makes no writes, network calls or subprocess calls, and contains no secrets.
- It strengthens STRIDE E1 and S1 coverage: it lifts the endpoint regex out of `variables.tf` and feeds it hostile inputs, pins all nine endpoints, the static credentials and the module set.
- No new attack surface (`stride_new_threats: 0`).
- **Interaction worth knowing:** its assertion `^\s*secret_key\s*=\s*"test"\s*$` (line 96) would fail if a `# nosemgrep` marker were appended to `infra/envs/local/providers.tf:18` (row 10). If the owner ever decides to suppress row 10, put the marker on its own line above, or use `.semgrepignore` scoping.

### Totals

These are unchanged from cycle 2:
- 0 critical, 18 warnings, 0 fixed, 18 findings in total.
- `osv_max_cvss: 7.5`, all pyasn1, covered by the human waiver `osv_waiver.id = "pyasn1"`.
- `asvs.reconciled: true`, with 12.2.1, 12.3.1 and 13.2.1 honored.
- `input_surface.uncontrolled: []`, `data_surface.unprotected: []`, `scan_reconciled: true`.
- Status: **clean**.

### Action required

Cycle 2's Action required list still stands. In particular, CI's `osv` job will fail on the 4 pyasn1 GHSAs until a committed `osv-scanner.toml` mirrors the owner's waiver, or until pyasn1 is bumped on or after 2026-11-10.

## Cycle 4: re-scan after the code-review fixes (2026-11-08T06:09:25Z)

- **Change set:** 85 files, up from 64. **New hash:** `scanned_change_hash: 2730aefbe0b75322e1d9434609abc121044badcecdd01ffae0edca2f3458b456`.
- **New files (21):**
  - `tests/unit/test_dev_up_flow.py`
  - `docs/decisions/feature/a1-local-environment/` (14 retained artifacts)
  - 6 READMEs: `docker/`, `docker/firebase-emulator/`, `infra/envs/`, `infra/modules/app_identity/`, `infra/modules/data_keys/`, `scripts/dev/`, `ios/Orbit/Config/`
- **Content-modified since cycle 3:**
  - `.trivyignore`
  - `scripts/dev-up.sh`
  - `scripts/dev/local_aws.py`
  - `scripts/seed_dev_data.py`
  - `tests/unit/test_dev_scripts.py`
  - `tests/integration/test_secrets_facade_moto.py`
  - `docs/local-development.md`
  - READMEs (`ios/Orbit`, `scripts`, `tests`)
- `infra/envs/local/.terraform/` changed too, but it is gitignored and outside the change set.

### Carried forward, with reasons

These files have not been modified since cycle 3's scan (checked by mtime against 05:11:22Z):
- `poetry.lock`
- `Dockerfile`
- `docker/firebase-emulator/Dockerfile`
- `docker-compose.yml`
- `.dockerignore`
- every `infra/**/*.tf` (0 files newer)

So **OSV, Trivy (image, fs and config) and Checkov are carried forward from cycle 2** and omitted from `scan_artifacts`. Their counts are unchanged: OSV 4 (pyasn1, max 7.5, human waiver `pyasn1`), Trivy config 2, Checkov 0, and the image gate exits 0.

### `.trivyignore` edit is header-only

- The set of non-comment entries is **byte-identical** to cycle 2: 27 IDs, AWS-0104 plus 26 CVEs. No entry was added or removed.
- The documentation stage rewrote the A1 section header. It now says CVE-2026-84782 was moved to the cooldown section, and it gives the 20-no-fix count and both revisit-by dates.
- This **resolves cycle-2 row 9** (stale header comment).

### Scans run this cycle

| Tool | Scope | Result |
|---|---|---|
| Semgrep (same rule packs) | 85-file change set (a superset of the changed files) | **2 findings**: providers.tf:18 (WARNING) and seed_dev_data.py:91 (INFO), both the known false positives. The `tests/integration/test_secrets_facade_moto.py:48` INFO hit is gone because the busy-spin fix moved the readiness probe into `_wait_until_ready(get=requests.get)`. **Cycle-2 row 12 resolved.** 0 findings in `test_dev_up_flow.py` and in the changed scripts. |
| Gitleaks dir | tree | 0 in-scope hits, `docs/decisions/` included. Only the gitignored `.env.local` and `.pipeline/` copies match. |
| lockfile-check | — | WARN, the same intended re-lock as cycle 2 (row 18) |
| asvs-sast / store-compliance | — | 0 / 0 |
| reconcile-scans.sh | — | `reconciled: true`, no mismatches, no scope gaps |

### Secrets in the retained copies under `docs/decisions/feature/a1-local-environment/`

- 0 occurrences of the actual `.env.local` values (`POSTGRES_PASSWORD`, `ORBIT_DEV_USER_PASSWORD`). I also checked the rest of `docs/`, `scripts/`, `tests/` and `infra/`.
- No unredacted DSN credentials, no private keys, and no tokens.
- The only key-shaped string is `AKIAEXAMPLEPROBE0000`, the documented fake used by the CI and acceptance probes.
- The retained `security-status.json` is the cycle-3 snapshot (`55e3d4eb…`, clean). Re-copy it at closeout if the retained set should carry the final cycle.
- `private-docs/` is mentioned only as an exclusion target in the I2 threat row (`plan.md` lines 256 and 1032). Nothing is cited from it or copied out of it.

### Review of the code changes

- **`scripts/dev-up.sh`:**
  - The new `api-build` step runs before `migrate`. `--rebuild` maps to `--no-cache`.
  - The tf-state step `case`-matches exactly `state_bucket_created=0|1`. Any other output fails closed via `fail`, which echoes only the helper's stdout, never secret material.
  - No new `eval`, no sourcing of `.env.local`, and no new published ports. `assert_loopback_only` is still called for 5433/6380/9100/5001 and 8080.
- **`scripts/dev/local_aws.py`:** `ensure-state-backend --report` prints one fixed-format line on stdout and the summary on stderr. It touches no secrets. The loopback guard still runs before any client is created.
- **`scripts/seed_dev_data.py`:** the status code is checked before any JSON is parsed. Only a 400 body is inspected, by `_is_email_exists`, which is type-guarded. Every other failure raises the HTTP error. The URL in that error carries only the emulator's fake key; the token and password are never printed.
- **`tests/unit/test_dev_up_flow.py` (the PATH-stubbing harness):**
  - It is contained. The real `dev-up.sh` is **copied into `tmp_path`**, so `REPO_ROOT`, `.env.local` (a dummy) and `rm -f "$TF_DIR/errored.tfstate"` all resolve inside the temp tree.
  - Stubs for `docker`, `lsof`, `terraform` and `curl` are prepended to `PATH`. The venv python and `seed_ui_test_user.sh` are stubbed at their repo-relative paths.
  - It runs `subprocess.run` with an argv list, no `shell=True` and a 60 s timeout. Stub state is confined to `tmp_path`. No network, no real Docker, no real Terraform.
  - Residual design note, advisory and not a finding: the harness fails open. If `dev-up.sh` later calls a new external binary, that binary resolves from the host `PATH` and runs for real. Pre-check for it, or stub-by-default, if the script grows.
- **`tests/integration/test_secrets_facade_moto.py`:** the injectable `get`/`sleep`/`clock` readiness loop sleeps on every non-ready answer. That closes the 60 s request storm. Its target is the testcontainers moto only.

### Totals

- 0 critical, **16 warnings**, 0 fixed, **16 findings in total**. That is cycle 2's 18 rows minus row 9 (stale `.trivyignore` header) and row 12 (Semgrep `test_secrets_facade_moto.py:48`), both resolved by the tree changes. No new findings.
- `semgrep_findings: 2`, `osv_findings: 4`, `osv_max_cvss: 7.5`, `osv_waiver.id: "pyasn1"` (human-recorded and honored).
- `asvs.reconciled: true`, with 12.2.1, 12.3.1 and 13.2.1 honored.
- `input_surface.uncontrolled: []`. The code-review fixes changed the existing CLI inputs, all still allowlisted, and added no new input source.
- `data_surface.unprotected: []`, `stride_new_threats: 0`, `scan_reconciled: true`.
- Status: **clean**.

### Action required

Cycle 2's list still stands:
1. **CI `osv` job.** It will fail on the 4 pyasn1 GHSAs until a committed `osv-scanner.toml` mirrors the owner's waiver, or pyasn1 is bumped on or after 2026-11-10.
2. **Dated cooldown bumps (A2 row C).** pyasn1 on or after 2026-11-10; base image on or after 2026-11-19.
3. **Stale `.trivyignore` IDs.** Delete CVE-2026-76642, CVE-2026-78408 and CVE-2026-78409 once amd64 confirms they no longer match.
4. **CI `boto3` install.** It still has no `--require-hashes`.
