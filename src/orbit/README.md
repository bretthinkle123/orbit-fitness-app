# `src/orbit/` — FastAPI backend

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

The Orbit backend: a thin, owner-scoped REST API over PostgreSQL, fronting the iOS
client. Every domain row is scoped by Firebase UID (`owner_uid`); every collection read
is day-/window-bounded with a hard `LIMIT`. Full deterministic gate coverage (pytest,
Semgrep, OSV, Checkov) — the reduced-assurance stance applies to `ios/Orbit/`, not here.

## Modules

| Module | Responsibility |
|---|---|
| `main.py` | `create_app()` — builds the FastAPI app, registers the edge-middleware stack once (request-ID/trace → security headers → CORS → Tier-1 throttle → auth → Tier-2 throttle → error envelope), mounts every router (`health`, `me`, `profile`, `fuel`, `train`, `body`, `weight`). |
| `models.py` | SQLAlchemy 2.0 ORM models for all 9 tables (`profiles`, `muscle_base_levels`, `quick_foods`, `food_entries`, `programs`, `exercises`, `set_events`, `weight_entries`, plus the `muscle_level_templates` seed table). |
| `auth/` | `require_auth` / `require_fresh_reauth` facade — Firebase ID-token verification, revocation-aware. |
| `config/` | `Settings` (env config) + `get_secret()` (Secrets Manager/SSM facade). |
| `crypto/` | `hash_uid()` — the one place uid-pseudonymization for logs happens. |
| `edge/` | ASGI-level facades: security headers, CORS, request-size cap, two-tier rate limiter, error-envelope. |
| `lifecycle/` | `erase_account_rows()` — the atomic multi-table account-deletion cascade. |
| `logging/` | structlog facade — `get_logger()`, `request_logger` middleware, central PII redaction. |
| `observability/` | `init_sentry()` — thin, release-tagged Sentry init with PII suppression. |
| `repositories/` | Owner-scoped, bounded data-access functions per aggregate (one file per domain). |
| `routes/` | FastAPI routers — one file per resource, thin (validate → repository call → response schema). |
| `schemas/` | Pydantic v2 request/response models — every body/query contract (`extra="forbid"` + typed bounds). |

## Relationships

`main.py` is the composition root: it is the only place the middleware stack and routers
are assembled. Request flow is **routes → schemas (validate) → repositories (owner-scoped
query) → models (ORM)**, with `auth.require_auth` injected as a FastAPI dependency ahead
of every protected route so `owner_uid` is always derived from the verified token, never
the request body. `edge/`, `logging/`, `crypto/`, `config/`, `observability/` are cross-cutting
facades imported by the above rather than importing each other.

### `auth/`

| File | Responsibility |
|---|---|
| `__init__.py` | `require_auth(request)` — extracts + verifies the bearer token, returns normalized claims; `require_fresh_reauth` — additionally requires `auth_time` within 5 minutes (used by `DELETE /me`). |
| `firebase.py` | `verify_id_token()`, `revoke_refresh_tokens()`, `delete_firebase_user()` — the only module that calls the Firebase Admin SDK directly; lazy app init is double-checked-locked. |

### `edge/`

| File | Responsibility |
|---|---|
| `headers.py` | `SecurityHeadersMiddleware` — HSTS, `nosniff`, CSP, `X-Frame-Options: DENY`, referrer policy, on every response including errors. |
| `cors.py` | `register_cors(app)` — explicit origin allowlist, never `*` with credentials. |
| `ratelimit.py` | `EdgeThrottleMiddleware` (Tier-1, IP-keyed, pre-auth, `/health` exempt) + `require_resource_throttle` (Tier-2, uid-keyed, post-auth, on write routes) — shared Redis store, fail-open with a `warn` log on Redis unavailability. |
| `bodysize.py` | `RequestSizeLimitMiddleware` — rejects a declared `Content-Length` over 64 KiB with `413` before routing. |
| `errors.py` | `install_error_handlers(app)` — the error-envelope facade; maps DB constraint violations and validation errors to 4xx, everything else to a generic `500` (no stack/SQL/type/path to the client). |

### `repositories/`

| File | Responsibility |
|---|---|
| `base.py` | `resolve_database_url()`, `get_engine()`, `get_sessionmaker()`, `dispose_engine()` — engine construction; the DB credential is re-resolved through the secrets facade on each physical connection (rotation-aware). |
| `profile.py` | `get_profile()`, `bootstrap_profile()` (atomic idempotent create-if-absent), `update_profile()` (allowlisted PATCH). |
| `fuel.py` | `list_quick_foods()`, `create_food_entry()` (≤200/day cap, advisory-lock guarded), `get_fuel_day_entries()` (day-scoped + bounded). |
| `train.py` | `get_program_with_exercises()`, `get_day_set_events()`, `get_week_set_events()`, `mark_set_done()` / `unmark_set()` (idempotent on the `(uid, exercise, set, day)` unique key). |
| `body.py` | `get_muscle_levels()`, `get_trained_muscle_groups_today()` (derives glow from today's `set_events`). |
| `weight.py` | `create_weight_entry()`, `get_window_entries()` (fixed 30-day window + hard `LIMIT`). |

### `lifecycle/`

`erase_account_rows(session, owner_uid)` — deletes `food_entries`, `set_events`,
`weight_entries`, `muscle_base_levels`, `profiles` for the uid in one transaction (a
fault-injected failure mid-cascade rolls the whole thing back, per the test suite);
`routes/me.py`'s `DELETE /me` calls this, then deletes the Firebase identity.

## Notes

- Blocking Firebase Admin SDK calls (`verify_id_token`, `revoke_refresh_tokens`,
  `delete_firebase_user`) and the secrets-facade DB-URL resolution run via
  `anyio.to_thread.run_sync` — they must never sit directly on the event loop (security
  finding, fixed this run).
- No route ever accepts an id path parameter — every resource is scoped by
  `(owner_uid, day_key)` derived from the verified token, so the classic IDOR surface is
  structurally absent.
- `GET /health` has zero external dependencies (no DB/Firebase/Redis) and is exempt from
  the Tier-1 throttle — the smoke check depends on this.
