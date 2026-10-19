# A1 run-start checklist (read before starting the A1 run)

_Written 2026-10-03 on the WSL box, for a fresh Claude Code session on the operator's M2
Mac with no other context. Scope: getting the **A1** run started on the right machine with
the right environment and decisions. Retire this file at A1 closeout — it is a launch
checklist, not a living reference._

Everything here is derived from committed docs, cited inline. Where this file and a cited
doc disagree, **the cited doc wins**: it is maintained, this one is not.

## Start here — the two messages to paste

**First, in a terminal** (the session needs the pulled files to read them):

```sh
cd ~/repos/orbit-fitness-app && git pull
```

**Then paste this to the session:**

```
Read docs/a1-run-start.md, then run bash scripts/mac-preflight.sh and tell me
what fails. Don't start the A1 run until the pre-flight is clean.
```

**Once the pre-flight reports READY, paste this:**

```
Start the A1 run: read plans/A1-local-environment.md and begin with
requirements-elicitation.
```

The run branches off `main` by itself — no branch needs creating by hand. The rest of
this file is what the session reads to act on those two messages.

## What the run is

**A1 — Local environment**, the first run of the post-greenfield roadmap. Brief:
[`plans/A1-local-environment.md`](../plans/A1-local-environment.md). Run order and the
standing rules every run must honor: [`docs/roadmap.md`](roadmap.md).

It builds the Dockerfile, docker-compose (Postgres, Redis, Firebase Auth emulator,
LocalStack), Terraform `envs/local` applied to LocalStack, the Simulator build config,
`dev-up.sh` / `dev-down.sh`, and `docs/local-development.md`. No AWS account is involved
and nothing costs money.

## Why the Mac

A1's acceptance includes the CLAUDE.md done-flow (register → log food → toggle sets →
weight → theme switch → delete account) **from the iOS Simulator**, against the
containerized API. The WSL box has no Xcode, so it cannot prove that half. The Mac proves
both halves in one place.

`.pipeline/` is gitignored and machine-local, so a run cannot be started on one machine
and finished on another. This run starts and ends on the Mac.

## Before starting the run

**Run `bash scripts/mac-preflight.sh` first.** It checks every step below and prints a
PASS/WARN/FAIL line each, with the fix command on every failure. It changes nothing: no
installs, no services started, and it never writes a `.pipeline` run marker. The steps
are spelled out here anyway, because the script reports what is wrong, not why it
matters.

**Three failures were expected on this Mac's first run of it** (as written 2026-10-16),
because the machine had been idle since 2026-08-26 while the repo moved on:

| Expected | Why | Status as of 2026-10-19 |
|---|---|---|
| `gh auth` | tokens expire; the WSL box's died after ~6 weeks, and this one was last used 2026-08-26 | **did not occur** — the Mac's token was still valid |
| engine shebang fixes uncommitted | they had never been pushed (step 7) | **done** — pushed as `fix/macos-shebangs`; see step 7 |
| `pyjwt` / `urllib3` / `mako` behind the lockfile | three CVE bumps landed 2026-10-03 and 2026-10-12 | **done** — `poetry install` re-synced the venv |

The 2026-10-19 pre-flight also surfaced three the table did not predict, all since
resolved or reassigned: Docker unreachable (`colima start`), `alembic` not on `PATH`
(step 6 — activate the venv **before** running the pre-flight, or it reports a missing
alembic that is in fact installed), and no `.pipeline/` at all (step 5, now bootstrapped).

Anything else it reports is new information — read it rather than assuming it is stale
state.


1. `cd ~/repos/orbit-fitness-app && git checkout main && git pull`
   - Three PRs merged on 2026-10-03: the AWS Lambda compute decision + the StoreKit spec
     (#6), CVE bumps for pyjwt/urllib3 plus a rate-limit test de-flake (#7), and this
     checklist. The A1 brief changed in #6, so confirm the pull landed before reading it.
2. **Re-sync the Python deps** (`poetry install`, or `pip install -e .` in the venv).
   PR #7 bumped `pyjwt` 2.13.0 → 2.15.1 and `urllib3` 2.7.0 → 2.8.0 in `poetry.lock`, so a
   venv from before 2026-10-03 is now behind the lockfile. Leaving it stale is how the
   Tier-2 rate-limit test's `check_revoked` race shows up again (it passed locally on the
   old pyjwt and failed twice in CI on the new one).
