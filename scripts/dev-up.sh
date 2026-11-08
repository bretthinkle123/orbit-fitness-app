#!/usr/bin/env bash
# Bring up the local stack (postgres, redis, moto, Firebase Auth emulator, the API) and seed it.
#
#   scripts/dev-up.sh [--rebuild]
#
# The api image is rebuilt on every run, from the layer cache, before migrate, so source and
# migration edits always reach both migrate and api; an unchanged tree rebuilds in seconds.
# --rebuild builds the api and Firebase emulator images with --no-cache, from nothing, so it
# takes minutes rather than seconds. Use it for a suspect cache or after editing
# docker/firebase-emulator/, which a plain run does not rebuild.
#
# Idempotent and convergent: every step is safe to repeat, and a run that failed or was
# interrupted part-way is fixed by running it again. moto keeps everything in memory, so each
# run re-creates its bucket, Terraform resources and the database-url secret; that is expected.
# bash 3.2 compatible (macOS): no mapfile, no associative arrays.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
dc() { docker compose --env-file "$REPO_ROOT/.env.local" -f "$REPO_ROOT/docker-compose.yml" "$@"; }

MOTO_ENDPOINT="http://localhost:5001"
TF_DIR="infra/envs/local"
PYTHON="$REPO_ROOT/.venv/bin/python"
PUBLISHED_PORTS="8080 5433 6380 9100 5001"
REBUILD=0

usage() {
  echo "usage: scripts/dev-up.sh [--rebuild]" >&2
  exit 2
}

for argument in "$@"; do
  case "$argument" in
    --rebuild) REBUILD=1 ;;
    *) usage ;;
  esac
done

CURRENT_STEP="start"
STEP_STARTED=$SECONDS

begin_step() { CURRENT_STEP="$1"; STEP_STARTED=$SECONDS; }
end_step() { echo "[dev-up] step=$CURRENT_STEP status=ok elapsed_s=$((SECONDS - STEP_STARTED))"; }
on_exit() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    echo "[dev-up] step=$CURRENT_STEP status=fail elapsed_s=$((SECONDS - STEP_STARTED))" >&2
    echo "[dev-up] the half-up stack is left in place for diagnosis; re-run scripts/dev-up.sh to converge" >&2
  fi
}
trap on_exit EXIT

fail() { echo "[dev-up] error: $*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------------------------

port_owner_service() {
  case "$1" in
    8080) echo api ;; 5433) echo postgres ;; 6380) echo redis ;; 9100) echo firebase-emulator ;; 5001) echo moto ;;
  esac
}

check_ports_free_or_ours() {
  local running port service listener
  running="$(dc ps --services --status running 2>/dev/null || true)"
  for port in $PUBLISHED_PORTS; do
    listener="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1 " (pid " $2 ")"}' || true)"
    service="$(port_owner_service "$port")"
    # An if (not `[ ] && continue`): a false test as the loop's last command would trip set -e.
    if [ -n "$listener" ] && ! printf '%s\n' "$running" | grep -qx "$service"; then
      fail "host port $port is in use by $listener and is not this project's $service; free it, then re-run"
    fi
  done
}

version_at_least() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | sed -n 1p)" = "$1" ]; }

preflight() {
  docker info >/dev/null 2>&1 || fail "Docker is not reachable; start it with: colima start"
  command -v terraform >/dev/null 2>&1 || fail "terraform not found; install it with: brew install hashicorp/tap/terraform"
  local terraform_version
  # sed (not head) reads all of the output, so pipefail cannot see a SIGPIPE.
  terraform_version="$(terraform version | sed -n '1s/^Terraform v//p')"
  version_at_least "1.11.0" "$terraform_version" || fail "terraform $terraform_version is older than 1.11; upgrade it"
  [ -x "$PYTHON" ] || fail "$PYTHON missing; create it with: python3.12 -m venv .venv && .venv/bin/pip install boto3 requests"
  [ -f "$REPO_ROOT/.env.local" ] || fail ".env.local missing; create it with: cp .env.local.example .env.local  (then replace every CHANGE_ME, e.g. openssl rand -hex 24)"
  dc version >/dev/null 2>&1 || fail "the compose plugin is missing; install it with: brew install docker-compose"
  AWS_ENDPOINT_URL="$MOTO_ENDPOINT" "$PYTHON" -m scripts.dev.local_aws validate-env --env-file "$REPO_ROOT/.env.local"
  check_ports_free_or_ours
}

