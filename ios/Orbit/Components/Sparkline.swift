import SwiftUI

/// CMP-20 — Home's 30-day weight trend: area fill + line + scatter dots +
/// an emphasized end dot. Data-driven from `GET /weight`'s `entries`
/// (T7) — the caller supplies chronological (oldest-first) weight values;
/// this component invents no window-length assumption of its own (AC12's
/// 30-day bound is the server's, not redeclared here).
struct Sparkline: View {
    let values: [Double]
    var theme = Theme()

    var body: some View {
        GeometryReader { geometry in
            if values.count >= 2 {
                let points = Self.normalizedPoints(values: values, size: geometry.size)
                ZStack {
                    areaFill(points: points, size: geometry.size)
                    line(points: points)
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let isLast = index == points.count - 1
                        Circle()
                            .fill(isLast ? theme.accent : theme.secondaryLight)
                            .frame(width: isLast ? 6 : 3, height: isLast ? 6 : 3)
                            .position(point)
                    }
                }
            }
        }
        // Decorative alongside an adjacent, already-labeled numeric trend
        // (e.g. "182.4 lb, down 0.4 lb / wk" — the caller renders that as
        // real text); a trend LINE has no single spoken value/target the
        // way a ring/bar does, so VoiceOver skips straight to that label.
        .accessibilityHidden(true)
    }

    private func line(points: [CGPoint]) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(theme.secondaryLight, lineWidth: 2)
    }

    private func areaFill(points: [CGPoint], size: CGSize) -> some View {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [theme.secondaryLight.opacity(0.35), theme.secondaryLight.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// Maps raw chronological values onto an evenly-spaced point grid
    /// within `size` — a pure function. Swift Testing exercises the
    /// empty/single-value guard (returns `[]`), a flat series (`min ==
    /// max`, every point should land at the vertical midline), and that
    /// endpoints land exactly at the frame's left/right edges.
    static func normalizedPoints(values: [Double], size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let normalizedY = range > 0 ? (value - minValue) / range : 0.5
            let y = size.height - (CGFloat(normalizedY) * size.height)
            return CGPoint(x: CGFloat(index) * stepX, y: y)
        }
    }
}
