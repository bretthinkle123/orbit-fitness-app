# Mac pipeline-readiness runbook (self-contained — read me first)

_Audience: a fresh Claude Code session on the operator's MacBook Air (M2), with NO other
context. Your job: verify this Mac can run the Orbit pipeline end-to-end, FIX what you
safely can, and end with an explicit verdict. The operator will say something like
"read plans/00-mac-pipeline-readiness.md and tell me if this machine is ready" — this
file is the entire brief. (Runbook v2 — adversarially audited 2026-07-24 against the
actual engine scripts; the BSD/GNU section below reflects grep-verified reality, not
folklore.)_

## The verdict you must produce (contract)

End your run with exactly this structure:
1. A gap table: `check | status (pass/fixed/BLOCKED) | action taken or needed`.
2. Two verdict lines:
   - `iOS BUILD/TEST READY: YES|NO` — can this Mac build the app in Xcode, run its
     test suites, and execute the XCUITest smoke flow?
   - `FULL PIPELINE READY: YES|NO` — can this Mac run complete pipeline feature runs
     (all agents, gates, scanners, hooks)?
3. If either is NO: the exact remaining steps, separated into "I can do this if you
   authorize" vs "only the operator can do this" (App Store sign-ins, purchases, auth).
4. Append a dated one-line result to the "## Verification log" at the bottom of this
   file (e.g. `- 2026-07-20: FULL=NO (Xcode missing), iOS=NO — gaps: …`).

## What the pipeline is (context)

A multi-agent SDLC pipeline ("engine") installed into `~/.claude` — 46 entries in
`~/.claude/hooks/` (41 `.sh` hook scripts + support files: an egress proxy dir, a `.jq`
predicate, allowlist `.txt`s, a `.mjs`), 10 agent definitions in `~/.claude/agents/`
(planning, plan-audit, implementation, security, testing, debugging, documentation,
deployment, design-spec, triage), templates in `~/.claude/pipeline-templates/`, plus
skills. Source of truth: **https://github.com/bretthinkle123/claude-agentic-workflow** —
installer: `scripts/install-global.sh` (run from the engine clone; `dry-run` and
`--force` flags exist, see Phase 1). The app repo (orbit-fitness-app) carries per-run
state in a gitignored `.pipeline/` directory. The engine was built on WSL/Linux; **the
two real macOS risk classes (grep-verified) are: (a) bash-4+ builtins under hardcoded
`#!/bin/bash` shebangs — macOS ships bash 3.2 at /bin/bash and SIP prevents replacing
it — and (b) GNU-only flags or commands missing from stock macOS (`stat -c`,
`sha256sum`, `timeout`, `date -d`).**

**WSL-side prerequisite (operator, before the first Mac readiness run):** push the
engine repo from the WSL machine — at audit time `~/repos/claude-agentic-workflow` was
2 commits ahead of origin/main with 1 untracked file; a Mac clone of origin today gets
a stale engine.

## Fix policy (what you may do without asking)

- MAY: `brew`/`npm`/`pipx` install missing tools; clone the engine repo and run
  `scripts/install-global.sh`; prepend GNU gnubin dirs to PATH in the shell profile;
  pull Docker images; create scratch files for probes.
- MAY (pre-authorized portability fix): change a hook's hardcoded `#!/bin/bash` shebang
  to `#!/usr/bin/env bash` **in the ENGINE CLONE**, then re-run `install-global.sh` —
  required for the three `mapfile` hooks below; PATH cannot fix a shebang and SIP
  forbids touching `/bin/bash`. Every such edit MUST be listed prominently in your
  verdict with "operator: commit this upstream (or apply the equivalent upstream fix)".
- MUST NOT: create any `.pipeline/*-approved` marker (human-only, ever); copy a
  `.pipeline/` directory from another machine; edit any hook logic beyond the shebang
  line above.
- ASK THE OPERATOR for: Apple ID / App Store sign-in (Xcode), `gh auth login`,
  Docker Desktop first-launch, anything needing a password or purchase.

## Phase 0 — things only the operator can install (detect, then instruct)

