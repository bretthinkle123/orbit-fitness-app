import SwiftUI

/// CMP-9 — ONE component, three uses (M/W on Body, Meals/By-hour on Fuel,
/// Metric/Imperial on Settings): design-spec §2 "selected / unselected (bg
/// .14 vs transparent)". Generic over any `Hashable` option type so each
/// screen supplies its own value type + label without a per-screen
/// re-implementation.
///
/// Note: `Screens/SettingsSheet.swift` (T13) currently uses a native
/// `Picker(.segmented)` for Units/Figure, authored before this component
/// existed. Left as-is rather than editing an already-verified T13 file
/// out of this task's scope — swapping it for this component is flagged as
/// T15 cleanup.
struct SegmentedToggle<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.segmentedMax, style: .circular)
                .fill(Theme.Neutral.chipFill)
        )
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            withAnimation(.easeOut(duration: Metrics.Motion.fillDuration)) { selection = option }
        } label: {
            Text(label(option))
                .font(.orbit(.body))
                .foregroundStyle(isSelected ? Theme.Neutral.textPrimary : Theme.Neutral.textMuted)
                .frame(maxWidth: .infinity, minHeight: Metrics.HitTarget.minimum)
                .background(isSelected ? Theme.Neutral.segmentedSelectedFill : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.segmentedMax, style: .circular))
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
