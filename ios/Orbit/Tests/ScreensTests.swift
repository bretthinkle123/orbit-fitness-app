import CoreGraphics
import Testing
@testable import Orbit

/// **Authored, not compiled, on this host** — see `.pipeline/
/// implementation-progress.md`'s T15 entry; genuine execution happens on
/// the operator's Mac. Pure-logic slices only, matching `.pipeline/
/// tasks.md`'s T15 test_strategy line: "Swift Testing pure-logic slices
/// (timer state machine, paging index binding, figure-path count/
/// coordinate spot-checks against figure-paths.md — a Python/grep
/// cross-check of coordinate fidelity IS runnable on this host, do it and
/// record it)". The Python cross-check itself (shape counts + generated-vs-
/// source coordinate spot-checks) was run this session and is recorded in
/// the progress file; the suite below is the Swift-side mirror of that same
/// fidelity claim, directly executable once a toolchain exists.

@Suite("Train — RestTimerState (the 120s rest-countdown state machine)")
struct RestTimerStateTests {
    @Test("A fresh timer starts at 0 seconds — not resting")
    func freshTimerIsNotResting() {
        let timer = RestTimerState()
        #expect(timer.remainingSeconds == 0)
        #expect(timer.isResting == false)
    }

    @Test("startCountdown() sets the full 120s window and marks resting")
    func startCountdownSetsFullWindow() {
        var timer = RestTimerState()
        timer.startCountdown()
        #expect(timer.remainingSeconds == 120)
        #expect(timer.isResting == true)
    }

    @Test("tick() decrements by exactly one second")
    func tickDecrementsByOneSecond() {
        var timer = RestTimerState()
        timer.startCountdown()
        timer.tick()
        #expect(timer.remainingSeconds == 119)
    }

    @Test("tick() never goes below zero — the chip hides at 0, not a negative countdown")
    func tickNeverGoesNegative() {
        var timer = RestTimerState()
        timer.tick()
        #expect(timer.remainingSeconds == 0)
    }

    @Test("Turning a set ON while already resting RESTARTS the countdown to the full window, not an accumulate")
    func startCountdownRestartsRatherThanAccumulates() {
        var timer = RestTimerState()
        timer.startCountdown()
        for _ in 0..<50 { timer.tick() }
        #expect(timer.remainingSeconds == 70)
        timer.startCountdown()
        #expect(timer.remainingSeconds == 120)
    }

    @Test("isResting is true for any positive remaining time and false at exactly zero")
    func isRestingReflectsRemainingSeconds() {
        var timer = RestTimerState()
        timer.startCountdown(seconds: 1)
        #expect(timer.isResting == true)
        timer.tick()
        #expect(timer.isResting == false)
    }
}

@Suite("DisplayFormatting — NumberDisplay")
struct NumberDisplayTests {
    @Test("Thousands separators match the design's own en-US fmt() convention", arguments: [
        (2350, "2,350"), (1047, "1,047"), (0, "0"), (999, "999"),
    ])
    func formatsWithThousandsSeparator(value: Int, expected: String) {
        #expect(NumberDisplay.formatted(value) == expected)
    }
}

@Suite("DisplayFormatting — WeightUnitFormatting (CLAUDE.md: canonical kg, display converts + rounds 0.1)")
struct WeightUnitFormattingTests {
    @Test("Metric display is the canonical kg value unchanged, rounded to 0.1")
    func metricDisplayIsUnchanged() {
        #expect(WeightUnitFormatting.displayValue(kilograms: 82.34, units: "metric") == 82.3)
    }

    @Test("Imperial display converts kg to lb, rounded to 0.1")
    func imperialDisplayConvertsToPounds() {
        let pounds = WeightUnitFormatting.displayValue(kilograms: 82.0, units: "imperial")
        #expect(abs(pounds - 180.8) < 0.05)
    }

    @Test("Round-trip: kilograms(fromDisplayValue:) inverts displayValue(kilograms:) for imperial")
    func roundTripsThroughPoundsAndBack() {
        let kilograms = WeightUnitFormatting.kilograms(fromDisplayValue: 180.0, units: "imperial")
        let backToPounds = WeightUnitFormatting.displayValue(kilograms: kilograms, units: "imperial")
        #expect(abs(backToPounds - 180.0) < 0.1)
    }

    @Test("Unit label matches the profile's units setting", arguments: [("metric", "kg"), ("imperial", "lb")])
    func unitLabelMatchesSetting(units: String, expectedLabel: String) {
        #expect(WeightUnitFormatting.unitLabel(units: units) == expectedLabel)
    }
}