| Check | Command | If missing |
|---|---|---|
| Full Xcode (not just CLT) | `xcodebuild -version` | Operator installs Xcode from the App Store (~several GB), then `sudo xcodebuild -license accept` and `sudo xcode-select -s /Applications/Xcode.app` |
| iOS Simulator runtime | `xcrun simctl list devices available \| grep -i iphone` | Xcode ▸ Settings ▸ Components — download an iOS runtime |
| Docker Desktop | `docker info` | Operator installs Docker Desktop for Mac (Apple silicon) and launches it once |
| Homebrew | `command -v brew` | Operator installs from https://brew.sh (needs sudo once) |
| GitHub auth | `gh auth status` | Operator runs `gh auth login` (browser flow) |

Environment notes: Rosetta is NOT required (every tool and Docker image named here
ships arm64). If this is the 8 GB Air: Docker Desktop + Xcode + a booted Simulator
concurrently will swap hard — run Phase 3/5 steps sequentially, quit Docker Desktop
while doing Simulator-heavy work where possible, and expect slowness, not failure.

## Phase 1 — engine install + the (real) macOS compatibility gauntlet

1. Clone and enter it: `git clone https://github.com/bretthinkle123/claude-agentic-workflow
   ~/repos/claude-agentic-workflow && cd ~/repos/claude-agentic-workflow`. Preview:
   `bash scripts/install-global.sh dry-run` — on a collision report (differing files
   already in `~/.claude` that aren't its own prior install), STOP and show the
   operator the list before using `--force`; on a clean or identical-files report,
   install: `bash scripts/install-global.sh`.
   (The installer itself is bash-3.2-clean — verified.)
2. Verify install: `ls ~/.claude/hooks | wc -l` (expect ~46 entries),
   `ls ~/.claude/agents` (the 10 named above),
   `~/.claude/pipeline-templates/bootstrap-project.sh` exists.
3. **Install modern GNU userland + bash 5 BEFORE any test run:**
   `brew install bash coreutils gnu-sed grep gawk findutils jq git` then prepend to the
   shell profile: `PATH="$(brew --prefix coreutils)/libexec/gnubin:$(brew --prefix
   gnu-sed)/libexec/gnubin:$(brew --prefix grep)/libexec/gnubin:$PATH"` and open a
   fresh shell. What this actually fixes (grep-verified inventory):
   - `sha256sum` (18 call sites; absent on stock macOS) → coreutils gnubin.
   - `stat -c` (`hooks/log-run.sh`, `scripts/preserve-transcripts.sh`) → gnubin `stat`.
   - `timeout` (`hooks/notify-checkpoint.sh`) → gnubin.
   - `date -d` (`hooks/log-run.sh`, has an `|| echo 0` fallback) → gnubin.
   - `sed -i` suffix-less (`scripts/bootstrap-project.sh` — runs on this Mac in
     Phase 4) → gnu-sed gnubin.
   - `declare -A` in `scripts/list-skills.sh` (`env bash` shebang) → brew bash 5 on
     PATH.
4. **The shebang trap (PATH cannot fix these):** three hooks use `mapfile` (a bash-4+
   builtin) under a hardcoded `#!/bin/bash` shebang — `asvs-sast.sh`,
   `check-doc-identifiers.sh`, `guard-tree-hygiene.sh`. Settings invoke hooks by
   absolute path, so macOS runs them with /bin/bash = bash 3.2 → runtime failure in
   three gate hooks that `bash -n` syntax checks do NOT catch. Apply the pre-authorized
   fix: in the engine clone, change those three shebangs to `#!/usr/bin/env bash`,
   re-run `install-global.sh`, and flag for upstream commit in your verdict.
5. **Run the engine's FULL eval:** `bash tests/run-eval.sh` in the engine clone (runs
   all suites). Do NOT settle for `suites/static.sh` + `suites/next-stage.sh` alone —
   static.sh is `bash -n` + wiring checks and next-stage.sh never executes the mapfile
   hooks, so those two pass on a machine where three gate hooks are runtime-broken.
   The full eval is the only honest FULL-PIPELINE-READY evidence. Failures that pass
   on Linux are portability bugs: fix via Phase-1 steps 3–4 if possible, otherwise
   report as engine gaps.
6. `bash ~/.claude/hooks/check-run-host.sh` — no Darwin branch exists: on macOS it
   falls through to the generic else and **exits 2 with a misleading "running on the
   Windows host" message. This is expected and ADVISORY on a Mac** (the /mnt/OneDrive
   risks it hunts don't exist on APFS). Report the verdict verbatim, don't block on
   it, and note the missing Darwin branch as an engine gap for the operator.

