import SwiftUI

/// The daily-kcal-budget editor off Settings' Mission section (design-spec
/// §2 CMP-25: "chevron row... editors undepicted" — plan.md Open Question 4's
/// confirmed default: "numeric stepper sheets off the Settings rows").
/// Bounds mirror `schemas.profile.ProfileUpdate.kcal_budget`'s own
/// `ge=500, le=10000` exactly (read directly this session) — a client-side
/// mirror, never a replacement for the server's own validation, which still
/// runs regardless.
struct BudgetEditorSheet: View {
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var kcalBudget: Int
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let bounds = 500...10000
    private static let step = 50

    init(store: AppStore) {
        self.store = store
        _kcalBudget = State(initialValue: store.profile?.kcalBudget ?? 2000)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily kcal budget") {
                    Stepper(value: $kcalBudget, in: Self.bounds, step: Self.step) {
                        Text("\(NumberDisplay.formatted(kcalBudget)) kcal")
                    }
                    .accessibilityIdentifier("budget-editor-stepper")
                    if let errorMessage {
                        Text(errorMessage).font(.orbit(.caption)).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Daily budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("budget-editor-save")
                }
            }
        }
    }

    private func save() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.updateProfile(ProfileUpdate(kcalBudget: kcalBudget))
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.userFacingMessage ?? error.localizedDescription
        }
    }
}
