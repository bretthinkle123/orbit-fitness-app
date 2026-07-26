import SnapshotTesting
import SwiftUI
import XCTest
@testable import Orbit

/// **Authored, not compiled or run, on this host** (no Swift toolchain —
/// `.pipeline/implementation-progress.md`'s T11-T16 entries carry the same
/// caveat). Genuine snapshot recording/comparison happens on the operator's
/// Mac (`plans/00-mac-pipeline-readiness.md` Phase 5) — the first run there
/// must record reference images, since none exist yet.
///
/// **Advisory only, never a gate** (plan.md's test-strategy; `swift-
/// conventions`: "Snapshot diffs are advisory — never a deploy gate")
/// — `.pipeline/tasks.md` T17's own row: "advisory Mac-only snapshot
/// scaffolds" for `Space/StarfieldView.swift`.
///
/// **Why these snapshots need a different determinism strategy than
/// `ComponentSnapshotTests`/`ScreenSnapshotTests`**: `StarfieldView`'s body
/// is a `TimelineView(.animation)`, which schedules its content closure off
/// the REAL wall clock — there is no way to make a snapshot of the LIVE view
/// byte-stable across two different test runs (or two different machines)
/// without controlling for that. Two independent strategies, covering two
/// different things:
/// 1. **The seed-deterministic field itself** (star/nebula positions) —
///    forcing Reduce Motion through the SAME `MotionPreference` facade every
///    real device uses freezes `elapsedTime` at 0 and hides any transient
///    decoration (`StarfieldSimulation.tick`/`currentFrame`, see that type's
///    own doc comments), so the rendered frame becomes a pure function of
///    the seed alone — real production code path, not a stub.
/// 2. **The shooting-star/ship renderer paths** — impossible to reach
///    deterministically via the real clock even under Reduce Motion (Reduce
///    Motion's whole point is to suppress them). These bypass
///    `StarfieldView`'s `TimelineView`/`StarfieldSimulation` machinery
///    entirely and instead hand-build a `StarfieldFrame` fixture, rendered
///    through the EXACT SAME `StarfieldRenderer.draw` pure function every
///    real frame uses (never a re-implementation) inside a plain,
///    non-ticking `Canvas` — the same "test the pure function directly"
///    discipline `SpaceTests.swift`'s own unit suite already established for
///    the non-rendering half of this file.
final class StarfieldSnapshotTests: XCTestCase {
    private static let size = StarfieldView.referenceSize

    private func assertStarfieldSnapshot(
        _ view: some View, named name: String,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        assertSnapshot(
            of: view.frame(width: Self.size.width, height: Self.size.height),
            as: .image(layout: .fixed(width: Self.size.width, height: Self.size.height)),
            named: name, file: file, testName: testName, line: line
        )
    }

    // MARK: - 1. Seed-deterministic field (Reduce Motion forced)

    func testHomeSeedStaticFieldUnderReduceMotion() {
        assertStarfieldSnapshot(
            StarfieldView(seed: StarfieldSeed.home, theme: Theme())
                .environment(\.accessibilityReduceMotion, true),
            named: "home_reduce_motion_static"
        )
    }

    func testSignInSeedStaticFieldUnderReduceMotion() {
        // A distinct seed (per-screen determinism, `.pipeline/tasks.md` T17's
        // own "deterministic per-screen seeds (same seed → same field)"
        // requirement) — proves two different seeds genuinely render two
        // different reference images, not one shared/cached background.
        assertStarfieldSnapshot(
            StarfieldView(seed: StarfieldSeed.signIn, theme: Theme())
                .environment(\.accessibilityReduceMotion, true),
            named: "signin_reduce_motion_static"
        )
    }

    func testAccentPaletteTintsTheSameSeedDifferently() {
        // The design's `pink`-flagged stars/nebula cores render with the
        // ACTIVE palette's accent/secondary color (`StarfieldRenderer`'s own
        // doc comments) — a non-default `Theme` proves the tint is genuinely
        // wired, not hardcoded to the default palette.
        assertStarfieldSnapshot(
            StarfieldView(seed: StarfieldSeed.home, theme: Theme(preset: .green))
                .environment(\.accessibilityReduceMotion, true),
            named: "home_green_palette_reduce_motion_static"
        )
    }

    // MARK: - 2. Renderer-path fixtures (bypass the real-time clock entirely)

    func testShootingStarRendererFixture() {
        var rng = StarfieldRNG(seed: StarfieldSeed.train)
        let field = StarfieldFieldGenerator.generate(using: &rng, size: Self.size)
        let shootingStar = StarfieldShootingStar.spawn(using: &rng, size: Self.size)
        let frame = StarfieldFrame(
            stars: field.stars, clusters: field.clusters, elapsedTime: 0,
            scrollProgress: 0, shootingStar: shootingStar, ship: nil
        )
        assertStarfieldSnapshot(
            Canvas { context, size in StarfieldRenderer.draw(frame, into: &context, size: size, theme: Theme()) },
            named: "shooting_star_fixture"
        )
    }

    func testShipRendererFixture() {
        var rng = StarfieldRNG(seed: StarfieldSeed.body)
        let field = StarfieldFieldGenerator.generate(using: &rng, size: Self.size)
        let ship = StarfieldShip.spawn(using: &rng, size: Self.size)
        let frame = StarfieldFrame(
            stars: field.stars, clusters: field.clusters, elapsedTime: 0,
            scrollProgress: 0, shootingStar: nil, ship: ship
        )
        assertStarfieldSnapshot(
            Canvas { context, size in StarfieldRenderer.draw(frame, into: &context, size: size, theme: Theme()) },
            named: "ship_fixture"
        )
    }
}