3. `gh auth status` — the deployment stage needs it
   ([`docs/mac-session-handoff.md`](mac-session-handoff.md)).
4. Start the stack: `brew services start postgresql@16 redis`, plus Colima for Docker
   (`colima start`). The full restart recipe is in `docs/mac-session-handoff.md`.
5. **Bootstrap `.pipeline/` FIRST, then record the waivers — in that order.**

   `.pipeline/` is gitignored and machine-local, so a fresh clone has neither the
   directory nor `waivers.json`, and `record-waiver.sh` refuses outright without
   `.pipeline/state.json` ("not a bootstrapped pipeline project"). Recording the
   waivers before bootstrapping therefore cannot work — the order below is the
   dependency, not a preference. (Corrected 2026-10-19: this step previously named
   only the waivers, and on a machine with no `.pipeline/` it was unrunnable.)

   ```sh
   # Pass the smoke flags — a bare bootstrap does NOT write .pipeline/smoke.env, and
   # the hook's built-in defaults (`src.main:app`, `python -c "import src.main"`) are
   # wrong for this repo, which is `src.orbit.main:app`. Without them the smoke check
   # fails mid-run on a default that was never Orbit's. Nothing in the pre-flight
   # catches this, so it looks READY right up until the first stage that smokes.
   bash ~/.claude/pipeline-templates/bootstrap-project.sh \
     --start ".venv/bin/python -m uvicorn src.orbit.main:app --host 0.0.0.0 --port 8000" \
     --health "http://localhost:8000/health" \
     --test ".venv/bin/python -m pytest --cov=src --cov-fail-under=80"

   bash ~/.claude/hooks/record-waiver.sh                    # asvs / 6.3.3
   bash ~/.claude/hooks/record-waiver.sh                    # asvs / 6.2.x
   ```

   `src.orbit.main:app` needs no `PYTHONPATH`: `src/orbit/main.py` imports its own
   package relatively (`from .config.settings import …`), and `src/` resolves as a
   namespace package, so the CLAUDE.md form runs as written — verified by starting it
   and getting a 200 from `/health`.

   Then append a startup allowance, because `SMOKE_STARTUP_WAIT` is a **fixed sleep
   followed by a single curl**, not a retry budget — an app slower than the wait fails
   outright. A cold start measured 3s here against the 5s default, on a Mac at ~95%
   disk with the simulator, Postgres, Redis and the emulator resident:

   ```sh
   echo 'export SMOKE_STARTUP_WAIT=12' >> .pipeline/smoke.env
   ```

   Confirm it works before starting the run — `bash ~/.claude/hooks/smoke-check.sh`
   should print `PASS — http://localhost:8000/health responded 200` and exit 0.

   One caveat if you pass `--start`/`--test`: bootstrap also derives Bash allow rules
   into `.claude/settings.json`, which IS tracked. On this repo it added only
   `Bash(.venv/bin/python -m:*)`, already covered by the existing
   `Bash(.venv/bin/python:*)` — a redundant no-op worth reverting to keep the tree
   clean. Check `git status` after bootstrapping and revert if that is all it did.

   Bootstrap is safe to re-run: every write is guarded by a `[skip] already exists`
   check, so a committed `CLAUDE.md`, `.claude/settings.json`, skills and CI workflow
   are left alone. On an already-bootstrapped machine it is a no-op and you can skip
   straight to checking `waivers.json`.

   **`record-waiver.sh` must be run BY A HUMAN, in a real terminal.** It refuses
   without a TTY on purpose — "a subagent must not waive on your behalf" — and a
   Claude Code session's Bash tool has no controlling terminal, so asking the session
   to run it will fail by design, not by accident. The guard is enforced four ways:
   the TTY check, `guard-approval-markers.sh` blocking agent writes to `waivers.json`,
   a settings Write/Edit deny, and `deployment-gate.sh` cross-checking every waiver
   the security agent CLAIMED against this file.

   The two greenfield waivers, both type `asvs` (reasons verbatim from
   [`docs/decisions/feature/greenfield/pr-description.md`](decisions/feature/greenfield/pr-description.md)):
   - `6.3.3` — MFA / combination of single factors: out of scope for the greenfield run
   - `6.2.x` — password composition/breach/length policy: delegated to Firebase, with
     the enable-at-deploy follow-up (discharged by the E-phase run per
     [`docs/roadmap.md`](roadmap.md))

   Each prompt ends with a literal confirmation — type `waive`, not `y`. Without these
   two entries the security stage re-flags both as new findings.
