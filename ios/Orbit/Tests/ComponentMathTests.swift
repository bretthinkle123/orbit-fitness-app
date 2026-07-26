import CoreGraphics
import Testing
@testable import Orbit

/// **Authored, not compiled, on this host** — see `.pipeline/
/// implementation-progress.md`'s T11-T14 entries; genuine execution happens
/// on the operator's Mac. Pure-logic math slices only, matching
/// `.pipeline/tasks.md`'s T14 test_strategy line: "pure-logic Swift Testing
/// where components have math (ProgressRing fraction clamping, WeekStrip
/// day computation, LevelSegments mapping)" — plus a few bonus math-bearing
/// components (`RestChip`/`HourTimeline`/`Sparkline`) discovered while
/// building them, tested for the same reason.

@Suite("Components — ProgressRing fraction clamping (CMP-5)")
struct ProgressRingMathTests {
    @Test("A fraction already in 0...1 passes through unchanged")
    func inRangeFractionUnchanged() {
        #expect(ProgressRing.clampedFraction(0.55) == 0.55)
    }

    @Test("An over-budget (>1) fraction clamps to 1, never overshoots the ring")
    func overBudgetClampsToOne() {
        #expect(ProgressRing.clampedFraction(1.4) == 1)
    }

    @Test("A negative fraction clamps to 0")
    func negativeClampsToZero() {
        #expect(ProgressRing.clampedFraction(-0.2) == 0)
    }

    @Test("A non-finite fraction (NaN/infinite) clamps to 0 rather than propagating garbage into .trim")
    func nonFiniteClampsToZero() {
        #expect(ProgressRing.clampedFraction(.nan) == 0)
        #expect(ProgressRing.clampedFraction(.infinity) == 0)
    }

    @Test("value/target computes and clamps in one call; a zero or negative target never divides by zero")
    func valueOverTargetComputesAndClamps() {
        #expect(ProgressRing.clampedFraction(value: 1303, target: 2350) == 1303.0 / 2350.0)
        #expect(ProgressRing.clampedFraction(value: 3000, target: 2350) == 1)
        #expect(ProgressRing.clampedFraction(value: 100, target: 0) == 0)
    }
}

@Suite("Components — WeekStrip day computation (CMP-19)")
struct WeekStripMathTests {
    @Test("An all-false week counts zero sessions")
    func allFalseCountsZero() {
        #expect(WeekStrip.sessionCount(in: Array(repeating: false, count: 7)) == 0)
    }

    @Test("An all-true week counts all seven sessions")
    func allTrueCountsSeven() {
        #expect(WeekStrip.sessionCount(in: Array(repeating: true, count: 7)) == 7)
    }

    @Test("A partial-fill week (design's own demo pattern: 4 of 7) counts exactly the filled days")
    func partialFillCountsExactly() {
        #expect(WeekStrip.sessionCount(in: [true, false, true, true, false, true, false]) == 4)
    }

    @Test("A non-7-length array still just counts true values — this component invents no day-of-week assumption")
    func nonStandardLengthStillCountsCorrectly() {
        #expect(WeekStrip.sessionCount(in: [true, true, false]) == 2)
        #expect(WeekStrip.sessionCount(in: []) == 0)
    }
}

@Suite("Components — LevelSegments mapping (CMP-21's sub-piece)")
struct LevelSegmentsMathTests {
    @Test("Levels 1...6 clamp to themselves (the valid range this app's DB CHECK constrains to)")
    func inRangeLevelsUnchanged() {
        for level in 1...6 {
            #expect(LevelSegments.clampedLevel(level) == level)
        }
    }

    @Test("A level below 1 (including 0) clamps to 0 — zero filled segments, not a crash")
    func belowRangeClampsToZero() {
        #expect(LevelSegments.clampedLevel(0) == 0)
        #expect(LevelSegments.clampedLevel(-3) == 0)
    }

    @Test("A level above 6 clamps to 6 — all segments filled, never an out-of-bounds draw")
    func aboveRangeClampsToSix() {
        #expect(LevelSegments.clampedLevel(7) == 6)
        #expect(LevelSegments.clampedLevel(99) == 6)
    }
}

@Suite("Components — RestChip m:ss formatting (CMP-18, bonus math)")
struct RestChipMathTests {
    @Test("Boundary seconds format with zero-padded seconds", arguments: [
        (0, "0:00"), (5, "0:05"), (59, "0:59"), (60, "1:00"), (65, "1:05"), (120, "2:00"),
    ])
    func formatsBoundarySeconds(seconds: Int, expected: String) {
        #expect(RestChip.formatted(seconds) == expected)
    }

    @Test("A negative input (should never occur, but must never crash) clamps to 0:00")
    func negativeSecondsClampToZero() {
        #expect(RestChip.formatted(-5) == "0:00")
    }
}

@Suite("Components — HourTimeline hour labeling (CMP-13, bonus math)")
struct HourTimelineMathTests {
    @Test("24-hour boundaries format correctly", arguments: [
        (0, "12 AM"), (6, "6 AM"), (9, "9 AM"), (12, "12 PM"), (13, "1 PM"), (21, "9 PM"), (23, "11 PM"),
    ])
    func formatsHourBoundaries(hour24: Int, expected: String) {
        #expect(HourTimeline.hourLabel(hour24) == expected)
    }
}

@Suite("Components — Sparkline point normalization (CMP-20, bonus math)")
struct SparklineMathTests {
    @Test("Fewer than 2 values produces no drawable points")
    func tooFewValuesProducesNoPoints() {
        #expect(Sparkline.normalizedPoints(values: [], size: CGSize(width: 100, height: 40)).isEmpty)
        #expect(Sparkline.normalizedPoints(values: [180.0], size: CGSize(width: 100, height: 40)).isEmpty)
    }

    @Test("A zero-size frame produces no drawable points (avoids a divide-by-zero step)")
    func zeroSizeFrameProducesNoPoints() {
        #expect(Sparkline.normalizedPoints(values: [180, 181], size: .zero).isEmpty)
    }

    @Test("Endpoints land exactly at the frame's left/right edges")
    func endpointsLandAtFrameEdges() {
        let points = Sparkline.normalizedPoints(values: [180, 181, 179, 182], size: CGSize(width: 90, height: 40))
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 90)
    }

    @Test("A flat series (min == max) places every point at the vertical midline, not a division by zero")
    func flatSeriesPlacesPointsAtMidline() {
        let points = Sparkline.normalizedPoints(values: [180, 180, 180], size: CGSize(width: 90, height: 40))
        #expect(points.allSatisfy { $0.y == 20 })
    }
}
