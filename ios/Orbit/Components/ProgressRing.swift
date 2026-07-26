import SwiftUI

/// CMP-5 — the two dash-ring gauges (Home calories r54/9pt stroke, Fuel
/// macros r24/6pt stroke). NM-7: the design's SVG dash-offset math becomes
/// `Circle().trim(from:to:)` over a 0...1 fraction, rotated -90° so the
/// trim's 3-o'clock start matches the SVG's 12-o'clock `rotate(-90deg)`
/// convention (`Metrics.ProgressRing.startRotationDegrees`).
struct ProgressRing: View {
    enum Size {
        case large // r54, Home calories, 9pt stroke
        case small // r24, Fuel macros, 6pt stroke

        var radius: CGFloat {
            self == .large ? Metrics.ProgressRing.largeRadius : Metrics.ProgressRing.smallRadius
        }

        var lineWidth: CGFloat { self == .large ? 9 : 6 }
    }

    let size: Size
    /// The already-computed 0...1 progress fraction. `body` re-clamps
    /// defensively (a `.trim` outside 0...1 is undefined-looking, not a
    /// crash, but a caller passing a raw `eaten/target` ratio over budget
    /// should never visually overshoot the ring).
    let fraction: Double
    var tint: Color
    var glow: Color
    /// e.g. "1,303 of 2,350 kilocalories" (README's VoiceOver acceptance
    /// criterion) — built by the CALLER (Home/Fuel screens, T15), which
    /// knows the domain units; this component stays a dumb, reusable gauge.
    var accessibilityLabel: String

    var body: some View {
        let clamped = Self.clampedFraction(fraction)
        ZStack {
            Circle()
                .stroke(Theme.Neutral.chipFill, lineWidth: size.lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(Metrics.ProgressRing.startRotationDegrees))
                .shadow(color: glow, radius: Metrics.Shadow.ringGlowRadius)
                .animation(
                    .timingCurve(
                        Metrics.Motion.barRingCurve.x1, Metrics.Motion.barRingCurve.y1,
                        Metrics.Motion.barRingCurve.x2, Metrics.Motion.barRingCurve.y2,
                        duration: Metrics.Motion.barRingDurationMax
                    ),
                    value: clamped
                )
        }
        .frame(width: (size.radius + size.lineWidth / 2) * 2, height: (size.radius + size.lineWidth / 2) * 2)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    /// Clamps a raw progress fraction into the drawable 0...1 range — a
    /// pure function so an over-budget (>1) or negative value never
    /// produces a malformed `.trim`. Swift Testing exercises this directly
    /// (the task's named "ProgressRing fraction clamping" math slice).
    static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Convenience for the common "value against a target" case (Home's
    /// calorie ring, Fuel's macro rings) — computes AND clamps in one call.
    static func clampedFraction(value: Double, target: Double) -> Double {
        guard target > 0, value.isFinite else { return 0 }
        return clampedFraction(value / target)
    }
}
