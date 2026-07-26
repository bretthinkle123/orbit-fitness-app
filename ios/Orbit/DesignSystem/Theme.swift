import Foundation
import SwiftUI

/// Per-channel sRGB blend toward a target hex color, matching the design
/// prototype's own `_blend(h1, h2, t)` (`Orbit Fitness.dc.html`, function at the
/// `_pal`/`_scale6` call sites) — a simple per-channel linear interpolation on the
/// raw 0–255 components, NOT a linear-light/perceptual blend. Verified against the
/// HTML `<script>` as the running source of truth per design-spec.md §7's
/// "when README and HTML disagree, the HTML script data is treated as the running
/// truth" rule; this is the ONLY color-math primitive in the app (CLAUDE.md "no
/// hardcoded hues" — every derived color in `Theme` is built by calling this, never
/// a second hand-computed hex literal).
enum OrbitColorMath {
    /// Blends `hexA` toward `hexB` by `fraction` (clamped 0...1) and returns a new
    /// `#rrggbb` hex string, one rounded channel at a time — mirrors the
    /// prototype's `Math.round(x + (b[i] - x) * t)` exactly so the two
    /// implementations produce identical output for the same inputs.
    static func blend(_ hexA: String, toward hexB: String, fraction: Double) -> String {
        let componentsA = rgbComponents(of: hexA)
        let componentsB = rgbComponents(of: hexB)
        let clampedFraction = min(max(fraction, 0), 1)

        let red = interpolate(componentsA.red, componentsB.red, clampedFraction)
        let green = interpolate(componentsA.green, componentsB.green, clampedFraction)
        let blue = interpolate(componentsA.blue, componentsB.blue, clampedFraction)

        return hexString(red: red, green: green, blue: blue)
    }

    private static func interpolate(_ start: Int, _ end: Int, _ fraction: Double) -> Int {
        Int((Double(start) + (Double(end) - Double(start)) * fraction).rounded())
    }

    /// Widened from `private` (T18): `Space/Textures.swift`'s gas-giant texture
    /// renderer is a second, legitimate consumer — it needs the raw 0-255
    /// components of an already-blended hex string (from `Theme.gasGiant*`
    /// below) to build a `CGColor`/`UIColor` for its offscreen `CGContext`,
    /// never to blend a NEW color of its own (that would defeat the whole
    /// point of routing every hue through this one facade). Reusing this
    /// function instead of adding a second hex-parsing helper in `Space/` is
    /// the `code-standards` "don't reinvent" rule; `check_no_inline_hex.sh`'s
    /// grep is unaffected either way since this function contains no hex
    /// literal itself.
    static func rgbComponents(of hex: String) -> (red: Int, green: Int, blue: Int) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        return (
            red: Int((value >> 16) & 0xFF),
            green: Int((value >> 8) & 0xFF),
            blue: Int(value & 0xFF)
        )
    }

    private static func hexString(red: Int, green: Int, blue: Int) -> String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }
}

/// One palette's raw primary/secondary/accent hex triple — the ONLY hardcoded hue
/// literals in the app (CLAUDE.md), verbatim from design-spec.md §3.1.
struct OrbitPalette: Equatable, Sendable {
    let primary: String
    let secondary: String
    let accent: String
}

/// The 4 user-selectable palette presets (design-spec §3.1). `apiValue` maps 1:1
/// onto the backend's `models.PALETTE_PRESETS` enum-CHECK values (`palette_preset`
/// column, `schemas/profile.py`'s `_PaletteLiteral`) — same literal strings, so
/// `PATCH /profile` round-trips with no translation table.
enum PalettePreset: String, CaseIterable, Identifiable, Sendable {
    case purple
    case blue
    case red
    case green

    var id: String { rawValue }

    /// Purple is the design's default (design-spec §3.1 "Purple (default)").
    static let `default`: PalettePreset = .purple

