import Foundation
import SwiftUI

/// Layout, radius, elevation, and motion constants verbatim from
/// `.pipeline/design-spec.md` §3.6. Palette-independent facts only — anything that
/// needs a palette color (shadow tint, glow color) lives on `Theme` instead, which
/// combines these geometry tokens with the active palette.
enum Metrics {
    /// Screen/content/card spacing (design-spec §3.6 "Screen / content padding",
    /// "Card padding").
    enum Spacing {
        static let screenPadding: CGFloat = 16
        static let contentTopPadding: CGFloat = 64
        static let contentSidePadding: CGFloat = 16
        static let contentBottomPadding: CGFloat = 140
        static let cardPaddingMin: CGFloat = 16
        static let cardPaddingMax: CGFloat = 18
        static let cardGap: CGFloat = 12
        static let headerSidePadding: CGFloat = 4
    }

    /// Top spacer each screen reserves for its pinned 3D hero (design-spec §3.6
    /// "Hero top spacer"; Body has no hero, so no entry here).
    enum HeroSpacer {
        static let home: CGFloat = 244
        static let fuel: CGFloat = 224
        static let train: CGFloat = 214
    }

    /// T18 additions: the 3D hero's own on-screen (2D, point-based) frame —
    /// distinct from `HeroSpacer` above (which is how much CONTENT space each
    /// screen reserves, always smaller than the hero itself so cards slide up
    /// over its lower portion, README "3D hero in the top ~440pt"). 3D-SPACE
    /// values (sphere radii, ring counts, camera z, orbit speeds) are NOT
    /// here — they're `Space/`'s own constants (`StarfieldFieldGenerator`
    /// already established this split: fixed 3D/canvas-space numbers live
    /// with the code that consumes them, only 2D UI-frame geometry lives in
    /// this palette-independent facts file).
    enum Hero {
        /// README "a 3D hero in the top ~440pt (Home/Fuel/Train; Body has none)".
        static let sceneHeight: CGFloat = 440
        /// README "Hero layer also parallax-translates up to −95pt" —
        /// `translateY(-scroll*95)`, scroll 0...1.
        static let parallaxMaxOffset: CGFloat = 95
    }

    /// Corner radii (design-spec §3.6 "Radii"). CSS `border-radius` is a circular
    /// arc — use `style: .circular` on `RoundedRectangle` for these to match the
    /// design exactly (per `claude-design-to-swiftui`'s accuracy note), not the
    /// default squircle `.continuous`.
    enum Radius {
        static let card: CGFloat = 22
        static let pillButton: CGFloat = 23
        static let pillButtonHeight: CGFloat = 46
        static let tabBar: CGFloat = 26
        static let chipMin: CGFloat = 10
        static let chipMax: CGFloat = 14
        static let segmentedMin: CGFloat = 8
        static let segmentedMax: CGFloat = 13
        static let progressBarMin: CGFloat = 4
        static let progressBarMax: CGFloat = 7
    }

    /// Shadow/glow geometry (design-spec §3.6 "Shadow / glow"). CSS blur radius maps
    /// to a SwiftUI shadow `radius` of roughly half the blur value (`claude-design-
    /// to-swiftui` conversion rule) — the color itself is palette-derived, so it
    /// lives on `Theme.glow*` instead of here.
    enum Shadow {
        static let ctaBlurRadius: CGFloat = 11 // css blur 22 / 2
        static let ctaOffsetY: CGFloat = 6
        static let ctaOpacity: Double = 0.35
        static let ringGlowRadius: CGFloat = 3.5 // css blur 7 / 2
        static let ringGlowOpacity: Double = 0.55
        static let setDoneGlowRadius: CGFloat = 6 // css blur 12 / 2
        static let setDoneGlowOpacity: Double = 0.45
        static let trainedMuscleGlowRadius: CGFloat = 3.5 // css blur 7 / 2
        static let trainedMuscleGlowOpacity: Double = 0.85
    }

    /// Motion durations/curves/amplitudes (design-spec §3.6 "Motion"). Every use
    /// site gates the repeating variants (float/pulse/starfield/scroll-driven 3D)
    /// behind Reduce Motion per the accessibility acceptance criteria — this enum
    /// only carries the raw numbers, not the gating (that's each view's job).
    enum Motion {
        static let fillDuration: Double = 0.4
        static let barRingDurationMin: Double = 0.5
        static let barRingDurationMax: Double = 0.7
        /// cubic-bezier(.22, 1, .36, 1) control points, for a matching `.timingCurve`.
        static let barRingCurve = (x1: 0.22, y1: 1.0, x2: 0.36, y2: 1.0)
        static let pressScale: CGFloat = 0.95
        static let avatarPressScale: CGFloat = 0.9
        static let ctaPressScale: CGFloat = 0.98
        static let floatAmplitude: CGFloat = 7
        static let floatDurationMin: Double = 5.5
        static let floatDurationMax: Double = 6.0
        static let pulseDuration: Double = 2.4
        static let sheetSlideDuration: Double = 0.5
        /// T14 additions (design-spec §2's component table names these two
        /// exact numbers for specific components, distinct from the
        /// generic bar/ring range above): CMP-6 MacroBar's own
        /// width-animation duration ("animates width .6s" — ProgressRing's
        /// dash-offset separately uses `barRingDurationMax` = 0.7s exactly).
        static let macroBarDuration: Double = 0.6
        /// CMP-10 PlanetPickerChip's own press scale ("pressed (scale .94)")
        /// — a fourth, distinct value in this already-centralized
        /// press-scale family (alongside `pressScale`/`avatarPressScale`/
        /// `ctaPressScale`), not a new mechanism.
        static let planetChipPressScale: CGFloat = 0.94
    }

    /// SVG-ring → SwiftUI `.trim` math (design-spec §3.6 "Progress-ring math"; NM-7).
    enum ProgressRing {
        static let largeRadius: CGFloat = 54
        static let largeCircumference: CGFloat = 339.3
        static let smallRadius: CGFloat = 24
        static let smallCircumference: CGFloat = 150.8
        /// SVG rings start at 12 o'clock (`rotate(-90deg)`); SwiftUI `Circle().trim`
        /// starts at 3 o'clock, so every ring needs this rotation applied.
        static let startRotationDegrees: Double = -90
    }

    /// Apple HIG minimum tappable area (apple-hig-compliance) — every pressable
    /// control's hit target is at least this large even when its glyph (36pt set
    /// circles, 30pt avatar) is visually smaller; pad the tappable area, not the
    /// glyph, to stay faithful to the design's smaller visual sizes.
    enum HitTarget {
        static let minimum: CGFloat = 44
    }
}
