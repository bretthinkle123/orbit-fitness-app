import Testing
@testable import Orbit

/// Expected values below are computed independently (Python re-implementation of
/// the design prototype's own `_blend(h1, h2, t)` — `Orbit Fitness.dc.html`) and
/// checked into this file as literals, so a regression in `OrbitColorMath.blend`
/// or in `Theme`'s derivation rules fails a concrete number, not a vague "looks
/// different" snapshot. AC28's "no hardcoded hues" grep check
/// (`scripts/check_no_inline_hex.sh`) is what keeps these literals confined to
/// `DesignSystem/` — this file lives there.
///
/// **Authored, not compiled, on this host:** no Swift toolchain/Xcode exists on
/// this Linux build machine (`.pipeline/implementation-progress.md`'s T11 entry
/// records this explicitly). These tests are written to the exact Swift Testing
/// API shape and will run for real on the operator's Mac
/// (`plans/00-mac-pipeline-readiness.md` Phase 5).
@Suite("Theme — palette blend/tint math")
struct ThemeColorMathTests {
    /// One preset's full set of independently-computed expected derived-tint hex
    /// values, so all 4 presets get the identical assertion shape.
    struct Expectation: Sendable {
        let preset: PalettePreset
        let secondaryLight: String
        let primaryLight: String
        let primaryLighter: String
        let primaryDark: String
        let primaryDark2: String
        let levelScale: [String]
    }

    static let expectations: [Expectation] = [
        Expectation(
            preset: .purple,
            secondaryLight: "#e47af3",
            primaryLight: "#ae8df9",
            // #c5aefb, not #c5aefa: the blue channel lands on an exact .5 tie
            // (246 + (255-246)*0.5 = 250.5) and the prototype's own
            // `Math.round(x + (b[i] - x) * t)` rounds that UP to 251 = 0xfb.
            // The original fixture value rounded it down, inconsistently with
            // the red preset's 161.5 → 162 in this same table, which does round
            // up. Hand-computed fixture error, not an implementation bug.
            primaryLighter: "#c5aefb",
            primaryDark: "#7a51d8",
            primaryDark2: "#6442b1",
            levelScale: ["#452d80", "#6744ba", "#8b5cf6", "#b650f2", "#e47af3", "#f7d1fd"]
        ),
        Expectation(
            preset: .blue,
            secondaryLight: "#60dff3",
            primaryLight: "#76a8f9",
            // #9dc1fb, not #9dc0fa: same exact-.5 tie as the purple preset
            // above, in BOTH the green (192.5 → 193 = 0xc1) and blue
            // (250.5 → 251 = 0xfb) channels.
            primaryLighter: "#9dc1fb",
            primaryDark: "#3472d8",
            primaryDark2: "#2a5eb1",
            levelScale: ["#213e80", "#2e5fba", "#3b82f6", "#2daff2", "#60dff3", "#c4dffe"]
        ),
        Expectation(
            preset: .red,
            secondaryLight: "#fc99a7",
            primaryLight: "#f47c7c",
            primaryLighter: "#f7a2a2",
            primaryDark: "#d23c3c",
            primaryDark2: "#ac3131",
            levelScale: ["#722230", "#af333a", "#ef4444", "#f65d68", "#fc99a7", "#fee9d0"]
        ),
        Expectation(
            preset: .green,
            secondaryLight: "#a6da57",
            primaryLight: "#58cea7",
            primaryLighter: "#88dcc0",
            primaryDark: "#0ea372",
            primaryDark2: "#0c855d",
            levelScale: ["#0d574c", "#0f8766", "#10b981", "#50c346", "#a6da57", "#aff2d7"]
        ),
    ]

