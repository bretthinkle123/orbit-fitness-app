import SwiftUI
import FirebaseCore
import FirebaseAuth

/// The app's composition root (plan.md §Frontend: "`OrbitApp` (@main
/// composition root)"). Builds every long-lived collaborator exactly once
/// and wires the one genuine mutual dependency `Core/AuthService.swift`
/// documents (T12's flagged deferral, closed here): `LiveAPIClient` needs
/// `AuthService` to attach a bearer token to every request;
/// `FirebaseAuthService` needs the API client to invalidate the server
/// session on sign-out (AC34). Both objects exist by the time this
/// initializer returns, so `authService.remoteSession` is set before either
/// is ever used for a real call — `FirebaseAuthService.signOut()`'s
/// `preconditionFailure` guard exists specifically to catch a REGRESSION of
/// this wiring, not to document that it might be skipped.
@main
struct OrbitApp: App {
    private let authService: FirebaseAuthService
    private let apiClient: LiveAPIClient

    init() {
        FirebaseApp.configure()
        Self.configureFirebaseAuthEmulatorIfConfigured()

        let tokenStore = KeychainTokenStore()
        let authService = FirebaseAuthService(tokenStore: tokenStore)
        let apiClient = LiveAPIClient(baseURL: Self.resolveAPIBaseURL(), tokenProvider: authService)
        authService.remoteSession = apiClient // closes T12's documented deferral — see doc comment above

        self.authService = authService
        self.apiClient = apiClient
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService, apiClient: apiClient)
        }
    }

    /// The backend base URL — read from `Info.plist`'s `OrbitAPIBaseURL`
    /// (see `Resources/Info.plist`), never a literal in source. Keeping the
    /// endpoint a build-configuration value (rather than hardcoded here)
    /// means a differently-configured build (a staging HTTPS endpoint, once
    /// plan.md Open Question 1's infra depth lands) can point elsewhere
    /// with no code change, mirroring the backend's own config-facade
    /// discipline (`config/settings.py`: never call the raw source inline).
    /// `OrbitAPIBaseURL` is always present in the committed `Info.plist`, so
    /// its absence here is a genuine build-configuration bug, not a
    /// reachable runtime state — hence the loud failure rather than a
    /// silent fallback. Checked FIRST against `ProcessInfo`'s environment —
    /// the standard XCUITest pattern (`XCUIApplication.launchEnvironment`)
    /// for pointing a UI-test launch at a specific, ephemeral test backend
    /// without a rebuild; see `Tests/UITests/*.swift`'s own header comments.
    private static func resolveAPIBaseURL() -> URL {
        if let overridden = ProcessInfo.processInfo.environment["OrbitAPIBaseURL"], let url = URL(string: overridden) {
            return url
        }
        guard
            let configuredValue = Bundle.main.object(forInfoDictionaryKey: "OrbitAPIBaseURL") as? String,
            let url = URL(string: configuredValue)
        else {
            preconditionFailure("OrbitAPIBaseURL must be set in Info.plist to a valid URL")
        }
        return url
    }

    /// Debug-only, opt-in Firebase Auth emulator wiring — mirrors the
    /// backend's own `FIREBASE_AUTH_EMULATOR_HOST` detection
    /// (`src/orbit/auth/firebase.py`), so the Mac-phase operator's local/
    /// XCUITest runs against the real emulator-backed API (AC27) need only
    /// set `OrbitFirebaseAuthEmulatorHost` in a local, uncommitted scheme
    /// environment/xcconfig override — never a value baked into the
    /// committed `Info.plist`, and compiled out of Release builds entirely.
    private static func configureFirebaseAuthEmulatorIfConfigured() {
        #if DEBUG
        let fromEnvironment = ProcessInfo.processInfo.environment["OrbitFirebaseAuthEmulatorHost"]
        let fromInfoPlist = Bundle.main.object(forInfoDictionaryKey: "OrbitFirebaseAuthEmulatorHost") as? String
        guard let emulatorHost = fromEnvironment ?? fromInfoPlist, !emulatorHost.isEmpty else { return }
        Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
        #endif
    }
}
