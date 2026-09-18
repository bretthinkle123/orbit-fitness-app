# Greenfield run — retained pipeline artifacts

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

The frozen, human-readable record of the **greenfield** pipeline run (merged 2026-07-26,
PR #1). Each pipeline run writes its working artifacts to a gitignored `.pipeline/`
directory that does **not** survive a fresh clone and whose files the *next* run
overwrites. This directory is the durable copy of the ones worth keeping.

**Convention for every future run:** at closeout, retain the same set under
`docs/decisions/feature/<feature>/`. Anything only in `.pipeline/` is run-local and
disposable by design.

## What's here

| File | What it is | Why retained |
|---|---|---|
| `requirements.md` | The elicited + operator-revised brief planning treated as source of truth | Authoritative scope record; cited from `CLAUDE.md`, `PROJECT.md`, `README.md` |
| `design-audit.md` | Scope-level audit of the Claude Design export — what the design depicts vs what shipped | Justifies every deferral in `docs/roadmap.md` |
| `design-spec.md` | Normalized screen/component/token inventory + injection report | The design contract the iOS layer replicates |
| `plan.md` | Full implementation plan, STRIDE threat model, data classification | The security/architecture posture the build is held to |
| `plan-audit.md` | Pre-checkpoint structural audit of that plan | Shows what was challenged before approval |
| `tasks.md` | The 18-task decomposition and its AC coverage map | Referenced by task id (T1–T18) from `ios/Orbit/README.md` and elsewhere |
| `acceptance.md` | All 34 acceptance criteria and how each was verified | The done-bar future runs inherit (see roadmap standing rules) |
| `security-report.md` | Findings, fixes, ASVS reconciliation, waivers, latent items | Carries forward open obligations |
| `security-status.json` | Machine-readable gate record: counts, ASVS reconciliation, scan-artifact hashes | Evidence the prose report summarizes |
| `test-results.json` | Test counts and line/branch coverage as measured at closeout | Provenance for the coverage figures quoted in `tests/README.md` |
| `pr-description.md` | The merged PR's body — assurance stamp, per-area narrative | The run's own summary of what shipped and how sure it is |
| `run-summary.json` | Per-stage invocation/attempt/cap tallies | Run-mechanics record; `assurance` field is the reduced-assurance stamp |
| `implementation-progress.md` | Append-only per-task build journal (T1–T18) | **Historical, point-in-time.** Where it disagrees with the code, the code wins |

## Deliberately not retained

- `waivers.json` — the human-recorded ASVS waiver ledger (`6.3.3`, `6.2.x`). It stays
  gitignored on purpose: `record-waiver.sh` is TTY-only and human-only, and the security
  gate trusts only the live `.pipeline/waivers.json`. Copying it into the tracked tree
  would turn a human control into a copyable file. **Consequence to plan for:** on a fresh
  clone (including the operator's Mac), those waivers are absent and the security stage
  will re-block on both until a human re-records them. See `security-report.md`
  §"Waived — human-recorded".
- `surface-delta.md`, `debug-notes.md` — inputs to, and working notes of, the security and
  debugging stages; their conclusions are already in `security-report.md` and in git
  history.
- `test-quality.json`, `store-compliance.json`, `review-manifest.json`,
  `doc-identifiers.json`, `scan-*.json`, `*.jsonl` — engine interlock state and telemetry,
  meaningful only to the run that produced them. The aggregate is in `run-summary.json`.

## Notes

- These are **frozen artifacts**. Internal `.pipeline/…` references inside them are
  as-written during the run; the retained equivalent, where one exists, sits beside them
  in this directory.
- Native iOS is a **reduced-assurance** target throughout — nothing in `ios/Orbit/` was
  compiled, run, or snapshot-reviewed during this run. AC27's live device/simulator walk
  is still open (`plans/00-mac-pipeline-readiness.md` Phase 5). Never read an iOS claim in
  these artifacts as gate-verified.
