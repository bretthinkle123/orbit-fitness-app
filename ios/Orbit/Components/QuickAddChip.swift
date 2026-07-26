import SwiftUI

/// CMP-11 — Fuel's Dinner quick-add chips: "+name" (unadded) / "✓name"
/// (added, tinted). Quick-add is idempotent per food (design-spec §5), so
/// an already-added chip disables itself rather than allowing a second tap
/// to double-log the same food.
struct QuickAddChip: View {
    let name: String
    let isAdded: Bool
    var theme = Theme()
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isAdded ? "✓ \(name)" : "+ \(name)")
                .font(.orbit(.caption))
                .foregroundStyle(isAdded ? Theme.Neutral.textPrimary : Theme.Neutral.textMuted)
                .padding(.horizontal, Metrics.Spacing.cardPaddingMin)
                .frame(minHeight: Metrics.HitTarget.minimum)
                .background(isAdded ? theme.secondary.opacity(0.28) : Theme.Neutral.chipFill)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular))
        }
        .buttonStyle(PressableScaleButtonStyle(scale: Metrics.Motion.pressScale))
        .disabled(isAdded)
        .accessibilityLabel(isAdded ? "\(name), added" : "Add \(name)")
        .accessibilityAddTraits(isAdded ? [.isSelected] : [])
    }
}
