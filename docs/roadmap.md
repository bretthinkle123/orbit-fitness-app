# Roadmap — ordered feature runs after greenfield

_Last updated 2026-09-18: reordered local-first. The single source of truth for what runs
after the greenfield run, **in execution order**. One pipeline run per entry; each starts
with `requirements-elicitation` reading its brief in [`plans/`](../plans/). The entries
here are one-line summaries; the briefs are the planning-stage context._

_History:_
- _Renamed from `docs/deferred.md`._
- _Reordered and re-lettered on 2026-09-18 (see the mapping table below)._
- _Runs are identified by **phase letter + name** (e.g. `C3 — program builder`). Frozen
  greenfield artifacts under `docs/decisions/feature/greenfield/` cite the old numbered
  paths (`plans/01-…`); the mapping table resolves them._

_Deferral rule used for the greenfield scope: a feature whose **flow the design depicts**
was built; a feature that existed in the design only as a button/label/number with no
flow behind it shipped as a stub/default and lives here._

_Not a run: [plans/00-mac-pipeline-readiness.md](../plans/00-mac-pipeline-readiness.md)
is a self-contained runbook a fresh Claude session on the operator's Mac executes to
verify (and fix) that machine's readiness to run this pipeline and build/test the iOS app._

## Development posture: local-first until an explicit go-live decision

The owner's goal is learning — building the app, and building and *maintaining* AWS
infrastructure. Until the owner explicitly decides to go live:
- **Every run through Phase D runs entirely locally:** the iOS Simulator + the Firebase
  Auth emulator + the A1 local stack (docker-compose Postgres/Redis + LocalStack for the
  AWS APIs + Terraform `envs/local`). Cost: $0.
- **All functionality works locally before anything App Store.** Phase E (deploy,
  live monitoring, App Store) is parked; its briefs keep their full go-live detail,
  including the cost model and the manual bootstrap steps in
  [E1](../plans/E1-production-deploy-path.md).
- The deploy workflows stay inert (`DEPLOY_ENABLED` unset).
- When going live, price AWS **hourly, not monthly**: apply → operate → break on purpose
  → `terraform destroy`. Leaving the stack running is only for once real users exist.

## Standing rules — every future run, non-negotiable (planning must honor these)

1. **Erasure/export parity.** Any run that adds an `owner_uid` table must, **in the same
   run**:
   - extend the `DELETE /me` cascade (`src/orbit/lifecycle/erase.py`) and the AC5 erasure
     test
   - register the table in the shared owner_uid-table registry

   The registry and its export ∪ erase parity test are built by **whichever run first
   adds an owner-scoped table**. That is expected to be **C3 — program builder**, unless
   **C1 — entry management** takes its "shared idempotency-keys table" option first (B1's
   `audit_events` is keyed by hashed uid and decides its own erasure basis). Whichever
   gets there first owns building it. D1's export reuses it.

   Account deletion must never under-erase, even for one run — AC5's "every domain table"
   and App Store 5.1.1(v) depend on it.
2. **Classification pass.** Any new stored personal field gets a data-protection
   classification row and the **B1/B2 controls** (audit events through the B1 facade;
   B2 field encryption where classified sensitive) in the same run. Phase B lands before
   the feature runs precisely so this rule is met as each table is added, not retrofitted.
3. **Standard shapes.** Every new endpoint inherits the greenfield adversarial set:
   - unauthenticated → 401
   - cross-owner → 404 (IDOR)
   - bounded reads (scope + hard LIMIT)
   - `extra="forbid"` validation
   - a rate-limit tier
   - audit events via the B1 facade
4. **Local-first infrastructure.**
   - A run that adds an AWS resource adds it to the shared Terraform module **and** to
     `envs/local` (if LocalStack supports it) **and** to the authored `envs/staging` +
     `envs/prod` (A2), all in the same run.
   - Local and live may differ **only in configuration and `.tfvars`**: never an
     environment branch in `src/orbit/`, and never a forked copy of a module.
   - IAM policies are written least-privilege even though LocalStack doesn't enforce them.
