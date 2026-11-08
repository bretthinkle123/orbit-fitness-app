#!/usr/bin/env bash
# Stop the local stack. Volumes (Postgres data, Firebase emulator users) are KEPT by default.
#
#   scripts/dev-down.sh [--clean]      --clean also deletes the volumes (a full reset)
#
# bash 3.2 compatible (macOS).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
dc() { docker compose --env-file "$REPO_ROOT/.env.local" -f "$REPO_ROOT/docker-compose.yml" "$@"; }

TF_DIR="infra/envs/local"
CLEAN=0

usage() {
  echo "usage: scripts/dev-down.sh [--clean]" >&2
  exit 2
}

for argument in "$@"; do
  case "$argument" in
    --clean) CLEAN=1 ;;
    *) usage ;;
  esac
done

[ -f "$REPO_ROOT/.env.local" ] || { echo "[dev-down] .env.local missing; create it with: cp .env.local.example .env.local" >&2; exit 1; }

moto_container="$(dc ps -q --status running moto 2>/dev/null || true)"
if [ -n "$moto_container" ] && [ "$(docker inspect --format '{{.State.Health.Status}}' "$moto_container")" = "healthy" ]; then
  echo "[dev-down] destroying Terraform resources in moto"
  # Non-fatal: moto is about to be removed, and the next dev-up re-converges from empty state.
  TF_IN_AUTOMATION=1 terraform -chdir="$TF_DIR" destroy -auto-approve -input=false \
    || echo "[dev-down] warning: terraform destroy failed; continuing (moto state is discarded anyway)" >&2
else
  echo "[dev-down] moto is not running; skipping terraform destroy (state converges on the next dev-up)"
fi

if [ "$CLEAN" -eq 1 ]; then
  dc down -v
  # With the S3 backend the state lived in moto and is already gone; only a local backend leaves files.
  if [ ! -f "$REPO_ROOT/$TF_DIR/backend.tf" ]; then rm -f "$REPO_ROOT/$TF_DIR"/terraform.tfstate*; fi
  echo "[dev-down] volumes removed (--clean)"
else
  dc down
  echo "[dev-down] volumes kept; use --clean for a full reset"
fi

echo "[dev-down] note: the Terraform destroy succeeds here even though, in real AWS, the observability"
echo "           module's log-group delete-deny policy would block it. moto does not enforce IAM or"
echo "           resource policies (a live-only gap)."