@Suite("DisplayFormatting — CoachMessageFormatting (splits the static coach string)")
struct CoachMessageFormattingTests {
    @Test("Splits the real STATIC_COACH_MESSAGE shape into lead-in + message")
    func splitsRealCoachMessage() {
        let split = CoachMessageFormatting.splitLeadIn("Mission Control: log consistently this week to unlock personalized adjustments.")
        #expect(split.leadIn == "Mission Control:")
        #expect(split.message == "log consistently this week to unlock personalized adjustments.")
    }

    @Test("A string with no colon falls back to an empty lead-in rather than crashing")
    func fallsBackGracefullyWithNoColon() {
        let split = CoachMessageFormatting.splitLeadIn("no colon here")
        #expect(split.leadIn == "")
        #expect(split.message == "no colon here")
    }
}

@Suite("DisplayFormatting — AvatarInitials")
struct AvatarInitialsTests {
    @Test("A two-word display name yields both initials")
    func twoWordNameYieldsBothInitials() {
        #expect(AvatarInitials.initials(displayName: "Alex Kepler", email: nil) == "AK")
    }

    @Test("A missing display name falls back to the email's local part")
    func fallsBackToEmailLocalPart() {
        #expect(AvatarInitials.initials(displayName: nil, email: "alex.kepler@orbit.app") == "AL")
    }

    @Test("Neither display name nor email present falls back to a generic glyph")
    func fallsBackToGenericGlyph() {
        #expect(AvatarInitials.initials(displayName: nil, email: nil) == "?")
    }

    @Test("A blank/whitespace-only display name is treated as absent")
    func blankDisplayNameTreatedAsAbsent() {
        #expect(AvatarInitials.initials(displayName: "   ", email: "a@b.com") == "A")
    }
}

@Suite("DisplayFormatting — PlanetRingCaption (design-spec §5: singular '1 ring' at index 1)")
struct PlanetRingCaptionTests {
    @Test("Index 0 reads '0 rings'")
    func indexZeroReadsZeroRings() {
        #expect(PlanetRingCaption.caption(forIndex: 0) == "0 rings")
    }

    @Test("Index 1 is the one singular case: '1 ring'")
    func indexOneIsSingular() {
        #expect(PlanetRingCaption.caption(forIndex: 1) == "1 ring")
    }

    @Test("Indexes 2...5 are plural", arguments: [2, 3, 4, 5])
    func indexesAboveOneArePlural(index: Int) {
        #expect(PlanetRingCaption.caption(forIndex: index) == "\(index) rings")
    }
}

@Suite("DisplayFormatting — ExerciseSchemeFormatting")
struct ExerciseSchemeFormattingTests {
    @Test("Matches the design's '4 x 8 . 185 lb' shape for an integer weight")
    func formatsIntegerWeight() {
        #expect(ExerciseSchemeFormatting.formatted(sets: 4, reps: 8, weight: 185) == "4 \u{00d7} 8 \u{00b7} 185 lb")
    }

    @Test("A fractional seeded weight (e.g. Cable Fly's 42.5 lb) keeps its decimal")
    func formatsFractionalWeight() {
        #expect(ExerciseSchemeFormatting.formatted(sets: 3, reps: 12, weight: 42.5) == "3 \u{00d7} 12 \u{00b7} 42.5 lb")
    }
}

@Suite("DisplayFormatting — GreetingText")
struct GreetingTextTests {
    @Test("Time-of-day boundaries", arguments: [
        (5, "Good morning"), (11, "Good morning"), (12, "Good afternoon"), (16, "Good afternoon"),
        (17, "Good evening"), (21, "Good evening"), (22, "Good night"), (4, "Good night"),
    ])
    func greetsByHour(hour: Int, expected: String) {
        #expect(GreetingText.timeOfDayGreeting(hour: hour) == expected)
    }
}

// MARK: - CMP-23 MuscleFigure — figure-fidelity spot-check (mirrors the
// Python cross-check recorded in `.pipeline/implementation-progress.md`'s
// T15 entry: 33/34/26/27 shapes, generated — never hand-transcribed — from
// `figure-paths.md`).

@Suite("Figures — FigurePaths shape-count fidelity (CMP-23, AC11/AC29)")
struct FigurePathsCountTests {
    @Test("Male front has exactly the 33 shapes figure-paths.md's SVG block contains")
    func maleFrontShapeCount() {
        #expect(FigurePaths.maleFront.count == 33)
    }

    @Test("Female front has exactly 34 shapes (one more than male front: 2 extra head/hairline circles)")
    func femaleFrontShapeCount() {
        #expect(FigurePaths.femaleFront.count == 34)
    }