5. **Live-only honesty.** An acceptance item that only real AWS or a physical device can
   prove (IAM enforcement, network routing, alarm delivery, real camera, real HealthKit
   data) is **never faked locally**. It is recorded in the run's brief/PR as owed to the
   named Phase E run, which proves it.

## Run order

**Phase A — Local foundation**

- **A1 — Local environment.** Dockerfile, docker-compose (Postgres, Redis, Firebase
  emulator, LocalStack), Terraform `envs/local` applied to LocalStack, Simulator
  build config, `dev-up`/`dev-down`, and a learning doc on what local can't prove.
  → [plans/A1-local-environment.md](../plans/A1-local-environment.md)
- **A2 — Production Terraform, authored.** The staging/prod envs split, network
  completion (public subnets/NAT), compute, WAF, alarms, deploy/OIDC bootstrap stack and
  IAM, plus a cost estimate. Validated offline (`plan` + Checkov); **never applied**.
  → [plans/A2-production-terraform-authoring.md](../plans/A2-production-terraform-authoring.md)

**Phase B — Data-protection foundation** (before features, so every feature inherits it)

- **B1 — Append-only audit trail.** An audit facade and an append-only sink (DB role
  INSERT-only); who read or changed which record, never the values. This is the
  *security* log, distinct from users saving meals/workouts.
  → [plans/B1-audit-trail.md](../plans/B1-audit-trail.md)
- **B2 — Field encryption + consent.** KMS envelope encryption of health values via the
  crypto facade (KMS on LocalStack), the classification table, and a consent flow gating
  health-data writes. → [plans/B2-field-encryption-consent.md](../plans/B2-field-encryption-consent.md)

**Phase C — Features** (all local + Simulator)

1. **C1 — Entry management.** Edit/delete saved meals and weigh-ins, plus idempotency
   keys (no double-saved meal on a network retry).
   → [plans/C1-entry-management.md](../plans/C1-entry-management.md)
2. **C2 — Food logging integrations.** Search + **USDA FoodData Central** (free API key,
   called by the backend), then barcode scan (USDA-only; a miss → prefilled manual
   entry), then on-device nutrition-label OCR. Meal photos are deferred.
   → [plans/C2-food-logging-integrations.md](../plans/C2-food-logging-integrations.md)
3. **C3 — Program builder + workout logging.** User-owned programs, and saving performed
   sets (weight × reps), which C4/C5 need. The biggest run.
   → [plans/C3-program-builder.md](../plans/C3-program-builder.md)
4. **C4 — Muscle progression.** Body levels derived from lift history.
   → [plans/C4-muscle-derivation.md](../plans/C4-muscle-derivation.md)
5. **C5 — Strength tier & percentile.** Makes "Intermediate II / Top 22%" real; needs
   C3's performed-set data. → [plans/C5-tier-percentile.md](../plans/C5-tier-percentile.md)
6. **C6 — HealthKit activity.** Real "Burned +N", using Simulator sample data; before the
   coach. → [plans/C6-healthkit-activity.md](../plans/C6-healthkit-activity.md)
7. **C7 — Adaptive diet coach (TDEE engine).** Lazy weekly compute, verified against
   synthetic histories; available to all users (monetization is note-only — see Phase E).
   → [plans/C7-adaptive-coach.md](../plans/C7-adaptive-coach.md)
8. **C8 — Rank progression.** Streaks, orbit ranks, planet/ring unlocks.
   → [plans/C8-rank-progression.md](../plans/C8-rank-progression.md)

**Phase D — Pre-live hardening** (local)

- **D1 — Export-my-data + retention automation.** GDPR/CCPA portability via S3 on
  LocalStack, built on the registry; live-only retention checks are owed to Phase E.
  → [plans/D1-export-retention.md](../plans/D1-export-retention.md)

**— GO-LIVE DECISION (owner) —** Phase E starts only on an explicit owner decision,
after every Phase A–D feature works locally in the Simulator. Decide **monetization**
(free vs freemium) here, before E3. If freemium: a StoreKit 2 + entitlement + webhook run
gets planned, and the coach is gated via C7's entitlement shape.

**Phase E — Going live** (parked; briefs keep full go-live detail)

