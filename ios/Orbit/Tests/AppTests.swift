import Testing
@testable import Orbit

/// **Authored, not compiled, on this host** — see `.pipeline/
/// implementation-progress.md`'s T11/T12/T13 entries; genuine execution
/// happens on the operator's Mac. Pure-logic slices only: `AppRouter`'s
/// Settings-overlay/tab-selection transitions, and `RootView`'s auth-state
/// switching decision (`RootDestination`) — both plain, dependency-free
/// state, matching `.pipeline/tasks.md`'s T13 test_strategy slice
/// ("pure-logic slices (AppRouter transitions, auth-state switching) as
/// Swift Testing"). The end-to-end flows these states drive (sign-in,
/// sign-out ordering, delete-account) are `Tests/UITests/` (XCUITest,
/// Mac-only, against the real API).

@Suite("App — AppRouter Settings-overlay + tab-selection transitions")
@MainActor
struct AppRouterTests {
    @Test("A fresh AppRouter starts on Home with Settings dismissed")
    func startsOnHomeWithSettingsDismissed() {
        let router = AppRouter()
        #expect(router.selectedTab == .home)
        #expect(router.isSettingsPresented == false)
    }

    @Test("presentSettings() shows the overlay; dismissSettings() hides it again")
    func presentAndDismissToggleSettingsState() {
        let router = AppRouter()

        router.presentSettings()
        #expect(router.isSettingsPresented == true)

        router.dismissSettings()
        #expect(router.isSettingsPresented == false)
    }

    @Test("dismissSettings() on an already-dismissed router is a harmless no-op")
    func dismissWhenAlreadyDismissedIsANoOp() {
        let router = AppRouter()
        router.dismissSettings()
        #expect(router.isSettingsPresented == false)
    }

    @Test("selectedTab can be switched to every one of the 4 destinations", arguments: AppRouter.Tab.allCases)
    func selectedTabSwitchesToEveryDestination(tab: AppRouter.Tab) {
        let router = AppRouter()
        router.selectedTab = tab
        #expect(router.selectedTab == tab)
    }

    @Test("RootTabView's 4 destinations are exactly home/fuel/train/body (design-spec SCREEN-1…4)")
    func allTabsAreTheFourDesignedDestinations() {
        #expect(Set(AppRouter.Tab.allCases) == [.home, .fuel, .train, .body])
    }
}

@Suite("App — RootDestination auth-state switching (pure logic)")
struct RootDestinationTests {
    @Test("Signed out resolves to the auth flow (SignInView/RegisterView)")
    func signedOutResolvesToAuthFlow() {
        #expect(RootDestination.destination(forSignedIn: false) == .authFlow)
    }

    @Test("Signed in resolves to the tab shell (RootTabView)")
    func signedInResolvesToTabs() {
        #expect(RootDestination.destination(forSignedIn: true) == .tabs)
    }
}
