import SwiftUI

/// The single source of truth for the app's post-sign-in navigation state:
/// which of the 4 tab destinations is active, and whether Settings is
/// presented. NM-8 (design-spec §6 / plan.md §Frontend): Settings slides in
/// as a **trailing overlay transition** over everything — including the tab
/// bar — rather than a modal `.sheet`, so the 3D hero underneath keeps
/// animating while Settings is up. This type owns only the STATE + the
/// design's timing curve; the actual `.transition` style (and whether it
/// respects Reduce Motion) is a `View` concern, applied by `RootTabView`,
/// since Reduce Motion is read from the SwiftUI environment, not available
/// to a plain `@Observable` model.
@MainActor
@Observable
final class AppRouter {
    /// The 4 `RootTabView` destinations (design-spec SCREEN-1…4).
    enum Tab: Hashable, CaseIterable, Sendable {
        case home
        case fuel
        case train
        case body
    }

    var selectedTab: Tab = .home
    private(set) var isSettingsPresented = false

    /// design-spec §5: "Settings sheet: slides `translateX(102%→0)` ... .5s
    /// cubic-bezier(.22,1,.36,1)" — the same curve/duration `Metrics.Motion`
    /// already records for bars/rings elsewhere in the app (one motion
    /// vocabulary, not a second hand-picked curve for this transition).
    static let settingsTransitionAnimation = Animation.timingCurve(
        Metrics.Motion.barRingCurve.x1,
        Metrics.Motion.barRingCurve.y1,
        Metrics.Motion.barRingCurve.x2,
        Metrics.Motion.barRingCurve.y2,
        duration: Metrics.Motion.sheetSlideDuration
    )

    /// Presents the Settings overlay (tap avatar, SCREEN-1 Home per
    /// design-spec §4's navigation graph).
    func presentSettings() {
        withAnimation(Self.settingsTransitionAnimation) {
            isSettingsPresented = true
        }
    }

    /// Dismisses the Settings overlay (tap the back chevron, or a completed
    /// sign-out/delete-account action).
    func dismissSettings() {
        withAnimation(Self.settingsTransitionAnimation) {
            isSettingsPresented = false
        }
    }
}
