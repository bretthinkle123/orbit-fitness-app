---
audited_at: 2026-10-19T23:06:16Z
plan_sha256: e2f51541b32f9a4020a921561f6ee4eb5de32aef3acc4504e12b63fe5adacd4a
flags_total: 10
material_flags: 2
critical_flags: 0
revision_recommended: true
dependencies_checked: 14
dependencies_unverified: 0
---

# Plan audit: a1-local-environment

Audited `.pipeline/plan.md` (sha256 above), `acceptance.md` (32 AC), `tasks.md` (11 tasks), against `requirements.md` and `operator-kickoff.md`. Registry lookups ran 2026-10-19 (Docker Hub API, npm, PyPI, GitHub releases, HashiCorp releases). No repomix pack exists and the plan says so (`repomix_pack: absent`), so no receipt flag.

## Focus here first

1. [material] **E1 "never touch real AWS" leans on an unverified guard claim.** Plan §Infrastructure (providers.tf) and STRIDE E1 say the `allowed_account_ids` check "really runs" because the account lookup is "not skipped" and STS points at moto, and that "explicit provider creds take precedence over env creds". The same provider block sets `skip_credentials_validation = true`. Whether the provider still resolves the account id under that flag is the invariant, and no task or AC tests it. AC8 only probes the endpoint-regex validation (`moto_endpoint=https://example.com`). Failure shape: the account guard silently does not run, and the only remaining protection is the endpoint override list. Question for planning: add an AC8/T1 probe (e.g. a scratch `allowed_account_ids` mismatch must fail `plan`, and a real-looking `AWS_ACCESS_KEY_ID` in env must not change the target), or drop the "guard really runs" wording.
2. [material] **`--env-file .env.local` is used on one compose call but not on the others.** Plan §Command sequence step 2 passes `--env-file .env.local`. Step 7 (`docker compose run --rm migrate`), step 8 (`docker compose up -d --wait api`) and T6 step 3 do not, and compose reads `.env`, not `.env.local`. `postgres` interpolates `POSTGRES_USER/PASSWORD/DB` from that file. `up api` reconciles the `depends_on` services, so with the variables blank compose sees a changed postgres config and tries to recreate it, which fails on an empty `POSTGRES_PASSWORD`. That would break the idempotent re-run (AC2/AC3). Question: pin one mechanism (`COMPOSE_ENV_FILES=.env.local` exported by dev-up, or `--env-file` on every invocation incl. dev-down) and say which.
3. [advisory] Postgres `16.6-alpine` is the oldest pin in the stack: image pushed 2025-02-05, latest 16.x is 16.15. Chosen for RDS parity (`modules/data engine_version = "16.6"`), and the plan notes RDS floats. Because Trivy gates only the API image, known 16.6 CVEs will never surface. Suggest recording this in `docs/local-development.md` or bumping both pins together.
4. [advisory] The rest of the pins are behind latest by design (see Version policy); fine, but state in the PR that they are parity pins.

Contradiction check against requirements.md / operator-kickoff.md: **none found.** No `perf.budget` is emitted (plan §Performance, AC29; the string appears only in prose, and the gates read the JSON `.perf.budget.*` keys). Host 9099 is left free and the API moves to 8080 (OQ1, disclosed). No fork: `secrets` gets a variable, `data` is split, `app_identity` is shared. Moto, not LocalStack. Plain uvicorn, no Lambda work. Staged state (T1 local, T3 moto S3). Digest-pinned in-repo emulator on firebase-tools 15.18.0, which equals CI. Simulator shutdown, "compose down before pytest", no Colima memory raise and measured-not-invented footprint are all honored. Disclosed departures are in flag 10.

## Completeness

