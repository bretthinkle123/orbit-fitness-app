#!/usr/bin/env bash
# mac-preflight.sh — read-only pre-flight for starting a pipeline run on the Mac.
#
# Checks the environment described in docs/a1-run-start.md and prints one line per
# check plus a verdict. It CHANGES NOTHING: no installs, no services started, no
# .pipeline markers written (creating a run marker is the pipeline's job, never a
# check's). Every FAIL line says what to run to fix it.
#
# Usage:  bash scripts/mac-preflight.sh
#
# Written for macOS (bash 3.2-safe: no mapfile, no associative arrays), but it runs
# on Linux too — the Xcode and brew checks will report SKIP there.

set -u

PASS=0; FAIL=0; WARN=0
ENGINE="${ENGINE_CLONE:-$HOME/repos/claude-agentic-workflow}"

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL  %s\n        -> %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
warn() { printf '  WARN  %s\n        -> %s\n' "$1" "$2"; WARN=$((WARN+1)); }
skip() { printf '  SKIP  %s\n' "$1"; }
head_() { printf '\n%s\n' "$1"; }

cd "$(dirname "$0")/.." || exit 1
IS_MAC=0; [ "$(uname -s)" = "Darwin" ] && IS_MAC=1

head_ "1. Repository"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$BRANCH" = "main" ] && ok "on main" || warn "on branch '$BRANCH', not main" "git checkout main (a run branches off main)"
git fetch -q origin 2>/dev/null
LOCAL="$(git rev-parse HEAD 2>/dev/null)"; REMOTE="$(git rev-parse origin/main 2>/dev/null)"
if [ "$LOCAL" = "$REMOTE" ]; then ok "up to date with origin/main ($(git rev-parse --short HEAD))"
else bad "behind or ahead of origin/main" "git pull"; fi
if [ -z "$(git status --porcelain)" ]; then ok "working tree clean"
else warn "working tree has local changes" "commit or stash before starting a run"; fi

