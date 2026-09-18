---
feature: greenfield
task_count: 18
covers_all_acs: true
acs_covered: AC1–AC34
staging_note: >
  Visual-fidelity tasks (starfield + SceneKit 3D heroes) are T17–T18, the LAST tasks, so an
  implementation cap lands after the app is functional end-to-end (design-audit §5). Backend
  (T1–T10) carries full deterministic gate coverage; iOS (T11–T18) is reduced-assurance
  (XCTest/XCUITest/snapshot + human review), never claimed "gate-verified".
parallelism: >
  T11 (Theme) is independent and can start immediately. T10 (infra) is parallel-safe after T1.
  iOS Core (T12) needs the API contracts from T4–T7. Otherwise follow depends_on.
---

# Tasks — Orbit greenfield

Each task is sized so one implementation segment can finish with the suite green and the app
(backend and/or iOS) bootable. `ACs advanced` cite `acceptance.md` ids; the union covers AC1–AC34.

## Backend + infra (full gate coverage)

| ID | depends_on | ACs advanced | test_strategy slice | expected files |
|----|-----------|--------------|---------------------|----------------|
| **T1** | — | AC1, AC19, AC22 | unit: structlog facade fields + redaction; secrets facade raises-on-missing + facade-is-only-caller; integration: `/health` 200 with DB/Firebase absent | `pyproject.toml`+lockfile, `src/orbit/main.py`, `config/{settings,secrets}.py`, `logging/__init__.py`, `crypto/__init__.py`, `observability/sentry.py`, `routes/health.py`, `tests/conftest.py`, fill `pipeline-ci.yml` INSTALL/BUILD/TEST/COVERAGE_FLOOR |
| **T2** | T1 | AC6, AC9, AC24 | migration round-trip (create-migration kind — schema+constraints, seeded prod-shaped data, no row-survival); seed-content tests (catalog macros, Push Day 5 exercises, 13 template levels) | `migrations/env.py`, `versions/0001_initial_schema.py`, `versions/0002_seed_catalog_program_levels.py`, `src/orbit/models.py`, `repositories/base.py`, `tests/integration/test_migrations.py` |
| **T3** | T1, T2 | AC2, AC3, AC16, AC17, AC18, AC33, AC34 | unauth-denied (no/expired token→401); token validation (expired + wrong-aud→401); **session-lifecycle (T2-4: after `POST /me/signout` old token→401 via `check_revoked`; sign-in mints new token)**; constraint→4xx; safe-error; two-principals-one-IP throttle; header presence; `/health` throttle-exempt | `auth/{__init__,firebase}.py` (require_auth + `revoke_refresh_tokens` sign-out), `edge/{headers,cors,ratelimit,errors}.py`, `schemas/common.py`, `routes/me.py` (bootstrap + signout shells) |
| **T4** | T3 | AC4, AC8, AC13, AC15 | bootstrap idempotency + empty-start; **bootstrap multi-insert atomicity (T2-5 / ASVS 2.3.3): fault-injected failure mid-insert → whole transaction rolls back, no partial profile/levels persist**; profile round-trip per field; mass-assignment ignored; backdate-ok/future-422; canonical grams + derived-% unit | `routes/{me,profile}.py`, `schemas/profile.py`, `repositories/profile.py`, `tests/integration/test_profile.py` |
| **T5** | T3, T4 | AC7, AC14 | create entry (quick-food + explicit macro paths); grouped/day read + totals; ≤200/day bound; cross-owner IDOR; day-scoped LIMIT | `routes/fuel.py`, `schemas/fuel.py`, `repositories/fuel.py`, `tests/integration/test_fuel.py` |
| **T6** | T3, T4 | AC10, AC11, AC14 | set toggle idempotency (replay→200) + score math + week strip; concurrency replay (loser outcome); body levels + trained-today derivation; cross-owner IDOR; day-scoped LIMIT | `routes/{train,body}.py`, `schemas/{train,body}.py`, `repositories/{train,body}.py`, `tests/integration/test_train.py`, `test_body.py` |
| **T7** | T3, T4 | AC12, AC14 | kg canonical storage; 30-day window bound; future-ts 422; **`GET /weight?day_key=` undeclared-param→422**; cross-owner IDOR; weekly-delta math | `routes/weight.py`, `schemas/weight.py`, `repositories/weight.py`, `tests/integration/test_weight.py` |
| **T8** | T4, T5, T6, T7 | AC5, AC21 | erasure-cascade (seed every declared copy → `DELETE /me` → each raw store empty, Firebase `delete_user` called, audit event survives); **atomic-rollback (T2-5 / ASVS 2.3.3): a fault-injected session — a SQLAlchemy event hook or monkeypatched delete that raises after the N-th table delete — forces the whole cascade transaction to roll back; assert no table shows a partial delete**; fresh-reauth required (stale `auth_time`→401) | `lifecycle/erase.py`, `routes/me.py` (delete), `tests/integration/test_account_deletion.py` |
| **T9** | T4–T8 | AC23, AC25, AC26 | k6 perf (p95<300ms @ ~10 conc on GET /fuel, GET /train, POST /fuel/entries; out-of-process, nearest-rank, scenario disclosed); coverage ≥80%; OpenAPI-matches-routes; DAST seed script | `tests/perf/k6_orbit.js`, `scripts/seed_dast_user.py`, adversarial-gap tests, coverage wiring |
| **T10** | T1 | AC20, AC22, AC33 | `infra-validate.sh` (fmt/validate/plan → `.pipeline/infra-plan.txt`); Checkov clean (RDS SSE+TLS+not-public+deletion-protection+multi-AZ; Redis encrypted; secrets not in state; log delete-deny; sg no 0.0.0.0/0) | `infra/{backend,main,variables,outputs}.tf`, `infra/modules/{network,data,secrets,observability}/*` |

