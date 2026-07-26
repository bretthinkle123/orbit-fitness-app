#!/usr/bin/env bash
# run_perf.sh — stands up an OUT-OF-PROCESS Orbit API (uvicorn, a real ASGI
# server, never the in-process TestClient the pytest suite uses) plus a real
# Postgres, Redis, and Firebase Auth emulator, migrates the schema, runs the
# k6 perf harness (`k6_orbit.js`) against it once end-to-end, and tears
# everything down. This is the mechanism plan.md §Test strategy names for
# AC23 ("out-of-process uvicorn + testcontainers Postgres") — driven here via
# plain `docker run`/CLI subprocesses (bash, not testcontainers-python) since
# this script is an operational harness, not a pytest test.
#
# k6 itself runs in Docker (`grafana/k6`). This host's Docker runs in its own
# network namespace (verified empirically: a plain `--network host` container
# could NOT reach a host-bound loopback listener), so k6 reaches the
# out-of-process app/emulator via `host.docker.internal` instead — the app
# and the Firebase emulator are both bound to 0.0.0.0 (not 127.0.0.1) so
# Docker's bridge network can actually reach them from that address.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP_PORT="${APP_PORT:-8010}"
POSTGRES_PORT="${POSTGRES_PORT:-5544}"
REDIS_PORT="${REDIS_PORT:-6390}"
FIREBASE_EMULATOR_PORT="${FIREBASE_EMULATOR_PORT:-9099}"
FIREBASE_PROJECT_ID="demo-orbit-test"

POSTGRES_CONTAINER="orbit-perf-postgres"
REDIS_CONTAINER="orbit-perf-redis"
UVICORN_PID=""
FIREBASE_PID=""

cleanup() {
  echo "--- tearing down perf harness ---"
  [ -n "$UVICORN_PID" ] && kill "$UVICORN_PID" 2>/dev/null || true
  [ -n "$FIREBASE_PID" ] && kill "$FIREBASE_PID" 2>/dev/null || true
  docker rm -f "$POSTGRES_CONTAINER" "$REDIS_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "--- starting Postgres + Redis ---"
docker run -d --rm --name "$POSTGRES_CONTAINER" -p "${POSTGRES_PORT}:5432" \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=orbit_perf postgres:16-alpine >/dev/null
docker run -d --rm --name "$REDIS_CONTAINER" -p "${REDIS_PORT}:6379" redis:7-alpine >/dev/null

export DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:${POSTGRES_PORT}/orbit_perf"
export REDIS_URL="redis://localhost:${REDIS_PORT}/0"
export FIREBASE_PROJECT_ID
export FIREBASE_AUTH_EMULATOR_HOST="localhost:${FIREBASE_EMULATOR_PORT}"

echo "--- waiting for Postgres to accept connections ---"
for _ in $(seq 1 30); do
  docker exec "$POSTGRES_CONTAINER" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done

echo "--- running migrations against the perf Postgres ---"
poetry run alembic upgrade head

echo "--- starting the Firebase Auth emulator (bound 0.0.0.0 per firebase.json, so Docker's bridge network can reach it) ---"
firebase emulators:start --only auth --project "$FIREBASE_PROJECT_ID" \
  >/tmp/orbit-perf-firebase-emulator.log 2>&1 &
FIREBASE_PID=$!
for _ in $(seq 1 45); do
  curl -sf "http://${FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${FIREBASE_PROJECT_ID}/config" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://${FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${FIREBASE_PROJECT_ID}/config" >/dev/null || {
  echo "Firebase emulator never became ready — see /tmp/orbit-perf-firebase-emulator.log"
  cat /tmp/orbit-perf-firebase-emulator.log
  exit 1
}

echo "--- starting uvicorn (out-of-process, bound 0.0.0.0) on port ${APP_PORT} ---"
poetry run python -m uvicorn src.orbit.main:app --host 0.0.0.0 --port "$APP_PORT" \
  >/tmp/orbit-perf-uvicorn.log 2>&1 &
UVICORN_PID=$!
for _ in $(seq 1 30); do
  curl -sf "http://localhost:${APP_PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://localhost:${APP_PORT}/health" >/dev/null || {
  echo "uvicorn never became healthy — see /tmp/orbit-perf-uvicorn.log"
  cat /tmp/orbit-perf-uvicorn.log
  exit 1
}

echo "--- running k6 (Docker; reaches the host via host.docker.internal) ---"
docker run --rm --add-host=host.docker.internal:host-gateway \
  -v "$PWD/tests/perf:/scripts" \
  -e "BASE_URL=http://host.docker.internal:${APP_PORT}" \
  -e "FIREBASE_AUTH_EMULATOR_HOST=host.docker.internal:${FIREBASE_EMULATOR_PORT}" \
  -e "FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID}" \
  grafana/k6 run /scripts/k6_orbit.js
