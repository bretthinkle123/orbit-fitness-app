import SwiftUI

/// CMP-25 — Settings' 3 row kinds: a tappable chevron row (editors
/// undepicted per design-spec §1's open items), a toggle row (native
/// `Toggle` — its built-in knob-slide animation already IS the design's
/// "toggle knob slides `translateX(17px)`" affordance, a correct native
/// mapping rather than a custom re-implementation), and a destructive/
/// plain action row (Sign out / Delete Account).
///
/// Note: `Screens/SettingsSheet.swift` (T13) currently builds its own rows
/// ad hoc (native `Picker`s, plain `Button`s), authored before this
/// component existed. Left as-is rather than editing an already-verified
/// T13 file out of this task's scope — consolidating onto this component
/// is flagged as T15 cleanup.
struct SettingsRow: View {
    enum Kind {
        case chevron(action: () -> Void)
        case toggle(isOn: Binding<Bool>)
        case action(isDestructive: Bool = false, action: () -> Void)
    }

    let title: String
    let kind: Kind
    var theme = Theme()

    var body: some View {
        switch kind {
        case .chevron(let action):
            Button(action: action) {
                HStack {
                    rowTitle(color: Theme.Neutral.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.Neutral.textMuted)
                }
                .frame(minHeight: Metrics.HitTarget.minimum)
            }
        case .toggle(let isOn):
            Toggle(isOn: isOn) { rowTitle(color: Theme.Neutral.textPrimary) }
                .tint(theme.secondary)
                .frame(minHeight: Metrics.HitTarget.minimum)
        case .action(let isDestructive, let action):
            Button(action: action) {
                rowTitle(color: isDestructive ? .red : Theme.Neutral.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Metrics.HitTarget.minimum, alignment: .leading)
            }
        }
    }

    private func rowTitle(color: Color) -> some View {
        Text(title)
            .font(.orbit(.body))
            .foregroundStyle(color)
    }
}
