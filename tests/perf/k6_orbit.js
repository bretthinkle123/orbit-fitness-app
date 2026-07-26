/**
 * k6 performance harness (AC23; plan §Test strategy) — measures the p95 <
 * 300ms budget @ ~10 concurrent on GET /fuel, GET /train, and POST
 * /fuel/entries against an OUT-OF-PROCESS uvicorn (never the in-process
 * TestClient the pytest suite uses — that would measure test-harness
 * overhead, not the real network/ASGI-server path this budget is about).
 *
 * Run via Docker (`grafana/k6`) with `--network host` so the container can
 * reach the host-published app/Postgres/Redis/Firebase-emulator ports
 * (`run_perf.sh` drives the full out-of-process setup + this run + teardown).
 *
 * Scenario shape: one short, unmeasured WARM-UP phase (excludes JIT/pool-
 * warmup latency from the recorded thresholds, per plan §Test strategy's
 * "warm-up excluded"), then three sequential `constant-arrival-rate`
 * scenarios — one per named endpoint — each its own ~10 req/s arrival rate.
 * k6's Trend metric retains every sample by default (no down-sampling), so
 * `p(95)` is a true nearest-rank percentile, not an HDR-histogram estimate.
 *
 * Each measured phase is deliberately short (~6s @ 10/s = ~60 requests, plus
 * warmup's own light traffic on the same path) so the total per-(IP, path)
 * request count this run generates stays UNDER the app's own real Tier-1
 * edge-throttle budget (100 requests / 60s / (IP, path) — `edge/
 * ratelimit.py`) — this harness measures the real, unmodified request path,
 * including its own abuse-prevention limits, so the synthetic load must
 * respect them rather than tripping a 429 that would masquerade as latency.
 */

import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const FIREBASE_EMULATOR_HOST = __ENV.FIREBASE_AUTH_EMULATOR_HOST || 'localhost:9099';
const FIREBASE_PROJECT_ID = __ENV.FIREBASE_PROJECT_ID || 'demo-orbit-test';
// A fixed day for the whole run — every POST in this run shares one
// (owner_uid, day_key) bucket, so the total iteration budget below is kept
// comfortably under the app's <=200/day cap (repositories/fuel.py).
const PERF_DAY_KEY = __ENV.PERF_DAY_KEY || new Date().toISOString().slice(0, 10);

const ARRIVAL_RATE_PER_SECOND = 10; // the "~10 concurrent" budget AC23 names

export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-arrival-rate',
      exec: 'warmup',
      rate: 3,
      timeUnit: '1s',
      duration: '8s',
      preAllocatedVUs: 5,
      maxVUs: 10,
      startTime: '0s',
      // No `scenario:warmup`-tagged threshold below — this phase is
      // deliberately EXCLUDED from the measured p95 (JIT/connection-pool
      // warm-up is not representative of steady-state latency).
    },
    get_fuel: {
      executor: 'constant-arrival-rate',
      exec: 'getFuel',
      rate: ARRIVAL_RATE_PER_SECOND,
      timeUnit: '1s',
      duration: '6s',
      preAllocatedVUs: 15,
      maxVUs: 30,
      startTime: '10s',
    },
    get_train: {
      executor: 'constant-arrival-rate',
      exec: 'getTrain',
      rate: ARRIVAL_RATE_PER_SECOND,
      timeUnit: '1s',
      duration: '6s',
      preAllocatedVUs: 15,
      maxVUs: 30,
      startTime: '18s',
    },
    post_fuel_entry: {
      executor: 'constant-arrival-rate',
      exec: 'postFuelEntry',
      rate: ARRIVAL_RATE_PER_SECOND,
      timeUnit: '1s',
      duration: '6s',
      preAllocatedVUs: 15,
      maxVUs: 30,
      startTime: '26s',
    },
  },
  thresholds: {
    // AC23's budget, scoped per named endpoint via the scenario tag k6
    // attaches automatically — the warm-up phase carries no threshold at
    // all, so it can never mask (or pollute) a measured endpoint's p95.
    'http_req_duration{scenario:get_fuel}': ['p(95)<300'],
    'http_req_duration{scenario:get_train}': ['p(95)<300'],
    'http_req_duration{scenario:post_fuel_entry}': ['p(95)<300'],
  },
};

/** Mint a real Firebase ID token via the Auth emulator's Identity Toolkit
 * REST API (Operator addendum #1 — no mocked guard, even for perf) and
 * bootstrap the profile (`GET /fuel`/`GET /train` both 404 pre-bootstrap). */
export function setup() {
  const email = `k6-perf-${Date.now()}@example.com`;
  // Both the API key and password below are throwaway, emulator-only values
  // (the emulator never reaches a real Google endpoint and ignores the key
  // entirely) — same non-secret rationale as `tests/conftest.py`'s
  // `_EMULATOR_API_KEY`/`_TEST_USER_PASSWORD`, never a real credential.
  const signUpResponse = http.post(
    `http://${FIREBASE_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    JSON.stringify({ email: email, password: 'K6PerfRun123!', returnSecureToken: true }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(signUpResponse, { 'setup: firebase signup succeeded': (r) => r.status === 200 });
  const idToken = signUpResponse.json('idToken');

  const authHeaders = { headers: { Authorization: `Bearer ${idToken}`, 'Content-Type': 'application/json' } };
  const bootstrapResponse = http.post(`${BASE_URL}/me/bootstrap`, null, authHeaders);
  check(bootstrapResponse, { 'setup: bootstrap succeeded': (r) => r.status === 200 });

  return { idToken: idToken };
}

function authHeaders(idToken) {
  return { headers: { Authorization: `Bearer ${idToken}`, 'Content-Type': 'application/json' } };
}

/** Unmeasured warm-up traffic across all three endpoints — no assertions
 * beyond "didn't error," since this phase carries no threshold. */
export function warmup(data) {
  http.get(`${BASE_URL}/fuel?day_key=${PERF_DAY_KEY}`, authHeaders(data.idToken));
  http.get(`${BASE_URL}/train?day_key=${PERF_DAY_KEY}`, authHeaders(data.idToken));
}

/** Representative read #1 (AC23). */
export function getFuel(data) {
  const response = http.get(`${BASE_URL}/fuel?day_key=${PERF_DAY_KEY}`, authHeaders(data.idToken));
  check(response, { 'GET /fuel: 200': (r) => r.status === 200 });
}

/** Representative read #2 (AC23). */
export function getTrain(data) {
  const response = http.get(`${BASE_URL}/train?day_key=${PERF_DAY_KEY}`, authHeaders(data.idToken));
  check(response, { 'GET /train: 200': (r) => r.status === 200 });
}

/** Representative write (AC23) — explicit-macro path, so no dependency on
 * the seeded quick-food catalog's row ids. */
export function postFuelEntry(data) {
  const body = JSON.stringify({
    meal_group: 'snacks',
    day_key: PERF_DAY_KEY,
    logged_at: new Date().toISOString(),
    name: 'k6 perf entry',
    kcal: 100,
    protein_g: 5,
    carb_g: 10,
    fat_g: 2,
  });
  const response = http.post(`${BASE_URL}/fuel/entries`, body, authHeaders(data.idToken));
  check(response, { 'POST /fuel/entries: 201': (r) => r.status === 201 });
}
