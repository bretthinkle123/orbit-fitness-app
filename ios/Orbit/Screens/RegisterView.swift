import SwiftUI

/// Account creation — email/password + an optional display name (plan.md
/// Open Question 3: "display name captured at register → Firebase
/// profile"). Presented modally from `SignInView`; minimal per the design
/// README "Extending the UI", sharing `AuthScreenBackdrop`/
/// `OrbitTextFieldRow`/`OrbitPrimaryButtonStyle` from `SignInView.swift`.
struct RegisterView: View {
    let authService: AuthServiceProtocol
    /// Called after a successful registration — the SAME "now authenticated"
    /// transition `SignInView.onAuthenticated` triggers.
    let onRegistered: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// Firebase Auth's own minimum password length — checked client-side
    /// only as an early, friendlier error than round-tripping to Firebase
    /// first; Firebase itself still enforces this regardless.
    private static let minimumPasswordLength = 6

    private var theme: Theme { Theme() } // no profile/palette exists yet pre-auth

    var body: some View {
        AuthScreenBackdrop(theme: theme, starfieldSeed: StarfieldSeed.register) {
            VStack(spacing: Metrics.Spacing.cardGap) {
                Text("ORBIT")
                    .font(.orbit(.wordmark))
                    .tracking(OrbitTextStyle.wordmark.trackingEm * OrbitTextStyle.wordmark.size)
                    .foregroundStyle(theme.primaryLight)

                Text("Create your account")
                    .font(.orbit(.screenTitle))
                    .foregroundStyle(Theme.Neutral.textPrimary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.orbit(.caption))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("register-error")
                }

                OrbitTextFieldRow(
                    title: "Display name (optional)", text: $displayName, contentType: .name,
                    accessibilityIdentifier: "register-display-name"
                )
                OrbitTextFieldRow(
                    title: "Email", text: $email, contentType: .username,
                    keyboardType: .emailAddress, accessibilityIdentifier: "register-email"
                )
                OrbitTextFieldRow(
                    title: "Password (6+ characters)", text: $password, isSecure: true,
                    contentType: .newPassword, accessibilityIdentifier: "register-password"
                )

                Button("Create Account") { Task { await register() } }
                    .buttonStyle(OrbitPrimaryButtonStyle(theme: theme, isDisabled: !isValid || isSubmitting))
                    .disabled(!isValid || isSubmitting)
                    .accessibilityIdentifier("register-submit")

                Button("Already have an account? Sign in") { dismiss() }
                    .font(.orbit(.body))
                    .foregroundStyle(theme.secondaryLight)
                    .frame(minHeight: Metrics.HitTarget.minimum)
                    .accessibilityIdentifier("register-go-to-signin")
            }
        }
    }

    private var isValid: Bool {
        !email.isEmpty && password.count >= Self.minimumPasswordLength
    }

    private func register() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await authService.register(email: email, password: password, displayName: displayName)
            onRegistered()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
