import SwiftUI

/// The weight-entry sheet off Home's weight card (plan.md Open Question 4's
/// confirmed default: "sheet off the Home weight card"). The design shows
/// the weight card's DATA only — no input UI is depicted (design-spec §1
/// "Open items") — so this is an undepicted-screen build per the README's
/// "Extending the UI" conventions: a minimal, native `Form`, not a
/// full DesignSystem-styled treatment, matching the same posture T13's
/// `ReauthenticationPromptView` already established for a similarly
/// undepicted confirmation step.
struct WeightEntrySheet: View {
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var units: String { store.profile?.units ?? "imperial" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today's weigh-in") {
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("weight-entry-field")
                        Text(WeightUnitFormatting.unitLabel(units: units))
                            .foregroundStyle(Theme.Neutral.textMuted)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.orbit(.caption))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("weight-entry-error")
                    }
                }
            }
            .navigationTitle("Log weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValidInput || isSubmitting)
                        .accessibilityIdentifier("weight-entry-save")
                }
            }
        }
    }

    private var isValidInput: Bool {
        guard let value = Double(weightText) else { return false }
        return value > 0
    }

    private func save() async {
        guard let displayValue = Double(weightText) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let kilograms = WeightUnitFormatting.kilograms(fromDisplayValue: displayValue, units: units)
        do {
            try await store.logWeight(WeightEntryCreate(weightKilograms: kilograms, dayKey: store.dayKey, loggedAt: Date()))
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.userFacingMessage ?? error.localizedDescription
        }
    }
}
