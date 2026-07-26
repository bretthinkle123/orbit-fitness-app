import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared "undepicted screen" primitives (SignInView + RegisterView)
//
// SignInView/RegisterView are the design README's "Extending the UI" case:
// undepicted screens built minimally from already-established DesignSystem
// tokens (`Theme`/`Metrics`/`Font+Theme`), not a new visual language. The
// three small types below are the rule-of-two extraction point (both
// screens need the same backdrop/field/button shapes) — kept file-local
// rather than a third file, since `.pipeline/tasks.md`'s T13 file list names
// only `SignInView.swift`/`RegisterView.swift`.

/// The shared ZStack recipe the design README prescribes for any new screen:
/// a full-bleed dark background behind scrolling content. **T17 closes this
/// file's own T13-documented deferral**: the two placeholder radial-wash
/// blurs (an approximation invented before `Space/StarfieldView` existed)
/// are replaced with the REAL animated starfield, one deterministic seed
/// per screen (`StarfieldSeed.signIn`/`.register`) — exactly what this
/// docstring already promised, no other change to `SignInView`/
/// `RegisterView` themselves needed.
struct AuthScreenBackdrop<Content: View>: View {
    var theme = Theme()
    let starfieldSeed: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Theme.Neutral.screenBackground
            StarfieldView(seed: starfieldSeed, theme: theme)
            ScrollView {
                content()
                    .padding(.top, Metrics.Spacing.contentTopPadding)
                    .padding(.horizontal, Metrics.Spacing.contentSidePadding)
                    .padding(.bottom, Metrics.Spacing.contentBottomPadding)
            }
        }
        .ignoresSafeArea()
    }
}

/// A minimally-styled text-input row shared by the pre-auth screens —
/// guarantees the ≥44pt tappable height (`apple-hig-compliance`) even though
/// these undepicted screens have no reference design for input styling.
struct OrbitTextFieldRow: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var accessibilityIdentifier: String

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
        }
        .textContentType(contentType)
        .keyboardType(keyboardType)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.orbit(.body))
        .foregroundStyle(Theme.Neutral.textPrimary)
        .padding(.horizontal, Metrics.Spacing.cardPaddingMin)
        .frame(minHeight: Metrics.HitTarget.minimum)
        .background(Theme.Neutral.chipFill)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular)
                .stroke(Theme.Neutral.cardBorder, lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Minimal gradient-pill button styling built only from already-existing
/// DesignSystem tokens — a placeholder for `Components/GradientPillButton`
/// (T14), not a new component-library entry (this task's scope is `App/` +
/// `Screens/`, not `Components/`).
struct OrbitPrimaryButtonStyle: ButtonStyle {
    let theme: Theme
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

// MARK: - SignInView

/// Email/password sign-in — the default `RootView` shows when signed out.
/// Minimal per the design README "Extending the UI" (plan.md Open Question
/// 3): no onboarding carousel, no social login (email/password only, per
/// plan.md's auth-provider scope).
struct SignInView: View {
    let authService: AuthServiceProtocol
    /// Called after EITHER a successful sign-in here OR a successful
    /// register in the presented `RegisterView` — `RootView` treats both as
    /// the same "now authenticated" transition.
    let onAuthenticated: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isShowingRegister = false

    private var theme: Theme { Theme() } // no profile/palette exists yet pre-auth

    var body: some View {
        AuthScreenBackdrop(theme: theme, starfieldSeed: StarfieldSeed.signIn) {
            VStack(spacing: Metrics.Spacing.cardGap) {
                Text("ORBIT")
                    .font(.orbit(.wordmark))
                    .tracking(OrbitTextStyle.wordmark.trackingEm * OrbitTextStyle.wordmark.size)
                    .foregroundStyle(theme.primaryLight)

                Text("Welcome back")
                    .font(.orbit(.screenTitle))
                    .foregroundStyle(Theme.Neutral.textPrimary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.orbit(.caption))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("signin-error")
                }

                OrbitTextFieldRow(
                    title: "Email", text: $email, contentType: .username,
                    keyboardType: .emailAddress, accessibilityIdentifier: "signin-email"
                )
                OrbitTextFieldRow(
                    title: "Password", text: $password, isSecure: true,
                    contentType: .password, accessibilityIdentifier: "signin-password"
                )

                Button("Sign In") { Task { await signIn() } }
                    .buttonStyle(OrbitPrimaryButtonStyle(theme: theme, isDisabled: !isValid || isSubmitting))
                    .disabled(!isValid || isSubmitting)
                    .accessibilityIdentifier("signin-submit")

                Button("Need an account? Register") { isShowingRegister = true }
                    .font(.orbit(.body))
                    .foregroundStyle(theme.secondaryLight)
                    .frame(minHeight: Metrics.HitTarget.minimum)
                    .accessibilityIdentifier("signin-go-to-register")
            }
        }
        .fullScreenCover(isPresented: $isShowingRegister) {
            RegisterView(authService: authService, onRegistered: onAuthenticated)
        }
    }

    private var isValid: Bool { !email.isEmpty && !password.isEmpty }

    private func signIn() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await authService.signIn(email: email, password: password)
            onAuthenticated()
        } catch {
            // Firebase's own `AuthErrorCode` NSErrors reach here (not our
            // `AppError` — that's the backend's error shape, not the
            // identity provider's); `localizedDescription` is Firebase's own
            // user-presentable message for these.
            errorMessage = error.localizedDescription
        }
    }
}