    @Test("Derived tints (secondaryLight/primaryLight/primaryLighter/primaryDark/primaryDark2) match the design prototype's own _blend() output, per preset", arguments: expectations)
    func derivedTintsMatchPrototype(_ expectation: Expectation) {
        let theme = Theme(preset: expectation.preset)
        #expect(theme.secondaryLightHex == expectation.secondaryLight)
        #expect(theme.primaryLightHex == expectation.primaryLight)
        #expect(theme.primaryLighterHex == expectation.primaryLighter)
        #expect(theme.primaryDarkHex == expectation.primaryDark)
        #expect(theme.primaryDark2Hex == expectation.primaryDark2)
    }

    @Test("6-stop strength-level scale (Beginner..World Class) matches the prototype's _scale6() output, per preset", arguments: expectations)
    func levelScaleMatchesPrototype(_ expectation: Expectation) {
        let theme = Theme(preset: expectation.preset)
        let actual = theme.levelScale.map(\.colorHex)
        #expect(actual == expectation.levelScale)
    }

    @Test("Level scale names are Beginner..World Class in order, independent of preset", arguments: PalettePreset.allCases)
    func levelScaleNamesAreFixed(_ preset: PalettePreset) {
        let theme = Theme(preset: preset)
        #expect(theme.levelScale.map(\.name) == [
            "Beginner", "Novice", "Intermediate", "Advanced", "Elite", "World Class",
        ])
    }

    @Test("Intermediate stop (level 3) is exactly the palette's own primary color")
    func intermediateStopEqualsPrimary() {
        let theme = Theme(preset: .purple)
        #expect(theme.levelScaleStop(forLevel: 3).colorHex == theme.primaryHex)
    }

    @Test("Elite stop (level 5) is exactly secondaryLight")
    func eliteStopEqualsSecondaryLight() {
        let theme = Theme(preset: .purple)
        #expect(theme.levelScaleStop(forLevel: 5).colorHex == theme.secondaryLightHex)
    }

    @Test("blend(x, x, anyFraction) is a no-op — blending a color toward itself never changes it")
    func blendTowardSelfIsIdentity() {
        #expect(OrbitColorMath.blend("#8B5CF6", toward: "#8B5CF6", fraction: 0.5) == "#8b5cf6")
    }

    @Test("blend fraction 0 returns the start color unchanged; fraction 1 returns the target color")
    func blendEndpointsAreExact() {
        #expect(OrbitColorMath.blend("#8B5CF6", toward: "#FFFFFF", fraction: 0) == "#8b5cf6")
        #expect(OrbitColorMath.blend("#8B5CF6", toward: "#FFFFFF", fraction: 1) == "#ffffff")
    }

    @Test("blend fraction is clamped to 0...1 rather than extrapolating out of range")
    func blendFractionIsClamped() {
        let overshoot = OrbitColorMath.blend("#8B5CF6", toward: "#FFFFFF", fraction: 1.5)
        #expect(overshoot == "#ffffff")
        let undershoot = OrbitColorMath.blend("#8B5CF6", toward: "#FFFFFF", fraction: -0.5)
        #expect(undershoot == "#8b5cf6")
    }

    @Test("All 4 presets produce distinct primary colors — recoloring is real, not a no-op")
    func allPresetsAreDistinct() {
        let primaries = Set(PalettePreset.allCases.map { Theme(preset: $0).primaryHex })
        #expect(primaries.count == PalettePreset.allCases.count)
    }

    @Test("Purple is the default preset (design-spec §3.1)")
    func purpleIsDefault() {
        #expect(PalettePreset.default == .purple)
        #expect(Theme().preset == .purple)
    }
}

/// AC8: gram targets are canonical; the split percentage is always DERIVED, never
/// the design's stale "40/35/25" prototype copy. This mirrors
/// `schemas.profile.compute_macro_split_percentages` (backend) so both layers
/// agree on the exact same worked example.
@Suite("Theme — derived macro-split percentages (AC8)")
struct MacroSplitMathTests {
    @Test("2,350 kcal budget · P185/C240/F72 g derives to (31, 41, 28) — the plan's worked example")
    func workedExampleMatchesPlan() {
        let result = OrbitMacroMath.computeSplitPercentages(kcalBudget: 2350, proteinGrams: 185, carbGrams: 240, fatGrams: 72)
        #expect(result.protein == 31)
        #expect(result.carb == 41)
        #expect(result.fat == 28)
    }

