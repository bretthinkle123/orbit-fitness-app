import SwiftUI

/// The macro-target-grams editor off Settings' Mission section (same
/// confirmed-default shape as `BudgetEditorSheet` — numeric steppers, not a
/// depicted editor). Bounds mirror `schemas.profile.ProfileUpdate`'s
/// `protein_target_g`/`carb_target_g`/`fat_target_g` (`ge=0, le=1000` each,
/// read directly this session). Shows the LIVE derived split percentage
/// (`OrbitMacroMath.computeSplitPercentages`, T11) as the user adjusts grams
/// — AC8's "derived, never the design's stale copy" guarantee holds here
/// too, not just on the read-only Settings row.
struct MacroEditorSheet: View {
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var proteinGrams: Int
    @State private var carbGrams: Int
    @State private var fatGrams: Int
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let bounds = 0...1000
    private static let step = 5

    init(store: AppStore) {
        self.store = store
        _proteinGrams = State(initialValue: store.profile?.proteinTargetGrams ?? 0)
        _carbGrams = State(initialValue: store.profile?.carbTargetGrams ?? 0)
        _fatGrams = State(initialValue: store.profile?.fatTargetGrams ?? 0)
    }

    private var derivedSplit: (protein: Int, carb: Int, fat: Int) {
        OrbitMacroMath.computeSplitPercentages(
            kcalBudget: store.profile?.kcalBudget ?? 0,
            proteinGrams: proteinGrams, carbGrams: carbGrams, fatGrams: fatGrams
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Macro targets") {
                    macroStepper(label: "Protein", value: $proteinGrams, percent: derivedSplit.protein)
                    macroStepper(label: "Carbs", value: $carbGrams, percent: derivedSplit.carb)
                    macroStepper(label: "Fat", value: $fatGrams, percent: derivedSplit.fat)
                    if let errorMessage {
                        Text(errorMessage).font(.orbit(.caption)).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Macro split")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("macro-editor-save")
                }
            }
        }
    }

    private func macroStepper(label: String, value: Binding<Int>, percent: Int) -> some View {
        Stepper(value: value, in: Self.bounds, step: Self.step) {
            Text("\(label): \(value.wrappedValue) g \u{00b7} \(percent)%")
        }
        .accessibilityIdentifier("macro-editor-\(label.lowercased())-stepper")
    }

    private func save() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.updateProfile(
                ProfileUpdate(proteinTargetGrams: proteinGrams, carbTargetGrams: carbGrams, fatTargetGrams: fatGrams)
            )
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.userFacingMessage ?? error.localizedDescription
        }
    }
}
