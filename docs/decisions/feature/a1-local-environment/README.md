# a1-local-environment run — retained pipeline artifacts

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

The frozen record of the **A1 local environment** pipeline run (2026-10-19 to 2026-11-08,
branch `feature/a1-local-environment`): a one-command local stack (moto, Postgres, Redis, a
Firebase Auth emulator, the containerized API), Terraform against moto, and the iOS Debug
build pointed at it. Same convention as `docs/decisions/feature/greenfield/README.md`:
`.pipeline/` is gitignored and overwritten by the next run, so the durable files are copied
here at closeout.

## What's here

| File | What it is | Why retained |
|---|---|---|
| `requirements.md` | The elicited brief planning treated as source of truth | Scope record |
| `operator-kickoff.md` | The owner's kickoff constraints, plan-checkpoint decisions, waiver and cooldown decisions, and journaled interventions, transcribed verbatim | The only durable record of the owner decisions (AC8 probe-2 amendment, `use_lockfile`, Postgres 16.15, the 6 cooldown exceptions, ASVS waivers) |
| `plan.md` | Plan, STRIDE threat model, data classification | The posture the build is held to |
| `plan-audit.md` | Pre-checkpoint audit of the plan | What was challenged before approval |
| `tasks.md` | The T1-T11 decomposition and AC coverage map | Referenced by task id |
| `acceptance.md` | The 32 acceptance criteria and how each is verified | The done-bar |
| `security-report.md`, `security-status.json` | Findings, ASVS reconciliation, waivers, open obligations | Carries the open items forward |
| `test-results.json` | Counts, coverage, per-criterion evidence | Provenance for coverage figures |
| `run-summary.json` | Per-stage tallies; `assurance` is `reduced (swift adapters absent)` | Reduced-assurance stamp |
| `implementation-progress.md` | Append-only per-task build journal | **Historical, point-in-time**; where it disagrees with the code, the code wins |
| `pr-description.md` | The PR body, including the verification coverage map | The run's own statement of what was and was not verified |

## Deliberately not retained

- `waivers.json` — human-only, TTY-recorded ledger (ASVS `12.2.1`, `12.3.1`, `13.2.1`,
  OSV `pyasn1`, plus earlier ones); gitignored on purpose. A fresh clone re-blocks until a
  human re-records them. The CI-side waiver record is the committed `.trivyignore`.
- `a1-evidence/` (about 66 MB: transcripts, Terraform logs, xcresult bundles) — too large and
  machine-specific. `test-results.json` and `acceptance.md` cite files in it as
  `.pipeline/a1-evidence/...`; those paths exist only on the machine that ran the pipeline.
  The numbers worth keeping are summarized in `docs/local-development.md`.
- `debug-notes.md`, `test-quality.json`, `scan-*.json`, `*.jsonl`, scanner outputs — working
  notes and telemetry; conclusions are in `security-report.md`.
