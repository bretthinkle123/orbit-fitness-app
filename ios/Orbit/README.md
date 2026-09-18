# Orbit — iOS app (SwiftUI)

Native iOS client for Orbit Fitness & Diet Tracking, replicating
`design/design_handoff_orbit_swiftui/` (Claude Design export) against the FastAPI backend
in `src/orbit/`. See root `CLAUDE.md` / `docs/decisions/feature/greenfield/plan.md`
§Frontend for the full brief; this file covers iOS-specific build/generation mechanics
only.

## Reduced assurance (read this first)

The pipeline authors this code on a **Linux host with no Swift toolchain and no Xcode**,
to the conventions in `swift-conventions`/`claude-design-to-swiftui`. Compilation, test
execution and snapshot review happen on the operator's Mac
(`plans/00-mac-pipeline-readiness.md` Phase 5).

The greenfield Swift was first compiled and run there after the merge. Fourteen defects
surfaced and were fixed in PR #3; since then every suite passes on the Mac — 157/157
Swift Testing units, 50/50 snapshots, 12 XCUITests with 0 failures — as recorded in
`docs/mac-session-handoff.md`. That is verification by tests and human review; the
pipeline's deterministic gates still analyze almost no Swift. Never read a passing iOS
task as "gate-verified" the way a backend task is.

## Module layout (CLAUDE.md's suggested decomposition, adopted per plan.md §Frontend)

```
App/            OrbitApp (@main), RootView, RootTabView, AppRouter        — T13 (done)
DesignSystem/   Theme, Color+Hex, Font+Theme, Metrics, MotionPreference,
                AccessibilityIdentifierSlug                                — T11 (done)
Core/           APIClient, AuthService, KeychainStore, Models, AppStore, AppError — T12 (done)
Screens/        SignInView, RegisterView, SettingsSheet (T13); HomeView, FuelView,
                TrainView, BodyView, WeightEntrySheet, BudgetEditorSheet,
                MacroEditorSheet, DisplayFormatting, ScreenStateViews          — T15 (done)
Components/     GlassCard through HeaderWordmark (25 CMP-n components)        — T14 (done)
Space/          StarfieldView (T17), HeroSceneView + Textures.swift (SceneKit
                gas-giant/asteroid/ring heroes, T18) — visual fidelity, staged LAST — done
Figures/        MuscleFigure + FigurePaths, verbatim from figure-paths.md      — T15 (done)
Resources/      Assets.xcassets, Fonts/ (FONTS-TODO.md only — no .ttf bundled yet),
                Info.plist, PrivacyInfo.xcprivacy, GoogleService-Info.plist
                (emulator-only placeholders; replace before shipping — E1) — T13 (done)
Tests/          Swift Testing unit suites (ThemeTests, CoreTests, AppTests,
                ComponentMathTests, ScreensTests, SpaceTests, HeroSceneTests, …),
                advisory snapshot suites, Tests/UITests/ — run on the Mac only
```

**T1–T18 (the full greenfield task list) are all COMPLETE.** "(done)" means authored on
the Linux host, then compiled, fixed and test-verified on the Mac (PR #3). Per the
Reduced assurance note above, none of it is gate-verified.

Undepicted screens (sign-in/register — T13; weight-entry sheet, budget/macro-editor
sheets — T15) follow the design README's own "Extending the UI" conventions — same shared
ZStack recipe (`Screens/SignInView.swift`'s `AuthScreenBackdrop`), new starfield seed per
screen, no new visual language invented. `RootTabView`'s 4 tabs are now the real
`HomeView`/`FuelView`/`TrainView`/`BodyView` (T15), each wired to `AppStore` and, since
T17/T18, layered over `StarfieldView` with a `HeroSceneView` (Home/Fuel/Train only —
`BodyView` has none) between the starfield and the scrollable content.

## Project file: XcodeGen, not a hand-authored `.xcodeproj` (flagged deviation)

`docs/decisions/feature/greenfield/tasks.md`'s T11 row names `Orbit.xcodeproj` as the
expected project file. This build uses a checked-in **`project.yml`** (XcodeGen spec)
instead, generated into `Orbit.xcodeproj` on the Mac. Rationale (recorded per the plan's
judgment-call precedent — see T2's `muscle_level_templates` design-note in
`docs/decisions/feature/greenfield/implementation-progress.md`):

- A hand-authored `project.pbxproj` is a binary-adjacent, deeply order-and-UUID-sensitive
  format `xcodebuild`/Xcode itself normally writes — hand-editing it on a host with no
  Xcode to validate the result risks producing a file that silently fails to open, with
  no way to catch that here.
- `project.yml` is plain, readable YAML: reviewable in a normal diff, and exactly the kind
  of artifact each subsequent iOS task (T12–T18) can extend by adding one more `sources:`
  entry as its directory lands, without touching a generated file.
- Generation is one command, run once on the Mac before opening the project:

  ```sh
  brew install xcodegen   # if not already installed
  cd ios/Orbit
  xcodegen generate       # writes Orbit.xcodeproj from project.yml
  open Orbit.xcodeproj
  ```

- `Orbit.xcodeproj` itself is gitignored (generated artifact); `project.yml` is the
  source of truth and the file every task's diff actually touches.

## Fonts

Space Grotesk (display/numbers) + DM Sans (body/UI), OFL-licensed Google Fonts, are not
yet bundled — see `Resources/Fonts/FONTS-TODO.md` for the exact files/URLs and the
`UIAppFonts` wiring step. Until they land, `DesignSystem/Font+Theme.swift` detects their
absence at runtime and transparently falls back to the recorded SF Pro Rounded / SF Pro
substitute (plan.md Open Question 6 default) — no other code changes when the fonts are
added later.

## Theme / no-hardcoded-hues

Every color in the app is derived from the active `PalettePreset` via `Theme`
(`DesignSystem/Theme.swift`) — never a second hex literal outside `DesignSystem/`.
`scripts/check_no_inline_hex.sh` enforces this structurally. From the repo root:

```sh
bash scripts/check_no_inline_hex.sh
```
