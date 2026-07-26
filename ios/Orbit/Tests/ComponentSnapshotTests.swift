import SnapshotTesting
import SwiftUI
import XCTest
@testable import Orbit

/// **Authored, not compiled or run, on this host** (no Swift toolchain —
/// `.pipeline/implementation-progress.md`'s T11-T14 entries). Genuine
/// snapshot recording/comparison happens on the operator's Mac
/// (`plans/00-mac-pipeline-readiness.md` Phase 5): the FIRST run there must
/// set `isRecording = true` (or use `SnapshotTesting`'s own record mode) to
/// capture the initial reference images, since none exist yet — this is
/// expected, not a bug.
///
/// **Advisory only, never a gate** (plan.md's test-strategy: "swift-
/// snapshot-testing... advisory"; `swift-conventions`: "Snapshot diffs are
/// advisory — never a deploy gate"). One snapshot per component
/// (`.pipeline/tasks.md` T14: "snapshot-test scaffolding per component on
/// flat backgrounds"), each on a plain, undecorated `Theme.Neutral.
/// screenBackground` rectangle — not the real starfield/hero (that's T17,
/// and would make every component's snapshot depend on a screen this task
/// doesn't own).
final class ComponentSnapshotTests: XCTestCase {
    /// Wraps a component at a fixed size over a flat background — the
    /// common fixture every snapshot below shares (rule-of-two → shared
    /// helper rather than repeating this ZStack 25 times).
    private func flatBackground(
        width: CGFloat = 320, height: CGFloat = 120, @ViewBuilder content: () -> some View
    ) -> some View {
        ZStack {
            Theme.Neutral.screenBackground
            content().padding()
        }
        .frame(width: width, height: height)
    }

    private func assertComponentSnapshot(
        _ view: some View, named name: String, width: CGFloat = 320, height: CGFloat = 120,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        assertSnapshot(
            of: flatBackground(width: width, height: height) { view },
            as: .image(layout: .fixed(width: width, height: height)),
            named: name, file: file, testName: testName, line: line
        )
    }

    // MARK: - CMP-1…8

    func testGlassCardStandard() {
        assertComponentSnapshot(GlassCard { Text("Card content").foregroundStyle(Theme.Neutral.textPrimary) }, named: "standard")
    }

    func testGlassCardChip() {
        assertComponentSnapshot(GlassCard(style: .chip) { Text("Chip").foregroundStyle(Theme.Neutral.textPrimary) }, named: "chip", width: 140, height: 60)
    }

    func testSectionLabel() {
        assertComponentSnapshot(SectionLabel("Mission"), named: "default", width: 200, height: 40)
    }

    func testHeaderWordmark() {
        assertComponentSnapshot(HeaderWordmark(text: "ORBIT"), named: "default", width: 200, height: 40)
    }

    func testAvatarSmall() {
        assertComponentSnapshot(Avatar(initials: "AK", size: .small), named: "small", width: 80, height: 80)
    }

    func testAvatarLargeTappable() {
        assertComponentSnapshot(Avatar(initials: "AK", size: .small, action: {}), named: "tappable", width: 80, height: 80)
    }

    func testProgressRingLarge() {
        assertComponentSnapshot(
            ProgressRing(size: .large, fraction: 0.55, tint: Theme().secondary, glow: Theme().ringGlow, accessibilityLabel: "1,303 of 2,350 kilocalories"),
            named: "large", width: 140, height: 140
        )
    }

    func testProgressRingSmall() {
        assertComponentSnapshot(
            ProgressRing(size: .small, fraction: 0.3, tint: Theme().primary, glow: Theme().ringGlow, accessibilityLabel: "74 of 185 grams"),
            named: "small", width: 80, height: 80
        )
    }

    func testMacroBar() {
        assertComponentSnapshot(MacroBar(fraction: 0.6, tint: Theme().secondaryLight, accessibilityLabel: "74 of 185 grams protein"), named: "default", height: 20)
    }

    func testGradientPillButton() {
        assertComponentSnapshot(GradientPillButton(title: "Start Push Day", action: {}), named: "default", height: 60)
    }

    func testStatChip() {
        assertComponentSnapshot(StatChip(label: "Strength score", value: "512", caption: "+4 this wk · Intermediate II"), named: "default", width: 180, height: 100)
    }

    // MARK: - CMP-9…16

    func testSegmentedToggle() {
        struct Wrapper: View {
            @State private var selection = "meals"
            var body: some View {
                SegmentedToggle(options: ["meals", "hour"], selection: $selection) { $0 == "meals" ? "Meals" : "By hour" }
            }
        }
        assertComponentSnapshot(Wrapper(), named: "default", width: 200, height: 60)
    }

    func testPlanetPickerChipActive() {
        assertComponentSnapshot(PlanetPickerChip(name: "Titan", levelIndex: 3, isActive: true, action: {}), named: "active", width: 140, height: 60)
    }

    func testPlanetPickerChipInactive() {
        assertComponentSnapshot(PlanetPickerChip(name: "Ember", levelIndex: 1, isActive: false, action: {}), named: "inactive", width: 140, height: 60)
    }

