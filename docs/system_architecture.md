# System architecture — Orbit

> Cross-cutting: how the pieces fit together end-to-end. For what a single directory
> does, see that directory's own README. Regenerate only the diagram a change affects.

This is the **greenfield** architecture: native SwiftUI iOS client → FastAPI backend →
PostgreSQL, fronted by Firebase Auth, on an AWS data-security baseline (compute deferred).
See `docs/decisions/feature/greenfield/plan.md` for the full STRIDE threat model this
architecture is held to.

## 1. System context

```mermaid
flowchart LR
    iOS[Orbit iOS app — SwiftUI] -->|"HTTPS + Bearer Firebase ID token"| API[FastAPI backend]
    iOS -->|email/password register / sign-in| Firebase[Firebase Auth]
    Firebase -->|ID token| iOS
    API -->|verify_id_token / revoke_refresh_tokens / delete_user| Firebase
    API -->|owner-scoped, bounded SQL| DB[(PostgreSQL — RDS)]
    API -->|rate-limit counters| Redis[(ElastiCache Redis)]
    API -->|get_secret| Secrets[(AWS Secrets Manager / SSM)]
    API -->|structured logs| CloudWatch[(CloudWatch: app + audit log groups)]
    API -->|traces| XRay[(AWS X-Ray)]
    API -->|error events| Sentry[(Sentry)]
    CI[GitHub Actions CI] -->|OIDC assume-role| AWS[(AWS control plane)]
```

Firebase owns password storage, KDF, and breach policy — the backend never receives a
raw password, only verifies signed ID tokens. Every domain row in PostgreSQL is scoped by
`owner_uid` (the Firebase UID); no local PII beyond that opaque key (email/display name
stay in Firebase).

## 2. Request lifecycle (edge middleware chain)

Every request passes through the same middleware stack, registered once in
`src/orbit/main.py`:

```mermaid
flowchart TD
    Client[iOS client] --> ReqID[Request-ID / trace middleware]
    ReqID --> Headers[Security headers]
    Headers --> CORS[CORS allowlist]
    CORS --> Tier1["Tier-1 edge throttle — IP + route keyed (Redis); /health exempt"]
    Tier1 --> BodySize[Request-size cap — 64 KiB declared Content-Length]
    BodySize --> Auth["require_auth — verify_id_token(check_revoked=True)"]
    Auth --> Tier2["Tier-2 resource throttle — uid-keyed (write routes only)"]
    Tier2 --> Handler[Route handler]
    Handler --> Repo[Repository — owner-scoped, bounded query]
    Repo --> Postgres[(PostgreSQL)]
    Handler --> Envelope[Error-envelope boundary]
    Envelope --> Response["JSON response / {error:{code,message,requestId}}"]
```

