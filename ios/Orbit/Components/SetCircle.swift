import SwiftUI

/// CMP-17 — Train's tappable set circles: 36pt numbered glyph, done =
/// 135° gradient fill + glow, pressed scale 0.9. The 36pt visual glyph is
/// padded to the ≥44pt hit target (`apple-hig-compliance`) via an outer
/// `.frame(minWidth:minHeight:)`, not by growing the glyph itself.
struct SetCircle: View {
    /// 1-based, both for the glyph's numeral and the VoiceOver label
    /// (README: "set circles expose 'Set n, done/not done' toggles").
    let setNumber: Int
    let isDone: Bool
    var theme = Theme()
    let action: () -> Void

    private static let diameter: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fillStyle)
                .overlay(
                    Text("\(setNumber)")
                        .font(.orbit(.body))
                        .foregroundStyle(Theme.Neutral.textPrimary)
                )
                .frame(width: Self.diameter, height: Self.diameter)
                .shadow(color: isDone ? theme.setDoneGlow : .clear, radius: Metrics.Shadow.setDoneGlowRadius)
                .frame(minWidth: Metrics.HitTarget.minimum, minHeight: Metrics.HitTarget.minimum)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: Metrics.Motion.avatarPressScale))
        .accessibilityLabel("Set \(setNumber), \(isDone ? "done" : "not done")")
        .accessibilityAddTraits(isDone ? [.isSelected] : [])
    }

    private var fillStyle: AnyShapeStyle {
        isDone
            ? AnyShapeStyle(LinearGradient(colors: [theme.primary, theme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Theme.Neutral.chipFill)
    }
}