## Phase 2 — pipeline toolchain (install what's missing, then re-verify)

| Tool | Check | Install |
|---|---|---|
| python3.12 | `python3.12 --version` | `brew install python@3.12` |
| git identity | `git config user.name && git config user.email` | `git config --global user.name/user.email` (ask operator for values) — **deployment commits/PRs fail without it** |
| jq / curl / unzip | `command -v …` | jq via Phase 1 brew; rest ship with macOS |
| gh | `gh --version` | `brew install gh` (+ Phase-0 auth) |
| semgrep | `semgrep --version` | `brew install semgrep` |
| osv-scanner | `osv-scanner --version` | `brew install osv-scanner` |
| checkov | `checkov --version` | `brew install checkov` (or `brew install pipx && pipx install checkov`) |
| terraform | `terraform version` | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| node + npm | `node --version` | `brew install node` |
| firebase CLI | `firebase --version` | `npm i -g firebase-tools` |
| Java 11+ (emulator dep) | `java -version` | `brew install --cask temurin` |
| ast-grep (security stage, advisory) | `ast-grep --version` | `brew install ast-grep` |
| gitleaks (secrets scan) | `gitleaks version` | `brew install gitleaks` |

## Phase 3 — functional probes (prove it, don't assume it)

1. Docker real work: `docker run --rm hello-world`; pull the images pipeline stages
   use: `docker pull postgres:16-alpine` (**likely tag — reconfirm against the app's
   testcontainers config once the code exists; the plan pins no Postgres version**),
   `docker pull redis:7-alpine`, `docker pull grafana/k6`. All are arm64-native.
2. Firebase Auth emulator boots: in a scratch dir, `echo '{}' > firebase.json` (guards
   against CLI versions that want a config present), then `firebase emulators:start
   --only auth --project demo-orbit` → wait for "All emulators ready", then kill it.
   The `demo-` project-id prefix is documented offline behavior — no `firebase login`
   needed; first run downloads the emulator JAR (network) and needs Java 11+.
3. Terraform offline: scratch dir with a trivial `main.tf` (`terraform {}`), run
   `terraform init -backend=false && terraform validate`.
4. Xcode real work: `xcodebuild -showsdks` lists an iphonesimulator SDK; boot a
   simulator once: `xcrun simctl boot "<any iPhone>" && xcrun simctl shutdown all`.

## Phase 4 — app repo state (rules that prevent self-inflicted wounds)

- Clone the app repo fresh (ask the operator for the URL/transfer if no GitHub remote
  exists yet). **`.pipeline/` is gitignored and does NOT travel with the clone — this is
  by design.** For a new run on this Mac: `bash
  ~/.claude/pipeline-templates/bootstrap-project.sh` from the repo root re-creates it.
- **Never copy `.pipeline/` (especially `*-approved` markers) from the WSL machine.**
  Approvals are per-checkpoint human artifacts; a new run gets new ones.
- Do not attempt to RESUME a run that is mid-checkpoint on another machine. One run,
  one host. Mac runs start fresh features (see `docs/roadmap.md` for the ordered list;
  each run's brief is in `plans/`).
- Backend expectations on this Mac: Python 3.12 venv, `pytest` with testcontainers
  (Docker), Firebase auth via the emulator (`FIREBASE_AUTH_EMULATOR_HOST`), Redis via
  Docker. No AWS credentials are required for validation (the infra uses an
  `offline_validate` tfvars pattern — see the plan's Operator addendum).

## Phase 5 — post-greenfield iOS verification (only once greenfield has merged)

1. Open `ios/Orbit/Orbit.xcodeproj`; build for an iPhone simulator.
2. Run the Swift Testing/XCTest unit suites and snapshot tests.
3. Start the backend locally (uvicorn + Docker Postgres/Redis + auth emulator), point
   the app's API base URL at it, and run the XCUITest smoke:
   register → sign in → quick-add food → toggle sets → log weight → switch palette/units
   → delete account. This is AC27's real execution — the reduced-assurance closure the
   Linux pipeline could not perform.
4. Report any failure as a finding against the app (route to a debugging run), not
   something to patch ad-hoc on the Mac.

## Verification log

_(appended by each readiness run — newest last)_
