import SwiftUI

/// CMP-22 — Body's 6-stop level-scale legend bar, "Beginner … World
/// Class". A continuous gradient across all 6 `Theme.levelScale` stops
/// (distinct from `LevelSegments`' discrete per-row bar, CMP-21's
/// sub-piece — this is the standalone full-scale key, not a per-muscle
/// indicator).
struct LevelLegend: View {
    var theme = Theme()

    private static let barHeight = Metrics.Radius.progressBarMax

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LinearGradient(
                colors: theme.levelScale.map { Color(hex: $0.colorHex) },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: Self.barHeight)
            .clipShape(Capsule())

            HStack {
                Text(theme.levelScale.first?.name ?? "")
                Spacer()
                Text(theme.levelScale.last?.name ?? "")
            }
            .font(.orbit(.micro))
            .foregroundStyle(Theme.Neutral.textFaint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level scale, \(theme.levelScale.first?.name ?? "") to \(theme.levelScale.last?.name ?? "")")
    }
}