    var palette: OrbitPalette {
        switch self {
        case .purple:
            return OrbitPalette(primary: "#8B5CF6", secondary: "#D946EF", accent: "#F0ABFC")
        case .blue:
            return OrbitPalette(primary: "#3B82F6", secondary: "#22D3EE", accent: "#93C5FD")
        case .red:
            return OrbitPalette(primary: "#EF4444", secondary: "#FB7185", accent: "#FED7AA")
        case .green:
            return OrbitPalette(primary: "#10B981", secondary: "#84CC16", accent: "#6EE7B7")
        }
    }

    /// The exact string `PATCH /profile { palette_preset }` expects/returns.
    var apiValue: String { rawValue }
}

/// One stop of the 6-stop strength-level scale (Beginner → World Class), computed
/// from the active palette (design-spec §3.3). Every screen that shows a muscle
/// level (Body's legend/rows, the level chip) reads this — never a separately
/// hand-picked color per level.
struct LevelScaleStop: Equatable, Sendable {
    let name: String
    let colorHex: String
}

/// Computed once per palette selection — the single source of every palette-
/// derived color in the app (plan §Frontend: "`Theme` struct computed from the
/// active 3-color palette (blend/tint math, 6-stop level scale, neutrals) — no
/// hardcoded hues"). All 4 presets recolor everything that reads from here (AC28).
struct Theme: Equatable, Sendable {
    let preset: PalettePreset

    init(preset: PalettePreset = .default) {
        self.preset = preset
    }

    private var palette: OrbitPalette { preset.palette }

    // MARK: - Derived tints (design-spec §3.2)

    // Lowercased for consistency with every `OrbitColorMath.blend` output (which
    // always emits lowercase hex) — so two stops that happen to equal the raw
    // palette value (e.g. level 3 "Intermediate" == primary) compare equal to a
    // blend-derived string byte-for-byte, not just case-insensitively.
    var primaryHex: String { palette.primary.lowercased() }
    var secondaryHex: String { palette.secondary.lowercased() }
    var accentHex: String { palette.accent.lowercased() }

    var secondaryLightHex: String {
        OrbitColorMath.blend(palette.secondary, toward: "#ffffff", fraction: 0.28)
    }

    var primaryLightHex: String {
        OrbitColorMath.blend(palette.primary, toward: "#ffffff", fraction: 0.30)
    }

    var primaryLighterHex: String {
        OrbitColorMath.blend(palette.primary, toward: "#ffffff", fraction: 0.50)
    }

