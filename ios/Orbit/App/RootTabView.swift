import SwiftUI

/// The signed-in root: the 4 screens (design-spec SCREEN-1…4: Home / Fuel /
/// Train / Body) behind `Components/GlassTabBar` (CMP-24, T14) — **T17
/// closes the fidelity-debt item T13/T14/T15 each flagged and left for a
/// later task**: this now wires the REAL floating glass tab bar in place of
/// the native `TabView`/`.tabItem` chrome T13 built as a placeholder before
/// the component existed (AC29's "high-fidelity replication" — CMP-24's own
/// usage list names this exact bar, not a system one).
///
/// **Decision, not another deferral**: replacing `TabView` with a manual bar
/// means SwiftUI no longer owns keeping each tab's own `@State` alive across
/// a switch — a plain `switch router.selectedTab { ... }` would DESTROY and
/// rebuild the non-selected screen's view (and its `@State`, e.g.
/// `TrainView`'s rest timer, `FuelView`'s Meals/By-hour page selection)
/// every time you switch away and back, a real regression from `TabView`'s
/// own behavior (which keeps every tab mounted, just hidden, backed by a
/// native `UITabBarController`). Resolved by keeping all 4 screens mounted
/// SIMULTANEOUSLY in one `ZStack`, toggling only `.opacity`/
/// `.allowsHitTesting`/`.accessibilityHidden` on the non-selected ones —
/// the standard workaround for a custom tab bar that needs `TabView`-
/// equivalent state preservation. This is not a NEW behavioral cost either:
/// `TabView` already ran every tab's `.task`/animations in the background
/// the same way (that's exactly why its own `@State` persisted across
/// switches in the first place) — each screen's `StarfieldView` (T17) was
/// already going to animate continuously while off-screen under either
/// implementation.
///
/// Settings' own overlay/transition mechanics (NM-8) are UNCHANGED by this
/// task — `GlassTabBar` sits at the SAME z-layer the native tab bar did
/// (beneath the Settings overlay's `zIndex(1)`), so "Settings slides over
/// everything including the tab bar" still holds exactly as before.
struct RootTabView: View {
    let store: AppStore
    let authService: AuthServiceProtocol
    let onSignedOut: () -> Void
    let onAccountDeleted: () -> Void

    @State private var router = AppRouter()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    /// Resolved through `MotionPreference` so the snapshot suites can force
    /// Reduce Motion ON: the system key is read-only in the SDK, so tests
    /// write `reduceMotionOverride` instead.
    private var reduceMotion: Bool {
        MotionPreference.resolvedReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
    }

    /// CMP-24's fixed 4-item set — icons verbatim from the native `TabView`
    /// chrome this replaces (no visual change to which glyph represents
    /// which tab).
    private static let tabItems: [GlassTabBarItem] = [
        GlassTabBarItem(id: .home, title: "Home", symbolName: "globe"),
        GlassTabBarItem(id: .fuel, title: "Fuel", symbolName: "flame"),
        GlassTabBarItem(id: .train, title: "Train", symbolName: "diamond"),
        GlassTabBarItem(id: .body, title: "Body", symbolName: "person.fill"),
    ]

    var body: some View {
        ZStack {
            ZStack {
                tabContent(for: .home) { homeTab }
                tabContent(for: .fuel) { fuelTab }
                tabContent(for: .train) { trainTab }
                tabContent(for: .body) { bodyTab }
            }
            .task { await store.loadEverything() }

            GlassTabBar(items: Self.tabItems, selection: $router.selectedTab)
                .padding(.horizontal, Metrics.Spacing.contentSidePadding)
                .padding(.bottom, Metrics.Spacing.cardGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            if router.isSettingsPresented {
                SettingsSheet(
                    store: store,
                    authService: authService,
                    onDismiss: { router.dismissSettings() },
                    onSignedOut: onSignedOut,
                    onAccountDeleted: onAccountDeleted
                )
                // Reduce Motion: swap the large slide-in for a fade
                // (`apple-hig-compliance`: "swap large transitions for
                // fades when accessibilityReduceMotion is set") — the
                // duration/curve itself (`AppRouter.settingsTransitionAnimation`)
                // is unaffected, only the WAY it enters/exits changes.
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                .zIndex(1)
            }
        }
    }

    /// Keeps `content()` PERMANENTLY mounted (never `if`-removed) so its own
    /// `@State` survives switching away and back — only visibility/hit-
    /// testing/accessibility toggle with the active tab, per this file's own
    /// doc comment above.
    @ViewBuilder
    private func tabContent<Content: View>(for tab: AppRouter.Tab, @ViewBuilder content: () -> Content) -> some View {
        let isActive = router.selectedTab == tab
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }

    private var homeTab: some View {
        HomeView(
            store: store,
            authService: authService,
            onOpenSettings: { router.presentSettings() },
            onStartPushDay: { router.selectedTab = .train }
        )
    }

    private var fuelTab: some View {
        FuelView(store: store)
    }

    private var trainTab: some View {
        TrainView(store: store)
    }

    private var bodyTab: some View {
        BodyView(store: store)
    }
}