6. **Put the venv's `bin` on `PATH`** (or activate it). The Postgres fixture shells out to
   `alembic` by name; without it, every DB-backed integration module errors at setup with
   `FileNotFoundError: 'alembic'`. This cost time on the WSL box on 2026-10-03.
7. **Push the engine clone's macOS shebang fixes upstream — before refreshing that
   clone.** Three hooks (`asvs-sast.sh`, `tree-hygiene`, `doc-identifiers`) use the
   bash-4+ builtin `mapfile` under a hardcoded `#!/bin/bash`, which macOS's bash 3.2
   cannot run; `PATH` cannot fix a shebang and SIP forbids replacing `/bin/bash`. The
   pre-authorized fix (`#!/usr/bin/env bash`) was applied on 2026-08-24 but **exists only
   in this Mac's `~/repos/claude-agentic-workflow` clone, uncommitted**
   ([`docs/mac-session-handoff.md`](mac-session-handoff.md),
   [`plans/00-mac-pipeline-readiness.md`](../plans/00-mac-pipeline-readiness.md) § the
   shebang trap). So:
   **Done 2026-10-19** — pushed as `fix/macos-shebangs` on
   `bretthinkle123/claude-agentic-workflow`, so a clone refresh can no longer lose it.
   **Still open: that branch is not merged to `main` yet.** Until it is, a machine that
   clones the engine fresh gets the broken hooks back.

   The fix went wider than the three. All 28 remaining `#!/bin/bash` shebangs moved to
   `#!/usr/bin/env bash` (the repo was already 64-to-25 in favour of the portable form,
   so this aligned stragglers with its own convention), and a new `portability` suite in
   `tests/run-eval.sh` now fails the harness if any reappear — the three historic hooks
   are also asserted by name. The other 25 were never broken; they simply used no bash-4
   builtin yet, which is a latent trap rather than a safe state.

   - `git -C ~/repos/claude-agentic-workflow status` — if edits are ever uncommitted
     again, push them as a **topic branch** (e.g. `fix/macos-shebangs`) and merge to
     `main`. The fix is strictly more portable, so both machines want it.
   - **No per-machine branches** in that repo: its convention is topic branches
     (`feat/…`, `docs/…`, `audit/…`) merging to `main`, and the installer installs from
     whatever clone it runs in — two long-lived machine branches would mean two engines
     with no source of truth.
   - Refreshing or reinstalling the clone before pushing silently reverts all three
     hooks.
8. **Confirm `.pipeline/` has no in-flight run marker.** On WSL an aborted A1 attempt from
   2026-09-06 left `state.json` + `run-started` behind; they were archived to
   `.pipeline/archive/aborted-a1-20260906/`. Handle any Mac leftovers the same way —
   move, don't delete.

## Decisions the run will ask about

[`plans/A1-local-environment.md`](../plans/A1-local-environment.md) § "Decisions for run
start" carries these in full. In short:

