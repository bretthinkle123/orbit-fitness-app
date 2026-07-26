import SwiftUI

/// CMP-1 — the card chrome every screen's cards/chips use. Two variants
/// (design-spec §2: "standard (r22, fill .32) · small chip (r10–14, fill
/// .38)"). NM-2: the design's `backdrop-filter` blur is approximated with
/// `.ultraThinMaterial` (not a flat translucent color alone), layered
/// UNDERNEATH the design's own literal tint color — this is what makes the
/// card read correctly both over today's flat `Theme.Neutral.
/// screenBackground` placeholder and, unchanged, once T17's real animated
/// starfield lands behind it ("tuned to 'stars read through'").
struct GlassCard<Content: View>: View {
    enum Style {
        case standard // r22 — the design's "standard" card
        case chip // r10-14 — the design's "small chip" (uses Metrics' upper chip radius)

        var cornerRadius: CGFloat {
            switch self {
            case .standard: return Metrics.Radius.card
            case .chip: return Metrics.Radius.chipMax
            }
        }

        var tint: Color {
            switch self {
            case .standard: return Theme.Neutral.cardFill
            case .chip: return Theme.Neutral.chipFill
            }
        }
    }

    var style: Style = .standard
    var padding: CGFloat = Metrics.Spacing.cardPaddingMin
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .circular)
        content()
            .padding(padding)
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(style.tint))
            .overlay(shape.stroke(Theme.Neutral.cardBorder, lineWidth: 1))
            .clipShape(shape)
    }
}
