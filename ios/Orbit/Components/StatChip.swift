import SwiftUI

/// CMP-8 — Home's paired stat chips (Strength score, Burn rate): a
/// `GlassCard`(.chip) holding a label, a big number, and an optional
/// caption line (e.g. "+4 this wk · Intermediate II").
struct StatChip: View {
    let label: String
    let value: String
    var caption: String?

    var body: some View {
        GlassCard(style: .chip) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(label)
                Text(value)
                    .font(.orbit(.bigStatHomeStat))
                    .foregroundStyle(Theme.Neutral.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption.map { "\(label), \(value), \($0)" } ?? "\(label), \(value)")
    }
}
