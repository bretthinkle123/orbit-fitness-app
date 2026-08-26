import SceneKit
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Orbit

/// **Authored, not compiled or run, on this host** (no Swift toolchain —
/// `.pipeline/implementation-progress.md`'s T11-T17 entries carry the same
/// caveat). Genuine snapshot recording/comparison happens on the operator's
/// Mac (`plans/00-mac-pipeline-readiness.md` Phase 5) — the first run there
/// must record reference images, since none exist yet.
///
/// **Advisory only, never a gate** (plan.md's test-strategy; `swift-
/// conventions`) — `.pipeline/tasks.md` T18's own row: "advisory Mac-only
/// snapshot scaffolds" for `Space/HeroSceneView.swift`. SceneKit rendering
/// ALSO needs a real Metal-capable device/simulator — more genuinely
/// "Mac/device-only" than `StarfieldSnapshotTests`' pure-`Canvas` snapshots,
/// which at least run in any host process.
///
/// **Why this file snapshots `HeroSceneState` DIRECTLY, never the live
/// `HeroSceneView`**: `Space/StarfieldView.swift`'s Reduce-Motion contract
/// (T17) freezes `elapsedTime` ENTIRELY, so `StarfieldSnapshotTests` could get
/// a byte-stable frame just by forcing Reduce Motion on the live view. The
/// hero's OWN accessibility contract is deliberately different (README:
/// "scroll-driven camera motion STOPS, idle spin may remain" —
/// `HeroSceneState`'s own doc comment) — `elapsedTime` NEVER freezes here,
/// so the live, `TimelineView`-driven `HeroSceneView` can never be snapshotted
/// byte-stably at all, Reduce Motion or not. These tests instead construct a
/// `HeroSceneState` directly, call `tick(to:scrollTarget:motionAllowed:
/// liveInputs:)` exactly ONCE with a FIXED `Date`, and snapshot the resulting
/// scene via a plain (non-ticking) `SceneView` — the same "bypass the
/// real-time clock, snapshot the state/scene construction instead"
/// discipline `StarfieldSnapshotTests`' own renderer-path fixtures already
/// established for shooting-star/ship frames.
final class HeroSceneSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 402, height: Metrics.Hero.sceneHeight)
    /// An arbitrary FIXED instant — `HeroSceneState.tick` only cares about
    /// the DELTA since its last tick (`nil` on the first call, so the very
    /// first tick always advances `elapsedTime` by exactly `0`), so which
    /// real calendar date this is doesn't matter, only that every test in
    /// this file uses the SAME one.
    private static let fixedDate = Date(timeIntervalSince1970: 0)

    /// `@MainActor` because `HeroSceneState` is — reading its `scene`/
    /// `cameraNode` from a nonisolated helper is a Swift 6 error. Every caller
    /// in this file is already `@MainActor`, so this only makes the helper
    /// match them.
    @MainActor
    private func assertHeroSnapshot(
        _ state: HeroSceneState, named name: String,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let view = SceneView(scene: state.scene, pointOfView: state.cameraNode, options: [])
            .frame(width: Self.size.width, height: Self.size.height)
        assertSnapshot(
            // Tolerance, not exact equality. GPU anti-aliasing and gradient
            // dithering differ by a hair between runs: re-recording these
            // baselines and immediately re-comparing produced images 186 bytes
            // apart on 3.7 MB (0.005%) — visually identical, byte-unequal.
            // The difference is sub-perceptual but spread over MANY pixels
            // (gradient dithering across large fills), so the pixel-COUNT
            // budget has to be the loose one: `precision: 0.999` still tipped
            // over on one screen in one run of three. `perceptualPrecision`
            // stays strict — every differing pixel must be perceptually
            // indistinguishable — so a real visual regression still fails.
            of: view, as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: Self.size.width, height: Self.size.height)),
            named: name, file: file, testName: testName, line: line
        )
    }

    @MainActor
    func testHomeSceneAtRest() {
        let state = HeroSceneState(kind: .home(planetIndex: 2), theme: Theme())
        state.tick(to: Self.fixedDate, scrollTarget: 0, motionAllowed: true, liveInputs: HeroSceneLiveInputs())
        assertHeroSnapshot(state, named: "home_planet_index_2_scroll_0")
    }

    @MainActor
    func testHomeSceneFullyScrolledShowsTiltedRingsAndPulledInCamera() {
        // `HeroSceneState.tick`'s own 8%/frame ease means a SINGLE tick from
        // 0 never reaches scroll=1 exactly — ticking many times with the
        // SAME fixed date (zero elapsed delta between ticks) settles the
        // eased value arbitrarily close to the target without depending on
        // real wall-clock time at all, keeping this deterministic.
        let state = HeroSceneState(kind: .home(planetIndex: 5), theme: Theme())
        for _ in 0..<200 {
            state.tick(to: Self.fixedDate, scrollTarget: 1, motionAllowed: true, liveInputs: HeroSceneLiveInputs())
        }
        assertHeroSnapshot(state, named: "home_planet_index_5_scroll_1")
    }

    @MainActor
    func testFuelSceneWithMacroMoonsAtVaryingFractions() {
        let state = HeroSceneState(kind: .fuel, theme: Theme(preset: .blue))
        state.tick(
            to: Self.fixedDate, scrollTarget: 0, motionAllowed: true,
            liveInputs: HeroSceneLiveInputs(proteinFraction: 0.4, carbFraction: 0.9, fatFraction: 0.1)
        )
        assertHeroSnapshot(state, named: "fuel_blue_palette_mixed_macros")
    }

    @MainActor
    func testTrainSceneAsteroidFullyHeated() {
        let state = HeroSceneState(kind: .train, theme: Theme())
        // Same "many fixed-date ticks" technique as the Home full-scroll
        // case, needed here because the emissive-intensity ease ALSO settles
        // at .06/frame rather than snapping instantly.
        for _ in 0..<200 {
            state.tick(to: Self.fixedDate, scrollTarget: 0, motionAllowed: true, liveInputs: HeroSceneLiveInputs(doneSetFraction: 1))
        }
        assertHeroSnapshot(state, named: "train_asteroid_fully_heated")
    }
}
