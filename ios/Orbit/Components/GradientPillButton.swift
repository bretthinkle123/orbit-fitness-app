import SwiftUI

/// CMP-7 — the primary CTA pill (Home's "Start Push Day"): 46pt tall, r23,
/// 135° primary→secondary gradient + glow. NM-4: the design's `:hover`
/// (brightness 1.12) has no touch equivalent and is dropped; `:active`
/// (scale .98) maps to `.scaleEffect` on press via the shared
/// `PressableScaleButtonStyle`.
///
/// Note: `Screens/SignInView.swift` (T13) already has an equivalent
/// file-local `OrbitPrimaryButtonStyle`, authored before this component
/// existed. Left as-is rather than editing an already-verified T13 file
/// out of this task's scope — consolidating both auth screens onto this
/// real component is flagged as T15 cleanup (same posture T13's own
/// progress note already recorded).
struct GradientPillButtonStyle: ButtonStyle {
    var theme = Theme()
    var isDisabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.orbit(.cardTitle))
            .foregroundStyle(Theme.Neutral.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Metrics.Radius.pillButtonHeight)
            .background(
                LinearGradient(colors: [theme.primary, theme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(isDisabled ? 0.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.pillButton, style: .circular))
            .shadow(color: theme.ctaGlow, radius: Metrics.Shadow.ctaBlurRadius, y: Metrics.Shadow.ctaOffsetY)
            .scaleEffect(configuration.isPressed ? Metrics.Motion.ctaPressScale : 1)
            .animation(.easeOut(duration: Metrics.Motion.fillDuration), value: configuration.isPressed)
    }
}

/// A ready-to-use `Text`-label button built on the style above, for the
/// common case (Home's "Start Push Day").
struct GradientPillButton: View {
    let title: String
    var theme = Theme()
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(GradientPillButtonStyle(theme: theme, isDisabled: isDisabled))
        .disabled(isDisabled)
    }
}
