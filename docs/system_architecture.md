# System architecture — Orbit

> Cross-cutting: how the pieces fit together end-to-end. For what a single directory
> does, see that directory's own README. Regenerate only the diagram a change affects.

This is the **greenfield** architecture: native SwiftUI iOS client → FastAPI backend →
PostgreSQL, fronted by Firebase Auth, on an AWS data-security baseline (compute deferred).
See `.pipeline/plan.md` (retained at `docs/decisions/feature/greenfield/plan.md`) for the
full STRIDE threat model this architecture is held to.

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
    CORS --> BodySize[Request-size cap — 64 KiB declared Content-Length]
    BodySize --> Tier1["Tier-1 edge throttle — IP-keyed (Redis); /health exempt"]
    Tier1 --> Auth["require_auth — verify_id_token(check_revoked=True)"]
    Auth --> Tier2["Tier-2 resource throttle — uid-keyed (write routes only)"]
    Tier2 --> Handler[Route handler]
    Handler --> Repo[Repository — owner-scoped, bounded query]
    Repo --> Postgres[(PostgreSQL)]
    Handler --> Envelope[Error-envelope boundary]
    Envelope --> Response["JSON response / {error:{code,message,requestId}}"]
```

`GET /health` short-circuits before the Tier-1 throttle touches Redis and before `auth`
— it has no external dependency, by design (the smoke check's own contract). Write
routes (`POST /fuel/entries`, `POST`/`DELETE /train/sets`, `POST /weight`,
`PATCH /profile`, `POST /me/signout`, `DELETE /me`) are the only ones behind Tier-2;
`DELETE /me` additionally requires `require_fresh_reauth` (Firebase `auth_time` within 5
minutes) ahead of the handler.

## 3. Data model

```mermaid
erDiagram
    PROFILES ||--o{ MUSCLE_BASE_LEVELS : "owner_uid"
    PROFILES ||--o{ FOOD_ENTRIES : "owner_uid"
    PROFILES ||--o{ SET_EVENTS : "owner_uid"
    PROFILES ||--o{ WEIGHT_ENTRIES : "owner_uid"
    PROGRAMS ||--|{ EXERCISES : "program_id"
    EXERCISES ||--o{ SET_EVENTS : "exercise_id"
    QUICK_FOODS ||--o{ FOOD_ENTRIES : "quick_food_id (optional)"

    PROFILES {
        string owner_uid PK
        int kcal_budget
        int protein_target_g
        int carb_target_g
        int fat_target_g
        int score_base
        string tier_label
        string palette_preset
        string units
        string gender
        int planet_index
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
        string meal_group
        datetime logged_at
        date day_key
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
    }
```

`MUSCLE_LEVEL_TEMPLATES` (a 4th global/seed table, not shown above — same shape as
`MUSCLE_BASE_LEVELS` but with no `owner_uid`) holds the per-user defaults
`POST /me/bootstrap` copies on account creation; it is a judgment-call addition beyond
the plan's literal 9-table list (see `migrations/README.md`). `QUICK_FOODS`,
`PROGRAMS`/`EXERCISES`, and `MUSCLE_LEVEL_TEMPLATES` are global seed/reference data with
no owner; every other table carries `owner_uid` and is scoped + bounded
(`food_entries` ≤200/day, `weight_entries` 30-day window, both hard `LIMIT`s) at the
repository layer.

## 4. Deployment topology

**Current (this run) — direct process, data-security baseline only:**

```mermaid
flowchart TD
    subgraph Provisioned_this_run [infra/ — provisioned]
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

**Deferred (run 1 — `plans/01-production-deploy-path.md`): the compute path.**
`deploy.yml` already scaffolds the target shape (verify signed image → `terraform apply`
→ migrate → canary rollout by ALB target-group weight, staging before prod, human
approval gate on the `production` environment) — but `infra/` does not yet provision the
ALB, ECS cluster/service, or the `envs/` staging/prod split it targets:

```mermaid
flowchart LR
    Internet((Internet)) --> ALB[ALB / target groups — NOT YET PROVISIONED]
    ALB --> ECS[ECS service — NOT YET PROVISIONED]
    ECS --> RDS2[(RDS — provisioned)]
    ECS --> Redis2[(ElastiCache — provisioned)]
    ALB -.->|"trusted XFF CIDR (ProxyHeadersMiddleware) — configure when this lands"| ECS
```

The Tier-1 rate limiter's `ProxyHeadersMiddleware` XFF-trust configuration is a **latent**
item that only activates once an ALB exists (security-report row 30) — deliberately left
unconfigured this run because there is no trusted proxy CIDR yet; configuring it against
no ALB would let any client spoof `X-Forwarded-For` and bypass the throttle.