# Every published port must listen on loopback only (STRIDE I1); lsof, not the compose syntax,
# is the enforcing check because it looks at what the Mac actually exposes.
assert_loopback_only() {
  local port listeners
  for port in "$@"; do
    listeners="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' || true)"
    [ -n "$listeners" ] || fail "nothing is listening on port $port"
    printf '%s\n' "$listeners" | grep -vE '^(127\.0\.0\.1|\[::1\]):' >/dev/null && fail "port $port is listening beyond loopback: $listeners"
  done
  return 0
}

local_aws() { AWS_ENDPOINT_URL="$MOTO_ENDPOINT" "$PYTHON" -m scripts.dev.local_aws "$@"; }

# --- steps -------------------------------------------------------------------------------------

begin_step preflight; preflight; end_step

API_WAS_PRESENT="$(dc ps -q api 2>/dev/null || true)"

begin_step infra-up
# Compose builds the emulator image here if it is missing (first run only: npm install, slow).
if [ "$REBUILD" -eq 1 ]; then dc build --no-cache firebase-emulator; fi
dc up -d --wait postgres redis moto firebase-emulator
end_step

begin_step loopback-assert
assert_loopback_only 5433 6380 9100 5001
end_step

begin_step tf-state
# A Terraform run that lost moto mid-apply leaves errored.tfstate behind; it describes resources in
# a moto that no longer exists, so it is stale by construction.
rm -f "$TF_DIR/errored.tfstate"
# A freshly created state bucket means moto lost its in-memory state (recreated, restarted, or
# first run). That is the one reliable signal, whether the restart happened before or during this run.
# --report prints exactly one line on stdout (the summary goes to stderr); anything else is a
# broken contract and stops the run rather than silently skipping the api restart.
STATE_REPORT="$(local_aws ensure-state-backend --report)"
case "$STATE_REPORT" in
  state_bucket_created=1) MOTO_WAS_RESET=1 ;;
  state_bucket_created=0) MOTO_WAS_RESET=0 ;;
  *) fail "unexpected ensure-state-backend --report output: $STATE_REPORT" ;;
esac
TF_IN_AUTOMATION=1 terraform -chdir="$TF_DIR" init -input=false -reconfigure -backend-config=backend.moto.hcl >/dev/null
end_step

begin_step tf-apply
TF_IN_AUTOMATION=1 terraform -chdir="$TF_DIR" apply -auto-approve -input=false
end_step

begin_step seed-secrets
local_aws seed-secrets --env-file "$REPO_ROOT/.env.local"
end_step

# Before migrate: that service only names orbit-api:local (no build:), so without the image
# compose would try to pull it, and a stale image would run stale migrations.
begin_step api-build
if [ "$REBUILD" -eq 1 ]; then dc build --no-cache api; else dc build api; fi
end_step

begin_step migrate
dc run --rm migrate
end_step

begin_step api-up
# up recreates a running api container when the image it was started from has been replaced.
dc up -d --wait api
# After a moto reset the api (already running) may hold a cached secret for up to 900 s; a
# restart gives it a fresh facade instead of relying on that cache.
if [ -n "$API_WAS_PRESENT" ] && [ "$MOTO_WAS_RESET" -eq 1 ]; then
  dc restart api
  dc up -d --wait api
fi
assert_loopback_only 8080
end_step

begin_step seed
"$PYTHON" -m scripts.seed_dev_data --env-file "$REPO_ROOT/.env.local"
FIREBASE_AUTH_EMULATOR_HOST=localhost:9100 "$REPO_ROOT/scripts/seed_ui_test_user.sh"
end_step

begin_step health
curl -sf http://localhost:8080/health >/dev/null
end_step

begin_step report
echo "[dev-up] total wall time: ${SECONDS}s"
dc ps --format 'table {{.Name}}\t{{.Status}}'
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' $(dc ps -q)
echo "API: http://localhost:8080 | Simulator: Debug build | stop: scripts/dev-down.sh"
end_step