head_ "2. Python dependencies match the lockfile"
PY="./.venv/bin/python"; [ -x "$PY" ] || PY="python3"
for pkg in pyjwt:jwt urllib3:urllib3 mako:mako; do
  name="${pkg%%:*}"; mod="${pkg##*:}"
  want="$(awk -v n="$name" '$0=="name = \""n"\"" {found=1; next} found && /^version = /{gsub(/[",]/,"",$3); print $3; exit}' poetry.lock)"
  have="$($PY -c "import $mod,sys; sys.stdout.write(getattr($mod,'__version__','?'))" 2>/dev/null)"
  if [ -z "$have" ]; then bad "$name not importable" "poetry install"
  elif [ "$have" = "$want" ]; then ok "$name $have matches lockfile"
  else bad "$name installed $have, lockfile wants $want" "poetry install  (a stale venv reintroduces the check_revoked test race)"; fi
done

head_ "3. GitHub CLI"
if ! command -v gh >/dev/null 2>&1; then bad "gh not installed" "brew install gh"
elif gh auth status >/dev/null 2>&1; then ok "gh authenticated"
else bad "gh token invalid or expired" "gh auth login -h github.com  (the deployment stage needs it)"; fi

head_ "4. Local services"
if [ "$IS_MAC" = "1" ]; then
  for svc in postgresql@16 redis; do
    if brew services list 2>/dev/null | grep -q "^$svc .*started"; then ok "$svc running"
    else bad "$svc not started" "brew services start $svc"; fi
  done
else skip "brew services (not macOS)"; fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ok "docker reachable (testcontainers + LocalStack need it)"
else bad "docker not reachable" "colima start"; fi
if command -v java >/dev/null 2>&1; then ok "java present (Firebase Auth emulator needs it)"
else bad "java missing" "install a JDK and set JAVA_HOME"; fi
if command -v firebase >/dev/null 2>&1; then ok "firebase CLI present"
else bad "firebase CLI missing" "npm i -g firebase-tools"; fi
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:9099 -sTCP:LISTEN >/dev/null 2>&1; then
  warn "port 9099 already bound" "another project's auth emulator squatting there fails the suite with 401s"
else ok "port 9099 free for the auth emulator"; fi

head_ "5. Pipeline waivers (machine-local, gitignored)"
if [ -f .pipeline/waivers.json ]; then
  miss=""
  grep -q '6\.3\.3' .pipeline/waivers.json || miss="$miss 6.3.3"
  grep -q '6\.2\.x' .pipeline/waivers.json || miss="$miss 6.2.x"
  if [ -z "$miss" ]; then ok "waivers.json has both greenfield ASVS waivers"
  else bad "waivers.json missing:$miss" "re-record with record-waiver.sh, or security re-flags them"; fi
else bad ".pipeline/waivers.json absent" "re-record the greenfield waivers (ASVS 6.3.3, 6.2.x) with record-waiver.sh"; fi

head_ "6. alembic on PATH"
if command -v alembic >/dev/null 2>&1; then ok "alembic resolves ($(command -v alembic))"
else bad "alembic not on PATH" "activate the venv — the Postgres fixture shells out to 'alembic' by name"; fi

head_ "7. Engine clone"
if [ ! -d "$ENGINE/.git" ]; then skip "engine clone not at $ENGINE (set ENGINE_CLONE=...)"
else
  DIRTY="$(git -C "$ENGINE" status --porcelain 2>/dev/null | head -20)"
  SHEBANG_DIRTY=0
  for h in asvs-sast tree-hygiene doc-identifiers; do
    echo "$DIRTY" | grep -q "$h" && SHEBANG_DIRTY=1
  done
  if [ "$SHEBANG_DIRTY" = "1" ]; then
    bad "the macOS shebang fixes are still uncommitted in the engine clone" \
        "push them as a topic branch BEFORE refreshing that clone, or all three mapfile hooks break"
  else ok "no uncommitted shebang fixes pending"; fi
  AHEAD="$(git -C "$ENGINE" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
  [ "${AHEAD:-0}" -gt 0 ] && warn "engine clone is $AHEAD commit(s) ahead of origin" "push them, or another machine gets a stale engine" || ok "engine clone not ahead of origin"
fi
if [ -d "$HOME/.claude/agents" ]; then
  n="$(ls "$HOME/.claude/agents" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -ge 10 ] && ok "engine installed ($n agent definitions in ~/.claude/agents)" || warn "only $n agent definitions found" "re-run install-global.sh from the engine clone"
else bad "~/.claude/agents missing" "run scripts/install-global.sh from the engine clone"; fi

head_ "8. Bootstrapped, with no run already in flight"
# `state.json` is NOT a run marker. `bootstrap-project.sh` creates it as the project
# seed (`{"debug_retry_count":…,"max_retries":3}`), and approve-plan.sh,
# approve-diff.sh and record-waiver.sh all REFUSE without it ("not a bootstrapped
# pipeline project"). This check used to list it as a leftover and advise archiving
# it — following that would have broken the waiver recorder, the very thing check 5
# tells you to run. `run-started` is the real per-feature anchor: dast-review.sh and
# log-run.sh both date their evidence against it.
#
# The absent case is a FAIL, not a pass. Before 2026-10-19 this check reported
# "no in-flight run marker" on a project with no `.pipeline/` AT ALL, so a machine
# that had never been bootstrapped looked clean here while check 5 failed for a
# reason it could not explain.
if [ -f .pipeline/run-started ]; then
  warn "leftover marker: run-started" "if no run is active, move it to .pipeline/archive/<name>/ — move, don't delete"
elif [ -f .pipeline/state.json ]; then
  ok ".pipeline bootstrapped, no in-flight run"
else
  bad ".pipeline/state.json absent — project never bootstrapped" "bash ~/.claude/pipeline-templates/bootstrap-project.sh  (record-waiver.sh in check 5 refuses without it)"
fi

head_ "9. iOS toolchain"
if [ "$IS_MAC" = "1" ]; then
  if command -v xcodebuild >/dev/null 2>&1; then ok "xcodebuild present ($(xcodebuild -version 2>/dev/null | head -1))"
  else bad "xcodebuild missing" "install Xcode + command line tools"; fi
  if command -v xcodegen >/dev/null 2>&1; then ok "xcodegen present"
  else bad "xcodegen missing" "brew install xcodegen"; fi
  if command -v xcrun >/dev/null 2>&1; then
    SIMS="$(xcrun simctl list devices available 2>/dev/null | grep -c 'iPhone')"
    [ "${SIMS:-0}" -gt 0 ] && ok "$SIMS iPhone simulator(s) available" || bad "no iPhone simulators available" "install a simulator runtime in Xcode"
  fi
else skip "Xcode toolchain (not macOS — the iOS half of a run cannot be proven here)"; fi

head_ "Verdict"
printf '  %d passed, %d warnings, %d failures\n\n' "$PASS" "$WARN" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  NOT READY — resolve each FAIL above, then re-run."; exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "  READY, with warnings — read each WARN and decide."; exit 0
else
  echo "  READY — start the run by pointing the session at the run's brief in plans/."; exit 0
fi
