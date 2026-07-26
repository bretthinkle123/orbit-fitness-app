import SwiftUI

/// CMP-3 — every screen header's wordmark ("ORBIT" / "FUEL" / "TRAIN" /
/// "BODY") + its leading gradient dot. The dot's 8pt diameter isn't a named
/// design-spec token (the normalized spec records "gradient dot" without a
/// pixel value) — a judgment call sized to sit comfortably beside the
/// wordmark's own type ramp, flagged rather than silently invented.
struct HeaderWordmark: View {
    let text: String
    var theme = Theme()

    private static let dotDiameter: CGFloat = 8

    var body: some View {
        HStack(spacing: Metrics.Spacing.cardGap / 2) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [theme.primary, theme.secondary],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            Text(text.uppercased())
                .font(.orbit(.wordmark))
                .tracking(OrbitTextStyle.wordmark.trackingEm * OrbitTextStyle.wordmark.size)
                .foregroundStyle(Theme.Neutral.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