The order is `create_app()`'s registration in `main.py` (Starlette runs the last-added
middleware outermost). `GET /health` is exempt from the Tier-1 throttle, so it never touches
Redis, and it never reaches `auth`
— it has no external dependency, by design (the smoke check's own contract). Write
routes (`POST /fuel/entries`, `POST`/`DELETE /train/sets`, `POST /weight`,
`PATCH /profile`, `POST /me/signout`, `DELETE /me`) are the only ones behind Tier-2;
`DELETE /me` additionally requires `require_fresh_reauth` (Firebase `auth_time` within 5
minutes) ahead of the handler.

## 3. Authentication

Firebase Auth owns identity (passwords, accounts, token issuance); the backend only
verifies Firebase ID tokens. On iOS, `Core/AuthService.swift` owns every runtime Firebase
call; the only other file importing `FirebaseAuth` is `App/OrbitApp.swift`, for
DEBUG-only emulator wiring and the UI-test auth reset (both compiled out of Release). On
the backend, `src/orbit/auth/firebase.py` is the only module that imports
`firebase_admin`, behind the `require_auth` / `require_fresh_reauth` facade in
`src/orbit/auth/__init__.py`.

**Sign-in and an authenticated request:**

```mermaid
sequenceDiagram
    participant App as iOS app (AuthService + APIClient)
    participant FB as Firebase Auth
    participant API as FastAPI (require_auth)
    participant DB as PostgreSQL

    App->>FB: signIn / createUser (email, password)
    FB-->>App: Firebase user
    App->>App: getIDToken, copy saved to Keychain
    Note over App: RootView switches to the tab shell
    App->>API: POST /me/bootstrap (on every tab-shell load)
    Note over API,DB: idempotent create-if-absent profile + defaults
    loop every API call
        App->>App: getIDToken(forcingRefresh: false) from the SDK cache
        opt token near expiry
            App->>FB: refresh ID token
            FB-->>App: new ID token
        end
        App->>API: request + Authorization: Bearer {ID token}
        alt header missing or malformed
            API-->>App: 401 (Firebase not contacted)
        else bearer token present
            API->>API: verify signature, exp, aud, iss (cached Google public keys)
            API->>FB: check_revoked: fetch user record (worker thread)
            FB-->>API: user record (tokens-valid-after, disabled)
            alt bad signature / expired / revoked / disabled / user not found
                API-->>App: 401 (same response whichever check failed)
            else valid
                API->>DB: query scoped by owner_uid = claims.uid
                DB-->>API: rows
                API-->>App: 2xx JSON
            end
        end
    end
```

The signature check is local, but `check_revoked=True` fetches the user record from
Firebase, so every authenticated request makes a round trip to Firebase. `owner_uid` always
comes from the verified claims, never from the request body.

**Sign-out** revokes the token server-side before discarding it locally:

```mermaid
sequenceDiagram
    participant App as iOS app (AuthService)
    participant API as FastAPI
    participant FB as Firebase Auth

    App->>API: POST /me/signout (Bearer token)
    alt request fails (network error or non-2xx)
        API-->>App: error
        Note over App: error shown, still signed in locally (nothing cleared)
    else success
        API->>FB: revoke_refresh_tokens(uid)
        API-->>App: 204
        App->>App: clear Keychain token
        App->>App: Auth.signOut() (SDK, local)
        Note over App: RootView switches to sign-in
    end
    Note over App,API: a token issued before the revocation now gets 401 on its next use
```

**Account deletion** additionally requires a recent login (`require_fresh_reauth`:
`auth_time` within 5 minutes). Any 401 on the first attempt opens the re-authentication
prompt. `AppStore.deleteAccount` then sends `DELETE /me` again with the old token *before*
re-authenticating, so a stale session makes three calls in total:

```mermaid
sequenceDiagram
    participant User
    participant App as iOS app (SettingsSheet + AppStore)
    participant FB as Firebase Auth
    participant API as FastAPI
    participant DB as PostgreSQL

    User->>App: Delete account, confirm
    App->>API: DELETE /me (cached token)
    opt 401, e.g. auth_time older than 5 min
        API-->>App: 401
        App->>User: re-authentication sheet
        User-->>App: email + password
        App->>API: DELETE /me (same cached token)
        API-->>App: 401 again
        App->>FB: reauthenticate + getIDToken(forcingRefresh: true)
        FB-->>App: fresh token (auth_time = now)
        App->>API: DELETE /me (fresh token), final attempt
    end
    API->>DB: erase all owner_uid rows (one transaction)
    DB-->>API: committed
    API->>FB: delete_user(uid)
    alt identity delete fails
        API-->>App: 502 (retry-safe: the row erase is now a no-op)
    else
        API-->>App: 204
        Note over App: RootView switches to sign-in (the Firebase SDK session and Keychain token are not cleared)
    end
```

## 4. Data model

```mermaid
erDiagram
    PROFILES ||--o{ MUSCLE_BASE_LEVELS : "owner_uid"
    PROFILES ||--o{ FOOD_ENTRIES : "owner_uid"
    PROFILES ||--o{ SET_EVENTS : "owner_uid"
    PROFILES ||--o{ WEIGHT_ENTRIES : "owner_uid"
    PROGRAMS ||--|{ EXERCISES : "program_id"
    EXERCISES ||--o{ SET_EVENTS : "exercise_id"

    PROFILES {
        string owner_uid PK
        int kcal_budget
        int protein_target_g
        int carb_target_g
        int fat_target_g
        int score_base
        string tier_label
        string percentile_label
        int next_tier_pct
        string palette_preset
        string units
        string gender
        int planet_index
        int burned_kcal "nullable, always NULL until HealthKit (C6)"
        float burn_rate "nullable, always NULL until HealthKit (C6)"
        datetime created_at
    }
    MUSCLE_BASE_LEVELS {
        string owner_uid PK
        string muscle_group PK
        int level "1-6"
    }
    QUICK_FOODS {
        int id PK
        string name
        int kcal
        float protein_g
        float carb_g
        float fat_g
    }
    FOOD_ENTRIES {
        int id PK
        string owner_uid
        string name
        int kcal
        float protein_g
        float carb_g
        float fat_g
        string meal_group
        datetime logged_at
        date day_key
        datetime created_at
    }
    PROGRAMS {
        int id PK
        string name
        string focus
        int est_minutes
    }
    EXERCISES {
        int id PK
        int program_id FK
        int order_index
        string name
        int sets
        int reps
        float weight "prescribed"
        string muscle_tag
    }
    SET_EVENTS {
        int id PK
        string owner_uid
        int exercise_id FK
        int set_index
        datetime done_at
        date day_key
    }
    WEIGHT_ENTRIES {
        int id PK
        string owner_uid
        float weight_kg
        date day_key
        datetime logged_at
        datetime created_at
    }
```

`MUSCLE_LEVEL_TEMPLATES` (a 4th global/seed table, not shown above — same shape as
`MUSCLE_BASE_LEVELS` but with no `owner_uid`) holds the per-user defaults
`POST /me/bootstrap` copies on account creation; it is a judgment-call addition beyond
the plan's literal table list, and brings the schema to 9 tables (see
`migrations/README.md`). `QUICK_FOODS`,
`PROGRAMS`/`EXERCISES`, and `MUSCLE_LEVEL_TEMPLATES` are global seed/reference data with
no owner; every other table carries `owner_uid` and is scoped + bounded
(`food_entries` ≤200/day, `weight_entries` 30-day window, both hard `LIMIT`s) at the
repository layer.