    func testQuickAddChipUnadded() {
        assertComponentSnapshot(QuickAddChip(name: "Salmon & Rice Bowl", isAdded: false, action: {}), named: "unadded", width: 220, height: 60)
    }

    func testQuickAddChipAdded() {
        assertComponentSnapshot(QuickAddChip(name: "Whey Shake", isAdded: true, action: {}), named: "added", width: 200, height: 60)
    }

    func testMealCardWithEntries() {
        let entries = [
            FoodEntry(id: 1, name: "Greek Yogurt + Granola", kcal: 342, proteinGrams: 20, carbGrams: 40, fatGrams: 8, mealGroup: "breakfast", loggedAt: Date(), dayKey: "2026-07-25"),
        ]
        assertComponentSnapshot(MealCard(title: "Breakfast", entries: entries), named: "with_entries", width: 320, height: 140)
    }

    func testMealCardEmptyState() {
        let quickAdds = [QuickFood(id: 1, name: "Salmon & Rice Bowl", kcal: 612, proteinGrams: 42, carbGrams: 58, fatGrams: 21)]
        assertComponentSnapshot(MealCard(title: "Dinner", entries: [], emptyStateQuickAdds: quickAdds), named: "empty_state", width: 320, height: 160)
    }

    func testHourTimelineRow() {
        let entries: [Int: [HourTimelineEntry]] = [7: [HourTimelineEntry(id: 1, name: "Greek Yogurt", kcal: 342)]]
        assertComponentSnapshot(HourTimeline(entriesByHour: entries, nowHour: 19), named: "default", width: 320, height: 900)
    }

    func testLogMethodButton() {
        assertComponentSnapshot(LogMethodButton(method: .scan), named: "scan", width: 80, height: 80)
    }

    func testCoachBanner() {
        assertComponentSnapshot(CoachBanner(leadIn: "Mission Control:", message: "burn rate trending up 2,847 kcal."), named: "default", width: 320, height: 90)
    }

    func testTipBanner() {
        assertComponentSnapshot(TipBanner(leadIn: "Tip:", message: "log sets on Train and trained muscles glow here."), named: "default", width: 320, height: 90)
    }

    // MARK: - CMP-17…22

    func testSetCircleDefault() {
        assertComponentSnapshot(SetCircle(setNumber: 1, isDone: false, action: {}), named: "default", width: 80, height: 80)
    }

    func testSetCircleDone() {
        assertComponentSnapshot(SetCircle(setNumber: 2, isDone: true, action: {}), named: "done", width: 80, height: 80)
    }

    func testRestChipVisible() {
        assertComponentSnapshot(RestChip(remainingSeconds: 95), named: "visible", width: 140, height: 60)
    }

    func testWeekStrip() {
        assertComponentSnapshot(WeekStrip(filledDays: [true, false, true, true, false, true, false]), named: "default", width: 260, height: 40)
    }

    func testSparkline() {
        assertComponentSnapshot(Sparkline(values: [183, 182.6, 182.8, 182.2, 182.4]), named: "default", width: 300, height: 80)
    }

    func testLevelSegments() {
        assertComponentSnapshot(LevelSegments(level: 4), named: "default", width: 100, height: 20)
    }

    func testMuscleRow() {
        assertComponentSnapshot(MuscleRow(muscleGroupName: "Chest", level: 4, isTrainedToday: true), named: "trained_today", width: 320, height: 40)
    }

    func testLevelLegend() {
        assertComponentSnapshot(LevelLegend(), named: "default", width: 320, height: 40)
    }

    // MARK: - CMP-24…25

    func testGlassTabBar() {
        struct Wrapper: View {
            @State private var selection: AppRouter.Tab = .home
            var body: some View {
                GlassTabBar(
                    items: [
                        GlassTabBarItem(id: .home, title: "Home", symbolName: "globe"),
                        GlassTabBarItem(id: .fuel, title: "Fuel", symbolName: "flame"),
                        GlassTabBarItem(id: .train, title: "Train", symbolName: "diamond"),
                        GlassTabBarItem(id: .body, title: "Body", symbolName: "person.fill"),
                    ],
                    selection: $selection
                )
            }
        }
        assertComponentSnapshot(Wrapper(), named: "default", width: 340, height: 80)
    }

    func testSettingsRowChevron() {
        assertComponentSnapshot(SettingsRow(title: "Daily budget", kind: .chevron(action: {})), named: "chevron", width: 320, height: 60)
    }

    func testSettingsRowToggle() {
        struct Wrapper: View {
            @State private var isOn = true
            var body: some View { SettingsRow(title: "Adaptive targets", kind: .toggle(isOn: $isOn)) }
        }
        assertComponentSnapshot(Wrapper(), named: "toggle", width: 320, height: 60)
    }

    func testSettingsRowDestructiveAction() {
        assertComponentSnapshot(SettingsRow(title: "Delete Account", kind: .action(isDestructive: true, action: {})), named: "destructive_action", width: 320, height: 60)
    }
}