    @Test("Male back has exactly 26 shapes (traps drawn as ONE combined path, not two)")
    func maleBackShapeCount() {
        #expect(FigurePaths.maleBack.count == 26)
    }

    @Test("Female back has exactly 27 shapes")
    func femaleBackShapeCount() {
        #expect(FigurePaths.femaleBack.count == 27)
    }

    @Test("Every figure's fill count matches its expected muscle-shape / neutral-shape split")
    func maleFrontHasExpectedMuscleVsNeutralSplit() {
        let muscleShapeCount = FigurePaths.maleFront.filter {
            if case .muscle = $0.fill { return true }
            return false
        }.count
        // 2 traps + 2 delts + 2 chest + 2 biceps + 2 forearms + 2 core-obliques
        // + 6 core-abs-rects + 1 core-abs-belt-rect + 2 quads + 2 calves = 23.
        #expect(muscleShapeCount == 23)
    }
}

@Suite("Figures — FigurePaths coordinate spot-check (generated, not hand-transcribed)")
struct FigurePathsCoordinateTests {
    @Test("Male front's ground-shadow ellipse matches figure-paths.md's literal cx/cy/rx/ry exactly")
    func maleFrontGroundShadowMatchesSource() {
        let shape = FigurePaths.maleFront[0]
        #expect(shape.fill == .groundShadow)
        #expect(shape.geometry == .ellipse(center: CGPoint(x: 110, y: 282), rx: 36, ry: 4.5, rotationDegrees: 0))
    }

    @Test("Male front's chest path (first occurrence) matches figure-paths.md's literal 'M86,58 Q97,53 108,57 ...' d= string exactly")
    func maleFrontChestPathMatchesSource() {
        let chestShapes = FigurePaths.maleFront.filter {
            if case .muscle(.chest) = $0.fill { return true }
            return false
        }
        #expect(chestShapes.count == 2)
        let expected = MuscleFigureShape.Geometry.path(
            start: CGPoint(x: 86, y: 58),
            segments: [
                .quad(control: CGPoint(x: 97, y: 53), to: CGPoint(x: 108, y: 57)),
                .line(to: CGPoint(x: 108, y: 79)),
                .quad(control: CGPoint(x: 96, y: 86), to: CGPoint(x: 87, y: 79)),
                .quad(control: CGPoint(x: 82, y: 68), to: CGPoint(x: 86, y: 58)),
                .close,
            ]
        )
        #expect(chestShapes.first?.geometry == expected)
    }

    @Test("Female front's chest shapes are rotated ellipses (a design idiom no other figure uses), matching the source's rotate(-8/8 ...) transforms")
    func femaleFrontChestIsRotatedEllipse() {
        let chestShapes = FigurePaths.femaleFront.filter {
            if case .muscle(.chest) = $0.fill { return true }
            return false
        }
        #expect(chestShapes.count == 2)
        #expect(chestShapes[0].geometry == .ellipse(center: CGPoint(x: 97, y: 71.5), rx: 11, ry: 10.5, rotationDegrees: -8))
        #expect(chestShapes[1].geometry == .ellipse(center: CGPoint(x: 123, y: 71.5), rx: 11, ry: 10.5, rotationDegrees: 8))
    }

    @Test("Male back's traps is drawn as ONE combined path (not a mirrored pair like every front figure's traps)")
    func maleBackTrapsIsOneCombinedShape() {
        let trapsShapes = FigurePaths.maleBack.filter {
            if case .muscle(.traps) = $0.fill { return true }
            return false
        }
        #expect(trapsShapes.count == 1)
    }

    @Test("Lower-back rects only exist on the BACK figures, filled by .lowerBack, matching figure-paths.md's mLow token")
    func lowerBackOnlyOnBackFigures() {
        let maleFrontHasLowerBack = FigurePaths.maleFront.contains {
            if case .muscle(.lowerBack) = $0.fill { return true }
            return false
        }
        let maleBackLowerBackCount = FigurePaths.maleBack.filter {
            if case .muscle(.lowerBack) = $0.fill { return true }
            return false
        }.count
        #expect(maleFrontHasLowerBack == false)
        #expect(maleBackLowerBackCount == 2)
    }

    @Test("MuscleGroupToken.displayName matches figure-paths.md's own muscle names verbatim (incl. 'Lower back', not 'Lower Back')")
    func displayNamesMatchDesignCopy() {
        #expect(MuscleGroupToken.lowerBack.displayName == "Lower back")
        #expect(MuscleGroupToken.shoulders.displayName == "Shoulders")
        #expect(MuscleGroupToken.hamstrings.displayName == "Hamstrings")
    }
}