| Dimension | Status | Missing item | Blocks | Class |
|---|---|---|---|---|
| Layer sections (Frontend/Backend/Data/Infra/Auth/Logging) | ✓ | Complete | — | — |
| Acceptance criteria traced (PROJECT/CLAUDE done-flow) | ✓ | All 8 done criteria traced; perf p95 carried as OQ8 with proposed answer | — | — |
| acceptance.md lists criteria with file/layer + verification | ✓ | 32/32, frontmatter count matches | — | — |
| tasks.md decomposition | ✓ | Union of "ACs advanced" = AC1-AC32. Every task maps to a plan section. No dangling `depends_on`. See flag 7 for a missing edge | — | advisory |
| STRIDE mechanisms named | ✓ | Every row carries file plus mechanism. E1 has an unverified claim (flag 1) | — | material (flag 1) |
| Input-surface controls | ✓ | No new HTTP route. Script, config and CLI sources carry validation plus `rate_limit_waiver` (AC21). Existing no-params rows are unchanged | — | — |
| Data protection | ✓ | No new stored field, stated | — | — |
| Object-level authz / authn boundary / safe-error / T2-x | ✓ n/a | No new route or auth change; greenfield tests still govern | — | — |
| DAST readiness | ✓ n/a | No new served HTTP surface | — | — |
| ASVS Compliance block | ✓ | Triggered chapters, "L3: none", waivers listed | — | — |
| Test strategy | ✓ | integration-heavy, with rationale | — | — |
| Files affected | ✓ | Concrete paths plus reasons. `.trivyignore` is named in AC14 but not in Files or any task (flag 8) | — | advisory |

## Ambiguities

| Section | Quoted text | Downstream risk | Clarifying question | Class |
|---|---|---|---|---|
| §Command sequence steps 7-8, tasks T6.3 | `docker compose run --rm migrate` / `docker compose up -d --wait api` (no `--env-file`) | Implementation follows literally; postgres recreated or fails (flag 2) | One env-file mechanism for every compose call? | material |
| §Infrastructure providers.tf | "the account lookup is **not** skipped" alongside `skip_credentials_validation = true` | Security expects a guard that may not fire (flag 1) | Is there a probe that proves it? | material |
| §Stack notes, compose table, tasks T6 | `redis:7.2.x-alpine`; `sha256:<index digest>` placeholders | Implementer must resolve at build time. Current facts: redis 7.2.16 is 28 days old; 7.2.15 is 85 days. node-24-trixie-slim moved 5 days ago and python-3.12-slim-bookworm 13 days ago, so a fresh digest sits inside a 14-day cooldown | Pick the digest at least 14 days old, or accept? | advisory (flag 6) |
| §Test strategy test_no_env_branches | Forbidden list omits `FIREBASE_AUTH_EMULATOR_HOST`, yet "exactly one allowlisted line" is that variable | The allowlist is moot; the test cannot fail on it. Current `src/orbit` has no forbidden hits (checked) | Add the pattern to the forbidden list, or drop the allowlist wording? | advisory (flag 5) |

## Proof-claim verification (3b) and data-flow trace (3c)

- "Proven by a test" (no `if local:` in `src/orbit`): enforced by `tests/unit/test_no_env_branches.py` (AC12). I grepped the plan's forbidden patterns over `src/orbit` today: 0 hits. OK.
- "`alembic upgrade head` is a no-op when current, which makes dev-up idempotent": enforced by AC2/AC3 runs. OK.
- "Release inherits no emulator host": enforced by AC26 `-showBuildSettings` and the `#if DEBUG` compile-out. OK.
- "account guard really runs / real account id refuses": **no enforcement point**, see flag 1.
- 3c: A1 reads only through the same-principal dev user it seeds via the real API. The reader owns its rows. No cross-feature scope-key gap.

## Dependency reality

