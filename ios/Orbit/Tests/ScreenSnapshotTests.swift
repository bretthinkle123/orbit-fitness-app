import SnapshotTesting
import SwiftUI
import XCTest
@testable import Orbit

/// **Authored, not compiled or run, on this host** (no Swift toolchain —
/// see `.pipeline/implementation-progress.md`'s T11-T15 entries). Genuine
/// snapshot recording/comparison happens on the operator's Mac.
///
/// **Advisory only, never a gate** (plan.md's test-strategy; `swift-
/// conventions`) — one snapshot per data-backed screen (`.pipeline/
/// tasks.md` T15: "snapshot per screen vs reference (advisory) + human
/// diff-review"), each driven by `AppStoreTests.makeMockClient()`'s
/// (`CoreTests.swift`, T12) already-established server-shaped fixture, so
/// every screen renders its REAL loaded-state layout, not an empty
/// placeholder. The FIRST Mac-phase run must record reference images (none
/// exist yet).
final class ScreenSnapshotTests: XCTestCase {
    @MainActor
    private func makeLoadedStore() async -> AppStore {
        let client = AppStoreTests.makeMockClient()
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")
        await store.loadEverything()
        return store
    }

    private func assertScreenSnapshot(
        _ view: some View, named name: String,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        assertSnapshot(
            of: view
                .frame(width: 402, height: 874) // design-spec §4's reference frame
                // T17 note: every screen here now embeds a real
                // `TimelineView(.animation)`-driven `Space/StarfieldView` in
                // its shared ZStack recipe (it did not at T15, when this file
                // was first written — these were flat placeholder
                // backgrounds then). `TimelineView(.animation)` schedules off
                // the real wall clock, so without this override each
                // snapshot's captured `elapsedTime`/in-flight shooting-star-
                // or-ship state would depend on exactly when the test host
                // happens to render it — a genuine, new source of flaky
                // advisory diffs this task's own starfield-wiring introduced.
                // Forcing Reduce Motion routes through the SAME
                // `MotionPreference` facade every real device does: it
                // freezes `elapsedTime` at 0 and hides any transient
                // decoration, so the star/nebula field renders as the pure,
                // byte-stable function of its seed alone — deterministic
                // again, and still the real production code path (not a
                // stub), since Reduce Motion is a genuine, supported user
                // setting these same screens must render correctly under
                // regardless (AC30).
                .environment(\.accessibilityReduceMotion, true),
            as: .image(layout: .fixed(width: 402, height: 874)),
            named: name, file: file, testName: testName, line: line
        )
    }

    @MainActor
    func testHomeViewLoadedState() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(
            HomeView(store: store, authService: MockAuthService(), onOpenSettings: {}, onStartPushDay: {}),
            named: "loaded"
        )
    }

    @MainActor
    func testFuelViewLoadedState() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(FuelView(store: store), named: "loaded")
    }

    @MainActor
    func testTrainViewLoadedState() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(TrainView(store: store), named: "loaded")
    }

    @MainActor
    func testBodyViewLoadedState() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(BodyView(store: store), named: "loaded")
    }

    @MainActor
    func testWeightEntrySheet() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(WeightEntrySheet(store: store), named: "default")
    }

    @MainActor
    func testBudgetEditorSheet() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(BudgetEditorSheet(store: store), named: "default")
    }

    @MainActor
    func testMacroEditorSheet() async {
        let store = await makeLoadedStore()
        assertScreenSnapshot(MacroEditorSheet(store: store), named: "default")
    }
}