    @Test("A zero or negative kcal budget derives to (0, 0, 0) rather than dividing by zero")
    func zeroBudgetIsSafe() {
        let result = OrbitMacroMath.computeSplitPercentages(kcalBudget: 0, proteinGrams: 185, carbGrams: 240, fatGrams: 72)
        #expect(result == (0, 0, 0))
    }

    @Test("Zero-gram targets derive to a zero percentage for that macro, not a NaN/crash")
    func zeroGramsIsZeroPercent() {
        let result = OrbitMacroMath.computeSplitPercentages(kcalBudget: 2000, proteinGrams: 0, carbGrams: 0, fatGrams: 0)
        #expect(result == (0, 0, 0))
    }
}

/// T16's accessibility pass: `MotionPreference` is the ONE facade every
/// Reduce-Motion-gated repeating animation asks (`MuscleFigure`'s float
/// loop, `HourTimeline`'s pulse, and — once built — `Space/`'s starfield
/// drift/ships/scroll-driven 3D, T17/T18). A pure, trivial function, but
/// worth a direct test since every one of those call sites now depends on
/// it never silently inverting its own sense.
@Suite("MotionPreference — Reduce Motion gating (T16)")
struct MotionPreferenceTests {
    @Test("Repeating animations are allowed when Reduce Motion is OFF")
    func allowedWhenReduceMotionOff() {
        #expect(MotionPreference.repeatingAnimationsAllowed(reduceMotion: false))
    }

    @Test("Repeating animations are NOT allowed when Reduce Motion is ON")
    func disallowedWhenReduceMotionOn() {
        #expect(!MotionPreference.repeatingAnimationsAllowed(reduceMotion: true))
    }
}

/// `AccessibilityIdentifierSlug` builds the stable per-instance XCUITest
/// identifiers `Tests/SmokeUITests.swift` (T16) taps against — e.g.
/// `"train-set-\(slug(exercise.name))-\(setIndex + 1)"`. Tested directly
/// against the actual seeded strings (`migrations/versions/
/// 0002_seed_catalog_program_levels.py`, read directly this session) so a
/// regression here would break the smoke test's own selectors, not just an
/// abstract string function.
@Suite("AccessibilityIdentifierSlug — XCUITest identifier construction (T16)")
struct AccessibilityIdentifierSlugTests {
    @Test("Slugs the seeded quick-food names exactly as the smoke test expects")
    func slugsSeededQuickFoodNames() {
        #expect(AccessibilityIdentifierSlug.slug("Salmon & Rice Bowl") == "salmon-rice-bowl")
        #expect(AccessibilityIdentifierSlug.slug("Whey Shake") == "whey-shake")
        #expect(AccessibilityIdentifierSlug.slug("Chicken Stir-fry") == "chicken-stir-fry")
    }

    @Test("Slugs the seeded Push Day exercise names exactly as the smoke test expects")
    func slugsSeededExerciseNames() {
        #expect(AccessibilityIdentifierSlug.slug("Barbell Bench Press") == "barbell-bench-press")
        #expect(AccessibilityIdentifierSlug.slug("Seated Overhead Press") == "seated-overhead-press")
        #expect(AccessibilityIdentifierSlug.slug("Triceps Pushdown") == "triceps-pushdown")
    }

    @Test("Collapses multiple internal spaces and is idempotent on an already-slugged string")
    func collapsesWhitespaceAndIsIdempotent() {
        #expect(AccessibilityIdentifierSlug.slug("Cable  Fly") == "cable-fly")
        #expect(AccessibilityIdentifierSlug.slug("already-slugged") == "already-slugged")
    }
}
