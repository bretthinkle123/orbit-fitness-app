# Orbit — iOS app (SwiftUI)

Native iOS client for Orbit Fitness & Diet Tracking, replicating
`design/design_handoff_orbit_swiftui/` (Claude Design export) against the FastAPI backend
in `src/orbit/`. See root `CLAUDE.md` / `.pipeline/plan.md` §Frontend for the full brief;
this file covers iOS-specific build/generation mechanics only.

## Reduced assurance (read this first)

This project is built and reviewed on a **Linux host with no Swift toolchain and no
Xcode** — nothing here has been compiled or run yet. Every file is authored to the exact
conventions in `swift-conventions`/`claude-design-to-swiftui`, but genuine compilation,
test execution, and snapshot review happen on the operator's Mac
(`plans/00-mac-pipeline-readiness.md` Phase 5). `.pipeline/implementation-progress.md`
records this for each iOS task as it lands; never read a passing iOS task here as
"gate-verified" the way a backend task is.

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
Resources/      Assets.xcassets, Fonts/*.ttf (+ FONTS-TODO.md); Info.plist,
                PrivacyInfo.xcprivacy — T13 (done)
Tests/          Swift Testing unit suites (ThemeTests, CoreTests, AppTests,
                ComponentMathTests, ScreensTests, SpaceTests, HeroSceneTests, …),
                advisory snapshot suites, Tests/UITests/ — all authored, Mac-only
```

**T1–T18 (the full task list) are all COMPLETE** — every module above is authored.
"(done)" here means authored-to-shape on this Linux host, per the Reduced assurance
note above; none of it is compiled/run/gate-verified until the Mac-phase.

Undepicted screens (sign-in/register — T13; weight-entry sheet, budget/macro-editor
sheets — T15) follow the design README's own "Extending the UI" conventions — same shared
ZStack recipe (`Screens/SignInView.swift`'s `AuthScreenBackdrop`), new starfield seed per
screen, no new visual language invented. `RootTabView`'s 4 tabs are now the real
`HomeView`/`FuelView`/`TrainView`/`BodyView` (T15), each wired to `AppStore` and, since
T17/T18, layered over `StarfieldView` with a `HeroSceneView` (Home/Fuel/Train only —
`BodyView` has none) between the starfield and the scrollable content.

## Project file: XcodeGen, not a hand-authored `.xcodeproj` (flagged deviation)

`.pipeline/tasks.md`'s T11 row names `Orbit.xcodeproj` as the expected project file. This
build uses a checked-in **`project.yml`** (XcodeGen spec) instead, generated into
`Orbit.xcodeproj` on the Mac. Rationale (recorded per the plan's judgment-call
precedent — see T2's `muscle_level_templates` design-note in
`.pipeline/implementation-progress.md`):

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
`scripts/check_no_inline_hex.sh` (run from the repo root) enforces this structurally:

```sh
bash ../../scripts/check_no_inline_hex.sh
```
