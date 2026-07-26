import SwiftUI

/// CMP-4 — the initials circle used on Home's header (30pt, tappable —
/// opens Settings) and Settings' own profile card (52pt, decorative only).
/// Pressed scale 0.9 (`Metrics.Motion.avatarPressScale`) applies only to
/// the tappable form.
struct Avatar: View {
    enum Size {
        case small // 30pt, Home header
        case large // 52pt, Settings profile card

        var diameter: CGFloat { self == .small ? 30 : 52 }
        var textStyle: OrbitTextStyle { self == .small ? .micro : .caption }
    }

    let initials: String
    var size: Size = .small
    var theme = Theme()
    /// `nil` renders a purely decorative avatar (Settings' profile card);
    /// non-`nil` renders a real, ≥44pt-tappable button (Home header).
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { glyph }
                .buttonStyle(PressableScaleButtonStyle(scale: Metrics.Motion.avatarPressScale))
                .frame(minWidth: Metrics.HitTarget.minimum, minHeight: Metrics.HitTarget.minimum)
                .accessibilityLabel("Open Settings")
        } else {
            glyph.accessibilityHidden(true)
        }
    }

    private var glyph: some View {
        Circle()
            .fill(Theme.Neutral.chipFill)
            .overlay(Circle().stroke(Theme.Neutral.cardBorder, lineWidth: 1))
            .overlay(
                Text(initials)
                    .font(.orbit(size.textStyle))
                    .foregroundStyle(Theme.Neutral.textPrimary)
            )
            .frame(width: size.diameter, height: size.diameter)
    }
}
