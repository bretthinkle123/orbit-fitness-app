import SwiftUI

/// Which root content the app shows for a given sign-in state — a tiny,
/// directly-testable seam (Swift Testing, `Tests/AppTests.swift`) so
/// `RootView`'s branch is a pure-function decision, not logic buried in a
/// `View.body` (`swift-conventions`: "keep business/domain logic out of
/// views").
enum RootDestination: Equatable, Sendable {
    case authFlow
    case tabs

    static func destination(forSignedIn isSignedIn: Bool) -> RootDestination {
        isSignedIn ? .tabs : .authFlow
    }
}

/// The app's root: switches on authentication state between the sign-in/
/// register flow and the signed-in tab shell (plan.md §Frontend: "`RootView`
/// (switches on auth state)"). `isSignedIn` is plain `@State` flipped by the
/// explicit callbacks every auth-changing action already goes through
/// (register/sign-in success; sign-out/delete-account success) — the
/// idiomatic SwiftUI MV shape for a transition this app's OWN actions always
/// drive (no external/other-device session change can happen out-of-band
/// here, so no Firebase auth-state listener is needed beyond these
/// callbacks).
struct RootView: View {
    let authService: AuthServiceProtocol
    let apiClient: APIClientProtocol

    @State private var isSignedIn: Bool

    init(authService: AuthServiceProtocol, apiClient: APIClientProtocol) {
        self.authService = authService
        self.apiClient = apiClient
        _isSignedIn = State(initialValue: authService.isSignedIn)
    }

    var body: some View {
        switch RootDestination.destination(forSignedIn: isSignedIn) {
        case .tabs:
            RootTabView(
                store: AppStore(apiClient: apiClient),
                authService: authService,
                onSignedOut: { isSignedIn = false },
                onAccountDeleted: { isSignedIn = false }
            )
        case .authFlow:
            AuthFlowView(authService: authService, onAuthenticated: { isSignedIn = true })
        }
    }
}

/// Toggles between `SignInView` and `RegisterView` — the undepicted
/// onboarding pair plan.md §Frontend names (README "Extending the UI": the
/// shared ZStack recipe, minimal, new starfield seed). `RegisterView` is
/// presented as a full-screen cover (there's no navigation stack pre-auth to
/// push onto).
private struct AuthFlowView: View {
    let authService: AuthServiceProtocol
    let onAuthenticated: () -> Void

    var body: some View {
        SignInView(authService: authService, onAuthenticated: onAuthenticated)
    }
}