    var primaryDarkHex: String {
        OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.12)
    }

    /// Used for the two screen-background radial washes (design-spec §3.4).
    var primaryDark2Hex: String {
        OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.28)
    }

    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }
    var accent: Color { Color(hex: accentHex) }
    var secondaryLight: Color { Color(hex: secondaryLightHex) }
    var primaryLight: Color { Color(hex: primaryLightHex) }
    var primaryLighter: Color { Color(hex: primaryLighterHex) }
    var primaryDark: Color { Color(hex: primaryDarkHex) }
    var primaryDark2: Color { Color(hex: primaryDark2Hex) }

    // MARK: - Gas-giant procedural-texture tints (T18, README "3D & Animated
    // Background" §, verbatim from `Orbit Fitness.dc.html`'s `_gasTex(seed)`).
    // `Space/Textures.swift`'s `GasGiantTextureRenderer` is the ONLY consumer —
    // it never blends a hex literal itself, only reads these (same "one
    // facade, every new consumer plugs into it" rule the rest of this file
    // already follows).

    /// `_gasTex`'s canvas base fill before any band/shear/storm is drawn:
    /// `x.fillStyle = this._blend(GP.p1,'#000000',.3)`.
    var gasGiantBaseFillHex: String {
        OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.3)
    }

    /// `_gasTex`'s own 11-color band palette (`const cols = [...]`), verbatim
    /// order — index 3 (`blend(p1,black,.12)`) equals `primaryDarkHex`, index
    /// 4 is bare `primary`, index 6 (`priL`) equals `primaryLightHex`, and
    /// index 9 (`priLL`) equals `primaryLighterHex`; the other 7 entries are
    /// blends this texture alone needs, so they're computed inline here
    /// rather than adding 7 more one-off named properties nothing else reads
    /// (YAGNI — this array IS the named, documented thing).
    var gasGiantBandPalette: [String] {
        [
            OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.6),
            OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.42),
            OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.25),
            primaryDarkHex,
            primaryHex,
            OrbitColorMath.blend(palette.primary, toward: "#ffffff", fraction: 0.12),
            primaryLightHex,
            OrbitColorMath.blend(palette.primary, toward: palette.secondary, fraction: 0.4),
            OrbitColorMath.blend(palette.secondary, toward: "#ffffff", fraction: 0.15),
            primaryLighterHex,
            OrbitColorMath.blend(palette.accent, toward: "#ffffff", fraction: 0.3),
        ]
    }

    /// `_gasTex`'s storm-shadow ellipse: `this._blend(GP.p1,'#000000',.7)`.
    var gasGiantStormShadowHex: String {
        OrbitColorMath.blend(palette.primary, toward: "#000000", fraction: 0.7)
    }

    /// `_gasTex`'s ODD-indexed storm highlight (`i % 2 ? this._blend(GP.p3,
    /// '#ffffff',.35) : GP.secL`) — the even-indexed half already exists as
    /// `secondaryLightHex` (`secL`), reused as-is.
    var gasGiantStormHighlightAccentHex: String {
        OrbitColorMath.blend(palette.accent, toward: "#ffffff", fraction: 0.35)
    }

    // MARK: - 6-stop strength-level scale (design-spec §3.3)

    /// Stop order/rule verbatim: 1 Beginner, 2 Novice, 3 Intermediate (= primary),
    /// 4 Advanced, 5 Elite (= secondaryLight), 6 World Class.
    var levelScale: [LevelScaleStop] {
        [
            LevelScaleStop(name: "Beginner", colorHex: OrbitColorMath.blend(palette.primary, toward: "#0b0620", fraction: 0.55)),
            LevelScaleStop(name: "Novice", colorHex: OrbitColorMath.blend(palette.primary, toward: "#0b0620", fraction: 0.28)),
            LevelScaleStop(name: "Intermediate", colorHex: primaryHex),
            LevelScaleStop(name: "Advanced", colorHex: OrbitColorMath.blend(palette.primary, toward: palette.secondary, fraction: 0.55)),
            LevelScaleStop(name: "Elite", colorHex: secondaryLightHex),
            LevelScaleStop(name: "World Class", colorHex: OrbitColorMath.blend(palette.accent, toward: "#ffffff", fraction: 0.45)),
        ]
    }

    /// Level is 1-based (matches the backend's `muscle_base_levels.level` column,
    /// `1...6`) — traps out of range rather than silently clamping, since a level
    /// outside 1...6 would indicate a data bug worth surfacing loudly in a debug
    /// build.
    func levelScaleStop(forLevel level: Int) -> LevelScaleStop {
        precondition((1...6).contains(level), "Muscle level must be 1...6, got \(level)")
        return levelScale[level - 1]
    }

    // MARK: - Neutrals (constant across palettes — design-spec §3.4)

    enum Neutral {
        static let screenBackground = Color(hex: "#04050E")
        static let cardFill = Color(.sRGB, red: 23.0 / 255, green: 15.0 / 255, blue: 44.0 / 255, opacity: 0.32)
        static let cardBorder = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.10)
        static let chipFill = Color(.sRGB, red: 23.0 / 255, green: 15.0 / 255, blue: 44.0 / 255, opacity: 0.38)
        static let tabBarFill = Color(.sRGB, red: 22.0 / 255, green: 13.0 / 255, blue: 42.0 / 255, opacity: 0.78)
        static let tabBarActivePill = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.09)
        static let tabBarActiveText = Color(hex: "#F3E8FF")
        static let textPrimary = Color(hex: "#F4F0FF")
        static let textPrimaryRow = Color(hex: "#F1ECFD")
        static let textMuted = Color(.sRGB, red: 216.0 / 255, green: 206.0 / 255, blue: 238.0 / 255, opacity: 0.62)
        static let textFaint = Color(.sRGB, red: 216.0 / 255, green: 206.0 / 255, blue: 238.0 / 255, opacity: 0.45)
        static let figureNeutralFill = Color(.sRGB, red: 244.0 / 255, green: 240.0 / 255, blue: 255.0 / 255, opacity: 0.13)
        static let figureOutline = Color(.sRGB, red: 12.0 / 255, green: 6.0 / 255, blue: 26.0 / 255, opacity: 0.4)
        /// T14 addition: CMP-9 SegmentedToggle's selected-segment background
        /// ("selected / unselected (bg .14 vs transparent)", design-spec §2)
        /// — a white-opacity neutral, same family as `tabBarActivePill`
        /// above (a different, distinct opacity value for a different
        /// component), not a new brand hue.
        static let segmentedSelectedFill = Color.white.opacity(0.14)
        /// T17 addition: the starfield's two fixed (palette-independent)
        /// tints (`Orbit Fitness.dc.html`'s `_drawBg`: star fill `'#efeaff'`,
        /// ship-hull fill `'#ece5ff'`) — literal design constants, not
        /// derived from the active palette, same "constant across palettes"
        /// family as `figureNeutralFill`/`figureOutline` above.
        static let starfieldStarWhite = Color(hex: "#efeaff")
        static let starfieldShipHull = Color(hex: "#ece5ff")
        /// T18 addition: `_gasTex`'s pole-darkening gradient base
        /// (`rgba(10,4,30,*)` — a palette-independent dark navy, distinct
        /// from `screenBackground`'s own `#04050e`), applied at varying
        /// alpha per gradient stop by `Space/Textures.swift`'s renderer
        /// (`0.6` at the poles fading to `0` at the equator band) — same
        /// "constant across palettes" family as `starfieldStarWhite` above.
        static let gasGiantPoleShadow = Color(hex: "#0a041e")
        /// T18 addition: Train's rocky-asteroid base material color
        /// (`_makeScene`'s train branch: `color: hud ? 0x2a2244 :
        /// 0x5b4d7d`) — a FIXED rock-gray, not palette-derived (only the
        /// asteroid's EMISSIVE heat glow is palette-derived, via
        /// `theme.secondary` at the call site), same "constant across
        /// palettes" family as `gasGiantPoleShadow` above.
        static let asteroidRockBase = Color(hex: "#5b4d7d")
    }

    // MARK: - Palette-derived shadow/glow colors (geometry in `Metrics.Shadow`)

    var ctaGlow: Color { secondary.opacity(Metrics.Shadow.ctaOpacity) }
    var ringGlow: Color { secondary.opacity(Metrics.Shadow.ringGlowOpacity) }
    var setDoneGlow: Color { secondary.opacity(Metrics.Shadow.setDoneGlowOpacity) }
    var trainedMuscleGlow: Color { secondaryLight.opacity(Metrics.Shadow.trainedMuscleGlowOpacity) }
}

