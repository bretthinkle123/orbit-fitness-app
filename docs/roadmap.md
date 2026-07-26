# Roadmap — ordered feature runs after greenfield

_Last updated 2026-07-18. The single source of truth for what runs after the greenfield
run, **in execution order**. One pipeline run per entry; each starts with
`requirements-elicitation` reading its brief in [`plans/`](../plans/) — the entries here
are one-line summaries, the briefs are the planning-stage context. (History: renamed from
`docs/deferred.md`; run numbers below are the NEW order — frozen greenfield artifacts
reference runs by name, not number.)_

_Deferral rule used for the greenfield scope: a feature whose **flow the design depicts**
was built; a feature that existed in the design only as a button/label/number with no
flow behind it shipped as a stub/default and lives here._

_Not a run: [plans/00-mac-pipeline-readiness.md](../plans/00-mac-pipeline-readiness.md)
is a self-contained runbook a fresh Claude session on the operator's Mac executes to
verify (and fix) that machine's readiness to run this pipeline and build/test the iOS app._

## Standing rules — every future run, non-negotiable (planning must honor these)

1. **Erasure/export parity:** any run that adds an `owner_uid` table extends the
   `DELETE /me` cascade (`src/orbit/lifecycle/erase.py`) **and** the AC5 erasure test **in
   the same run**, and registers the table in the shared owner_uid-table registry (the
   registry + its export∪erase parity test are introduced by the first run to add a table
   — run 6; run 12's export reuses it). Account deletion must never under-erase, even for
   one run — AC5's "every domain table" and App Store 5.1.1(v) depend on it.
2. **Classification pass:** any new stored personal field gets a data-protection
   classification row and the run-2 controls (field encryption, read-access audit) in the
   same run.
3. **Standard shapes:** every new endpoint inherits the greenfield adversarial set —
   unauth→401, cross-owner→404 (IDOR), bounded reads (scope + hard LIMIT), `extra="forbid"`
   validation, a rate-limit tier, audit events.

## Run order

**Pre-launch gates — required before the App Store, in this order:**

1. **Production deploy path** — compute topology (App Runner/ECS + ALB + autoscaling),
   staging/prod split, WAF, deploy alarms + canary, full observability wiring. No launch
   without prod. → [plans/01-production-deploy-path.md](../plans/01-production-deploy-path.md)
2. **SOC visibility & data hardening** — detection/paging/dashboard/runbooks (AWS-native)
   **plus** the health-data escalation: field-level encryption, read-access audit, consent
   UX. Encryption must land pre-users (post-users it's a live dual-write migration).
   → [plans/02-soc-visibility.md](../plans/02-soc-visibility.md)
3. **Entry management** — per-entry edit/delete + idempotency keys (GDPR rectification +
   duplicate-recovery; a timeout+retry can double-log a meal today).
   → [plans/03-entry-management.md](../plans/03-entry-management.md)
4. **App Store submission pass** — nutrition labels vs real data map, signing,
   screenshots, privacy-policy/support URLs, age rating, TestFlight round.
   → [plans/04-app-store-submission.md](../plans/04-app-store-submission.md)

**— LAUNCH —**

**Post-launch feature runs, in recommended order:**

5. **Food-logging integrations** — text search + food DB first, then barcode scan, then
   photo/label OCR (multiple sub-runs; un-stubs the four log-method buttons).
   → [plans/05-food-logging-integrations.md](../plans/05-food-logging-integrations.md)
6. **HealthKit activity (burned kcal)** — real "Burned +N" input; consent + privacy-label
   updates ride the next submission.
   → [plans/06-healthkit-activity.md](../plans/06-healthkit-activity.md)

**— DECISION GATE: monetization** — choose free vs freemium **before run 7**, so premium
features (coach, derivation engines) launch premium instead of being taken away later.
Moving payments off the excluded list is a deliberate operator decision; StoreKit 2 +
entitlement + webhook run gets planned when taken. —

7. **Adaptive diet coach (TDEE engine)** — the flagship premium candidate; needs weeks of
   post-launch intake+weight data, which will exist by now.
   → [plans/07-adaptive-coach.md](../plans/07-adaptive-coach.md)
8. **Program builder / periodization** — user-owned programs; biggest post-launch run;
   includes performed-set logging (weight×reps), which run 10 needs.
   → [plans/08-program-builder.md](../plans/08-program-builder.md)
9. **Muscle-level derivation from lift history** — makes Body levels real; benefits from
   run 8's exercise variety. → [plans/09-muscle-derivation.md](../plans/09-muscle-derivation.md)
10. **Strength tier & percentile engine** — makes "Intermediate II / Top 22%" real; needs
    run 8's performed-set data. → [plans/10-tier-percentile.md](../plans/10-tier-percentile.md)
11. **Rank progression / gamification** — streaks, orbit ranks, planet/ring unlocks;
    order-flexible retention work. → [plans/11-rank-progression.md](../plans/11-rank-progression.md)
12. **export-my-data + retention automation** — GDPR/CCPA portability; **trigger: before
    EU marketing** (pull earlier if that comes sooner).
    → [plans/12-export-retention.md](../plans/12-export-retention.md)

## Unscheduled small items (fold into the named run)
- **Internal token exchange (auth hardening)** — `POST /auth/token`: swap the verified
  Firebase ID token for a short-lived, PII-free backend-minted token; Firebase becomes
  login-only (drops the per-request `check_revoked` lookup; enables custom
  entitlement/mfa claims). Costs owning session lifecycle (signing keys via KMS, TTL +
  Redis denylist revocation replacing AC34's mechanism — full ASVS V7 back in scope).
  Contained entirely in the `require_auth`/`AuthService` facades — no route/schema/DB
  change. **Pair with the MFA decision** (currently excluded-list); not launch-required:
  greenfield already stores zero PII (tokens are verified per-request, never persisted).
- **Pagination** — when history views or scale demand it (likely with run 8's program
  lists or a history screen; bounded windows suffice until then).
- **Macro-split % editor UX** (reconciling the design's "40P·35C·25F" copy) — with run 7.

## Excluded — no run planned (revisit deliberately, not by drift)
Social/feed · reminders/scheduling · MFA + social login (adding social login triggers
Apple's guideline-4.8 equivalent-privacy-login requirement — Sign in with Apple is the
easy compliance path) · offline queue/local sync (the one consciously
closed architectural door — would be a client rearchitecture) · analytics dashboards
beyond the depicted cards · Android/web frontends.
_(Payments/subscriptions moved from this list to the decision gate above.)_