## iOS (reduced-assurance — XCTest/XCUITest/snapshot + human review)

| ID | depends_on | ACs advanced | test_strategy slice | expected files |
|----|-----------|--------------|---------------------|----------------|
| **T11** | — (parallel) | AC28, AC8 | Swift Testing: palette blend/tint math, 6-stop level scale, derived macro-% ; snapshot per preset (advisory); no-inline-hex check | `ios/Orbit/DesignSystem/{Theme,Color+Hex,Font+Theme,Metrics}.swift`, `Resources/{Assets.xcassets,fonts}`, `Tests/ThemeTests.swift`, `Orbit.xcodeproj` |
| **T12** | T11, T4–T7 | AC27 | Swift Testing: `Codable` decode of each API model; `AppStore` derived values + cross-screen reactions; error-envelope→`AppError` mapping; Keychain token store | `Core/{APIClient,AuthService,KeychainStore,Models,AppStore,AppError}.swift`, `Tests/CoreTests.swift` |
| **T13** | T12 | AC5, AC32, AC34, AC27 | XCUITest: sign-in/register; **Sign out → `POST /me/signout` then Keychain clear (old token unusable)**; delete-account action calls `DELETE /me`; PrivacyInfo required-reason present; store-compliance critical=0 | `App/{OrbitApp,RootView,RootTabView,AppRouter}.swift`, `Screens/{SignInView,RegisterView,SettingsSheet}.swift`, `Resources/{PrivacyInfo.xcprivacy,Info.plist}` |
| **T14** | T11, T12 | AC29 | snapshot per component (advisory) on flat backgrounds; ≥44pt hit-target audit | `Components/*.swift` (GlassCard, SectionLabel, ProgressRing, MacroBar, GradientPillButton, StatChip, SegmentedToggle, QuickAddChip, MealCard, HourTimeline, SetCircle, RestChip, WeekStrip, LevelSegments, MuscleRow, Sparkline, GlassTabBar, CoachBanner, TipBanner, LogMethodButton(stub), PlanetPickerChip, Avatar, HeaderWordmark) |
| **T15** | T13, T14 | AC7, AC9, AC11, AC13, AC29, AC27 | snapshot per screen vs reference (advisory) + human diff-review; figure geometry verbatim from `figure-paths.md`; Meals⇄By-hour paging; rest timer; Settings persistence | `Screens/{HomeView,FuelView,TrainView,BodyView,WeightEntrySheet,BudgetEditorSheet,MacroEditorSheet}.swift`, `Figures/{MuscleFigure,FigurePaths}.swift` |
| **T16** | T15 | AC27, AC30 | XCUITest smoke (register→log food→toggle sets→weight→theme-switch→delete against real API); Reduce Motion + VoiceOver traits; hit-target audit | `Screens/*` a11y modifiers, `Tests/SmokeUITests.swift`, `Tests/AccessibilityTests.swift` |

## Visual fidelity (LAST — cap lands after function exists)

| ID | depends_on | ACs advanced | test_strategy slice | expected files |
|----|-----------|--------------|---------------------|----------------|
| **T17** | T15, T16 | AC31 | manual/snapshot review (advisory); Reduce-Motion freeze verified (drift/ships/float stop) | `Space/StarfieldView.swift` (TimelineView+Canvas, deterministic per-screen seeds, shooting stars, toggleable ships) |
| **T18** | T17 | AC31 | manual/snapshot review (advisory); Reduce-Motion freeze (scroll-driven cameras stop, idle spin may remain) | `Space/{HeroSceneView,Textures}.swift` (SceneKit: Home planet+rings, Fuel macro moons, Train asteroid; procedural textures; scroll-driven cameras) |
