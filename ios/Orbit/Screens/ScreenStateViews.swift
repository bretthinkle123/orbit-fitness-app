import SwiftUI

/// The loading chrome every data-backed screen shows before its first
/// fetch resolves (plan §Frontend: "Every data-backed view defines loading
/// / empty / error states") — built once here since all four screens need
/// the identical treatment (rule-of-two/five), rather than four
/// near-identical inline ladders.
struct LoadingStateView: View {
    var message: String = "Loading\u{2026}"

    var body: some View {
        VStack(spacing: Metrics.Spacing.cardGap) {
            ProgressView()
                .tint(Theme.Neutral.textPrimary)
            Text(message)
                .font(.orbit(.body))
                .foregroundStyle(Theme.Neutral.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Metrics.Spacing.cardGap * 2)
        .accessibilityElement(children: .combine)
    }
}

/// A clear, actionable failure state — states what happened and offers a
/// manual retry (requirements: no offline queue/auto-retry); copy matches
/// the app's own "Mission Control" register rather than a generic system
/// error dialog.
struct ErrorStateView: View {
    let error: AppError
    let onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                Text("Signal lost")
                    .font(.orbit(.cardTitle))
                    .foregroundStyle(Theme.Neutral.textPrimary)
                Text(error.userFacingMessage)
                    .font(.orbit(.body))
                    .foregroundStyle(Theme.Neutral.textMuted)
                if error.isRetryable {
                    Button("Try again") {
                        Task {
                            isRetrying = true
                            await onRetry()
                            isRetrying = false
                        }
                    }
                    .font(.orbit(.body))
                    .foregroundStyle(Theme.Neutral.textPrimary)
                    .frame(minHeight: Metrics.HitTarget.minimum)
                    .disabled(isRetrying)
                    .accessibilityIdentifier("screen-error-retry")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An empty-data prompt for a section with real data but zero entries yet
/// (e.g. Home's weight card before the user's first weigh-in) — an
/// invitation to act, not a blank space (`frontend-design`: "an empty
/// screen is an invitation to act").
struct EmptyStatePrompt: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
            Text(message)
                .font(.orbit(.body))
                .foregroundStyle(Theme.Neutral.textMuted)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.orbit(.body))
                    .foregroundStyle(Theme.Neutral.textPrimary)
                    .frame(minHeight: Metrics.HitTarget.minimum)
            }
        }
    }
}
