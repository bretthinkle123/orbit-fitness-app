import SwiftUI

/// One `GlassTabBar` destination — icon + label for one of the app's fixed
/// 4 tabs.
struct GlassTabBarItem: Identifiable {
    let id: AppRouter.Tab
    let title: String
    let symbolName: String
}

/// CMP-24 — the floating glass tab bar (4 items: Home/Fuel/Train/Body).
/// Active = white 9% pill (`Theme.Neutral.tabBarActivePill`) + the design's
/// named active icon/label tint (`Theme.Neutral.tabBarActiveText`) — both
/// already-declared Theme tokens (T11), reused here rather than re-derived
/// or spelled out as a literal (`scripts/check_no_inline_hex.sh` greps raw
/// source text for a hex literal regardless of comment context, so naming
/// the design's actual hex value in prose here would itself be flagged —
/// same self-inflicted-false-positive class as T13's store-compliance
/// incident, avoided here by referencing the TOKEN name only). Bound directly
/// to `AppRouter.Tab` (this app has exactly one fixed 4-tab set, per
/// design-spec CMP-24 — a generic `Hashable`-typed tab bar would be
/// speculative abstraction for a case that doesn't exist, unlike
/// `SegmentedToggle`, CMP-9, which genuinely has 3 distinct call sites with
/// 3 distinct option types).
///
/// `App/RootTabView.swift` wires this in (T17 — closing the fidelity-debt
/// item T13/T14/T15 each flagged and left open) in place of the native
/// `TabView`/`.tabItem` chrome T13 built as a placeholder before this
/// component existed.
struct GlassTabBar: View {
    let items: [GlassTabBarItem]
    @Binding var selection: AppRouter.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(for: item)
            }
        }
        .padding(.horizontal, Metrics.Spacing.cardGap)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Metrics.Radius.tabBar, style: .circular).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: Metrics.Radius.tabBar, style: .circular).fill(Theme.Neutral.tabBarFill))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.tabBar, style: .circular))
    }

    private func tabButton(for item: GlassTabBarItem) -> some View {
        let isActive = item.id == selection
        return Button {
            selection = item.id
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.symbolName)
                Text(item.title).font(.orbit(.micro))
            }
            .foregroundStyle(isActive ? Theme.Neutral.tabBarActiveText : Theme.Neutral.textMuted)
            .frame(maxWidth: .infinity, minHeight: Metrics.HitTarget.minimum)
            .background(isActive ? Theme.Neutral.tabBarActivePill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular))
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        // T17: a real, stable identifier per tab (native `TabView`'s own
        // `app.tabBars.buttons[...]` query no longer resolves anything once
        // this custom bar replaces it — `Tests/SmokeUITests.swift`/
        // `AccessibilityTests.swift`, T16, are updated to query these
        // instead, per this task's own "preserve existing accessibility
        // identifiers" instruction).
        .accessibilityIdentifier("tab-\(item.title.lowercased())")
    }
}