| Package | Ecosystem | Exists? | Latest stable | Typosquat note |
|---|---|---|---|---|
| motoserver/moto 5.1.22 | Docker Hub | yes (pushed 2026-03-08, amd64+arm64) | 5.2.4 (2026-10-11) | official org |
| postgres 16.6-alpine | Docker Hub (official) | yes (pushed 2025-02-05) | 16.15-alpine | official |
| redis 7.2.x-alpine | Docker Hub (official) | yes, 7.2.16-alpine is latest | 7.2.16 (EOL 2029-12-01) | official |
| node 24-trixie-slim | Docker Hub (official) | yes (updated 2026-10-14) | tag floats | official; plan's trixie assumption holds |
| python 3.12-slim-bookworm | Docker Hub (official) | yes (updated 2026-10-06) | tag floats | official |
| firebase-tools 15.18.0 | npm | yes (2026-05-13) | 15.34.0 | official, already used in CI |
| poetry 2.4.1 | PyPI | yes (2026-05-09) | 2.5.1 | official, equals CI |
| boto3 1.43.40 | PyPI | yes (2026-07-03); already in pyproject | — | existing dependency |
| Terraform 1.15.9 | HashiCorp releases | yes (2026-08-19) | 1.16.6 | official |
| hashicorp/aws provider 6.52.0 | Terraform registry / GitHub | yes (2026-06-24) | 6.69.1 | official; equals root pin |
| hashicorp/setup-terraform | GitHub Action | yes | v4.0.1 (2026-05-12) | SHA to be looked up in T8 |
| hadolint (image) | Docker Hub | yes | 2.15.1 (2026-07-31) | official org |
| Trivy (image) | Docker Hub (aquasec) | yes | 0.76.0 (2026-10-14) | official |
| Checkov (bridgecrew image / PyPI) | Docker Hub | yes | 3.3.29 | already used in CI |

No new Python or npm package is added to `pyproject.toml`, `poetry.lock` or `package.json`. No 404s, so no critical flags.

## Version policy

| Package | Planned | Age (days) | Verdict | Recommended |
|---|---|---|---|---|
| moto | 5.1.22 | 225 | pass (spike-proven; last of the 5.1 line; 5.2.4 exists) | keep; revisit after T1 proves the cycle |
| postgres | 16.6 | ~621 | advisory: 9 patch releases behind, parity-driven | keep for RDS parity but re-pin both together (flag 3) |
| redis | 7.2.x | 7.2.16 = 28 | pass | 7.2.16 |
| node base | 24-trixie-slim | tag 5d | advisory: fresh digest inside cooldown | digest at least 14 days old |
| python base | 3.12-slim-bookworm | tag 13d | advisory: borderline | same |
| firebase-tools | 15.18.0 | 158 | pass (equals CI; 16 minors behind) | bump here and in CI together |
| poetry | 2.4.1 | 163 | pass (equals CI) | keep |
| Terraform | 1.15.9 | 61 | pass | keep |
| aws provider | 6.52.0 | 117 | pass (equals root; 17 minors behind) | keep. Note moto 5.1.22 predates this provider, so T1's failure clause matters |
| hadolint / Trivy / Checkov | digest at T8 | 80 / 5 / n/a | pass; Trivy 5d old, pin a digest ≥14d | choose digests at T8 |

## Could not verify

None unreachable. Not verifiable from the plan, because they are implementation-time lookups: the multi-arch index digests, the `hashicorp/setup-terraform` commit SHA, and that moto 5.1.22 serves `/moto-api/` and that AirPlay holds :5000 (the plan lists these as T1 assumptions).

## Other advisory flags

- Flag 7 [advisory]: tasks.md T6 modifies `scripts/dev/local_aws.py`, `test_dev_scripts.py` and relies on `.env.local.example`, all created in T3, but declares `depends_on: T2, T4, T5` (no T3). Execution is sequential, so no harm today; add T3 for resume safety.
- Flag 8 [advisory]: `.trivyignore` is referenced by AC14 and the CI job but no task or Files row creates or touches it.
- Flag 9 [advisory]: AC22 includes "dev-up/seed output" evidence (T7) but T7 does not list AC22.
- Flag 10 [advisory]: disclosed departures from requirements.md, all already raised as checkpoints: OQ6 (edits root `infra/main.tf` though requirements say the root composition stays put), OQ7 (CI runs the full apply/destroy cycle where requirements say validate/plan), OQ1 (8080 not 8000), nine endpoints (adds `sts`) where the brief says eight. All are reasoned. Confirm at the checkpoint.

(Flags 3-4 and 5-6 above are counted: advisory total = 8, material = 2, total = 10.)