1. **E1 — Production deploy path.** Account + budget alert + manual bootstrap, apply A2's
   Terraform, CI deploy, canary + auto-rollback proven by fault injection, synthetics,
   Sentry/dSYMs, Firebase password policy (discharges the ASVS 6.2.x waiver). Holds the
   cost model. → [plans/E1-production-deploy-path.md](../plans/E1-production-deploy-path.md)
2. **E2 — SOC visibility & security monitoring.** Detection, paging, GuardDuty,
   CloudTrail, auditor/responder IAM with negative tests, runbooks; ships B1's events to
   the CloudWatch audit group. → [plans/E2-soc-visibility.md](../plans/E2-soc-visibility.md)
3. **E3 — App Store submission.** Apple Developer Program ($99/yr), privacy labels,
   privacy-policy legal review, TestFlight, including the real-device checks (camera
   barcode, real HealthKit data). → [plans/E3-app-store-submission.md](../plans/E3-app-store-submission.md)

**— LAUNCH —**

## Old → new mapping (2026-09-18 reorder)

| Old | Old path | New |
|---|---|---|
| run 1 | `plans/01-production-deploy-path.md` | Authoring → **A1** (local) + **A2** (prod Terraform); applying/operating → **E1** |
| run 2 | `plans/02-soc-visibility.md` | Part C → **B1** (audit trail) + **B2** (encryption, consent); Parts A–B → **E2** |
| run 3 | `plans/03-entry-management.md` | **C1** |
| run 4 | `plans/04-app-store-submission.md` | **E3** |
| run 5 | `plans/05-food-logging-integrations.md` | **C2** |
| run 6 | `plans/06-healthkit-activity.md` | **C6** |
| run 7 | `plans/07-adaptive-coach.md` | **C7** |
| run 8 | `plans/08-program-builder.md` | **C3** |
| run 9 | `plans/09-muscle-derivation.md` | **C4** |
| run 10 | `plans/10-tier-percentile.md` | **C5** |
| run 11 | `plans/11-rank-progression.md` | **C8** |
| run 12 | `plans/12-export-retention.md` | **D1** |

## Unscheduled small items (fold into the named run)
- **Internal token exchange (auth hardening).** `POST /auth/token` swaps the verified
  Firebase ID token for a short-lived, PII-free backend-minted token; Firebase becomes
  login-only.
  - Gains: drops the per-request `check_revoked` lookup; enables custom entitlement/MFA
    claims.
  - Costs: owning the session lifecycle — signing keys via KMS, TTL + Redis-denylist
    revocation replacing AC34's mechanism, and full ASVS V7 back in scope.
  - Contained entirely in the `require_auth`/`AuthService` facades; no route, schema or
    DB change.
  - **Pair with the MFA decision** (currently on the excluded list). Not launch-required:
    greenfield already stores zero PII (tokens are verified per request, never
    persisted).
- **Pagination** — when history views or scale demand it (likely with C3's program lists
  or a history screen; bounded windows suffice until then).
- **Macro-split % editor UX** (reconciling the design's "40P·35C·25F" copy) — with C7.

## Deferred beyond go-live (decided 2026-09-18; revisit deliberately)
- **Meal-photo recognition** (server-side ML: per-call cost; images leave the device, a
  major privacy-label/consent change). C2 builds on-device label OCR only; the Photo
  button stays stubbed.
- **Open Food Facts** as a second food source (international barcode coverage; ODbL
  obligations). C2 is USDA-only.
- **EventBridge-scheduled coach job.** C7 uses lazy compute; revisit once E1's compute
  exists and scale warrants.

## Excluded — no run planned (revisit deliberately, not by drift)
- Social/feed
- Reminders/scheduling
- MFA + social login. Adding social login triggers Apple's guideline-4.8
  equivalent-privacy-login requirement; Sign in with Apple is the easy compliance path.
- Offline queue/local sync — the one consciously closed architectural door; it would be
  a client rearchitecture
- Analytics dashboards beyond the depicted cards
- Android/web frontends

_(Payments/subscriptions are not excluded: the monetization decision sits at the go-live
gate above.)_
