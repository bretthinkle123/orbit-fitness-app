import SwiftUI

/// CMP-6 — the 7pt rounded progress bar (Home's 3 macro rows, Fuel's
/// remaining-kcal bar). Colors are supplied by the caller (secondaryLight/
/// primary/accent per macro, design-spec §2) rather than fixed here, since
/// the same bar shape serves three different tints depending on context.
struct MacroBar: View {
    /// Already-computed 0...1 fill fraction (reuses `ProgressRing`'s own
    /// clamping math — one fraction-clamping rule for the whole app, not a
    /// second hand-rolled one here).
    let fraction: Double
    let tint: Color
    var height: CGFloat = Metrics.Radius.progressBarMax
    var accessibilityLabel: String

    var body: some View {
        let clamped = ProgressRing.clampedFraction(fraction)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Neutral.chipFill)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * clamped)
                    .animation(.easeOut(duration: Metrics.Motion.macroBarDuration), value: clamped)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }
}
