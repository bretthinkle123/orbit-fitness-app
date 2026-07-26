# `tests/` — backend test suite

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

pytest suite for `src/orbit/`: unit tests at local-logic boundaries, integration tests
against a real testcontainers Postgres + Firebase Auth emulator + Redis, and a k6
performance harness. Realized shape leans integration-heavy (106 integration vs 36 unit,
142 total) — an honest divergence from the plan's declared `pyramid` shape, because most
acceptance criteria (ownership, bounded queries, rate limiting, migrations, atomic
rollback) are only truthfully provable against a real DB, not a mocked boundary.

## Modules

| Path | Responsibility |
|---|---|
| `conftest.py` | Shared fixtures: testcontainers Postgres, Firebase emulator client, seeded app instance, per-test isolation. |
| `unit/` | `test_secrets.py`, `test_openapi_contract.py`, `test_crypto.py`, `test_models.py`, `test_auth_guard.py`, `test_schemas_common.py`, `test_repositories_base.py`, `test_logging.py`, `test_errors.py` — pure-logic / facade-boundary tests. |
| `integration/` | One file per domain (`test_migrations.py`, `test_edge.py`, `test_weight.py`, `test_train.py`, `test_ratelimit.py`, `test_account_deletion.py`, `test_fuel.py`, `test_health.py`, `test_auth.py`, `test_seed_dast_user.py`, `test_body.py`, `test_profile.py`) — each exercises real HTTP routes against the real DB/emulator, including the mandatory adversarial shapes (cross-owner IDOR/BOLA, unauthenticated-access-denied, constraint→4xx, safe-error, two-principals-one-IP, migration round-trip, erasure-cascade + atomic-rollback, token validation, session-lifecycle). |
| `perf/run_perf.sh`, `perf/k6_orbit.js` | k6 `constant-arrival-rate` performance harness (Docker `grafana/k6`) against an out-of-process uvicorn; excluded from the CI test job via the `perf` pytest marker, run separately. |

## Relationships

`conftest.py` is the one seam every other file depends on (rule-of-two shared
fixtures) — it is what makes the integration suite genuinely exercise real ownership,
constraint, and rate-limit behavior rather than mocking them. `unit/` never touches a
real DB/network; `integration/` always does. `perf/` runs standalone, outside pytest's
collection for the coverage-gated job.

## Notes

- Coverage floor is 80% (`CLAUDE.md`, mirrored in `pyproject.toml`'s pytest config and
  `.github/workflows/pipeline-ci.yml`); this run measured **97.07% lines / 91.51%
  branches** combined (`.pipeline/test-results.json`).
- No mutation-testing tool is wired yet (`.pipeline/test-quality.json`:
  `quality_ok: false` — see the PR description's Testing section); several
  falsifiability probes (deliberately breaking a mechanism, confirming the test goes
  red, then restoring it) were run this session as a manual substitute for the
  highest-value security-property tests.
- iOS's own test suite (`ios/Orbit/Tests/`) is authored but not runnable from this
  directory or on this host — see `ios/Orbit/README.md`.
