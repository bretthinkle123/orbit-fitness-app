import SwiftUI

/// CMP-10 — Home's "Your system" 6 planet chips (Ember…Zenith), each dot
/// colored by the active palette's level scale; active = highlight fill +
/// secondaryLight border; pressed scale 0.94.
struct PlanetPickerChip: View {
    let name: String
    /// Which of the 6 level-scale stops colors this chip's dot (1...6) —
    /// design-spec: "dot = level color."
    let levelIndex: Int
    let isActive: Bool
    var theme = Theme()
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: theme.levelScaleStop(forLevel: levelIndex).colorHex))
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.orbit(.caption))
                    .foregroundStyle(isActive ? Theme.Neutral.textPrimary : Theme.Neutral.textMuted)
            }
            .padding(.horizontal, Metrics.Spacing.cardPaddingMin)
            .frame(minHeight: Metrics.HitTarget.minimum)
            .background(isActive ? theme.primary.opacity(0.22) : Theme.Neutral.chipFill)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular)
                    .stroke(isActive ? theme.secondaryLight : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular))
        }
        .buttonStyle(PressableScaleButtonStyle(scale: Metrics.Motion.planetChipPressScale))
        .accessibilityLabel(name)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