/// Derives the display-only protein/carb/fat percentage split from the canonical
/// gram targets — a client-side mirror of the backend's
/// `schemas.profile.compute_macro_split_percentages` (same Atwater factors, same
/// rounding-per-value shape) so Settings/Fuel can render the split the instant a
/// profile is fetched, without a second round trip (AC8: the design's stale
/// "40/35/25" copy is never shown; the split is always derived from grams).
enum OrbitMacroMath {
    private static let proteinKcalPerGram = 4.0
    private static let carbKcalPerGram = 4.0
    private static let fatKcalPerGram = 9.0

    /// Returns (proteinPct, carbPct, fatPct), each rounded independently — the
    /// three percentages need not sum to exactly 100, matching the backend's own
    /// documented rounding behavior. 2,350 kcal · P185/C240/F72 g → (31, 41, 28).
    static func computeSplitPercentages(kcalBudget: Int, proteinGrams: Int, carbGrams: Int, fatGrams: Int) -> (protein: Int, carb: Int, fat: Int) {
        guard kcalBudget > 0 else { return (0, 0, 0) }
        let budget = Double(kcalBudget)
        let proteinPct = Int((Double(proteinGrams) * proteinKcalPerGram / budget * 100).rounded())
        let carbPct = Int((Double(carbGrams) * carbKcalPerGram / budget * 100).rounded())
        let fatPct = Int((Double(fatGrams) * fatKcalPerGram / budget * 100).rounded())
        return (proteinPct, carbPct, fatPct)
    }
}