1. **Lambda runner: now, or in A2?** The deploy target is AWS Lambda as of 2026-09-19
   ([`plans/A2-production-terraform-authoring.md`](../plans/A2-production-terraform-authoring.md)
   § Compute decision). A1 builds the Dockerfile but A2 picks the runner (Lambda Web
   Adapter vs Mangum). So either A1 adds the adapter now on A2's recommendation, or it
   ships a plain uvicorn image and A2/E1 add the Lambda pieces. Either way, nothing
   Lambda-specific goes in `src/orbit/` (CLAUDE.md).
2. **Multi-arch digest.** Pin a multi-arch manifest digest for the base image, not a
   per-architecture one: the Mac is arm64 and the WSL box is amd64, and a per-arch digest
   pinned on one will not run on the other.
3. **Port conflicts.** The Mac already runs brew `postgresql@16` on 5432 and `redis` on
   6379, which compose will collide with unless host ports are remapped or `dev-up.sh`
   detects it and says so.
4. **LocalStack terms** — confirm what its free offering currently includes and requires.
   The fallback is moto server.
5. **Local Terraform state** — plain local backend, or S3 + DynamoDB on LocalStack (the
   better lesson).
6. **CI** — does CI get a LocalStack service container, or do tests stay on the current
   testcontainers path?

## Context that changed since the Mac last saw this repo

- **Compute target is AWS Lambda**, not ECS Fargate or App Runner. Decided 2026-09-19 on
  cost at the expected launch scale (1–3 users). The rationale and the open sub-decisions
  (front door, WAF placement, client-IP source, NAT on the per-request hot path, DB
  connections, the separate migration function, the CodeDeploy alias canary) are in A2's
  § Compute decision. A1 only needs to know the Dockerfile must also be Lambda-runnable.
- **The AWS account is created at the start of E1**, not before, so the free plan's
  credits aren't spent during local development
  ([`plans/E1-production-deploy-path.md`](../plans/E1-production-deploy-path.md) § cost
  model). Everything through Phase D is $0 and local.
- **StoreKit monetization is specced but NOT scheduled**
  ([`docs/specs/storekit-monetization.md`](specs/storekit-monetization.md)). Do not pull it
  into any run; it is gated on the owner's freemium decision at the roadmap's go-live gate.
- `deploy.yml` and `load-campaign.yml` are still ECS-shaped and carry header notes saying
  A2 rewrites them. Both stay inert (`DEPLOY_ENABLED` unset). Not A1's job.
- The iOS app, its test suites and the pipeline engine were all green on this Mac as of
  PR #3: 142 backend tests, 157 Swift unit tests, 12 XCUITests, and 259 engine eval checks
  across 18 suites (`docs/mac-session-handoff.md`).

## At A1 closeout: where this file's contents go

Retire this file, but **move its durable parts rather than deleting them** — that is the
structure for every later repo handoff:

- **The generic pre-flight** (steps 1–8 above, minus the PR-specific notes) folds into
  [`docs/mac-session-handoff.md`](mac-session-handoff.md), which is already the Mac
  environment reference. Then every future run inherits it instead of rediscovering
  `alembic` on `PATH`, the waiver re-recording, and the engine shebangs.
- **The A1-specific parts** (its six run-start decisions, the "context that changed"
  section) die with the run. The decisions are recorded in A1's own brief and, once taken,
  in the run's retained artifacts under `docs/decisions/feature/<feature>/`.
- **Future runs do not need a file like this.** A run's brief in `plans/`, the roadmap's
  standing rules, and `docs/mac-session-handoff.md` are the handoff. Write a per-run
  checklist only when a run changes machines, or carries a cross-machine trap (the
  multi-arch digest and the brew port collision are why A1 got one).

## Honesty rules that apply to this run

- **Standing rule 5** ([`docs/roadmap.md`](roadmap.md)): an acceptance item only real AWS
  or a physical device can prove is **never faked locally** — it is recorded as owed to the
  named Phase E run. A1's live-only gap list already names Lambda cold
  starts/concurrency/VPC networking, the front door + WAF, IAM enforcement, RDS and
  ElastiCache behavior, real alarm delivery, and quotas.
- Native iOS is **reduced assurance** for the deterministic gates (CLAUDE.md). Never
  describe the Swift side as gate-verified.