**`QUICK_FOODS` deliberately has no edge to `FOOD_ENTRIES`.** A quick-add copies the
catalog row's name and macros into the entry at logging time; `food_entries` carries no
`quick_food_id` column and no FK (`repositories/fuel.py`). The persisted entry is a
**snapshot**, so re-pricing or correcting a catalog row never retroactively rewrites what
a user already logged — and an entry survives its catalog row being removed.

## 5. Deployment topology

**Where things stand:** the backend runs as a direct process (`uvicorn`) on the
developer's machine against a local Postgres, a local Redis and the Firebase Auth
emulator, with the iOS Simulator as the client. Development stays local-first until an
explicit go-live decision (`docs/roadmap.md`). The Terraform below is **authored but has
never been applied** to any AWS account (`offline_validate=true`); the diagram shows the
target it describes.

**Authored in `infra/` (never applied) — the data-security baseline:**

```mermaid
flowchart TD
    subgraph Provisioned_this_run [infra/ — authored, not applied]
        VPC[VPC + private subnets]
        RDS[(RDS PostgreSQL — storage_encrypted, multi-AZ, force_ssl)]
        ElastiCache[(ElastiCache Redis — at-rest + in-transit encrypted)]
        SecretsMgr[(Secrets Manager + SSM)]
        LogGroups[(CloudWatch app + audit log groups — delete-deny policy)]
        VPC --- RDS
        VPC --- ElastiCache
    end

    Process[uvicorn — direct process, single worker] -->|asyncpg| RDS
    Process -->|redis-py| ElastiCache
    Process -->|get_secret| SecretsMgr
    Process -->|structlog| LogGroups

    CI2[GitHub Actions] -.->|"terraform apply (deploy.yml, DEPLOY_ENABLED gate)"| Provisioned_this_run
```

**Deferred (authored in A2 — `plans/A2-production-terraform-authoring.md`; applied at
go-live in E1 — `plans/E1-production-deploy-path.md`): the compute path.**
`deploy.yml` already scaffolds the target shape (verify signed image → `terraform apply`
→ migrate → canary rollout by ALB target-group weight, staging before prod, human
approval gate on the `production` environment) — but `infra/` does not yet define the
ALB, ECS cluster/service, or the `envs/` staging/prod split it targets. A1 adds
`envs/local` (LocalStack); A2 authors the rest; E1 applies it:

```mermaid
flowchart LR
    Internet((Internet)) --> ALB[ALB / target groups — NOT YET PROVISIONED]
    ALB --> ECS[ECS service — NOT YET PROVISIONED]
    ECS --> RDS2[(RDS — authored, not applied)]
    ECS --> Redis2[(ElastiCache — authored, not applied)]
    ALB -.->|"trusted XFF CIDR (ProxyHeadersMiddleware) — configure when this lands"| ECS
```

The Tier-1 rate limiter's `ProxyHeadersMiddleware` XFF-trust configuration is a **latent**
item that only activates once an ALB exists (security-report row 30) — deliberately left
unconfigured this run because there is no trusted proxy CIDR yet; configuring it against
no ALB would let any client spoof `X-Forwarded-For` and bypass the throttle.
