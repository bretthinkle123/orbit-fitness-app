import FirebaseAuth
import Foundation

/// The narrow "invalidate my session on the server" capability `AuthService`
/// needs from the API layer (AC34: sign-out must revoke the token
/// server-side, not merely discard it client-side). `APIClientProtocol`
/// conforms to this via its `signOut()` method — `AuthService` depends on
/// this slice only (interface segregation), never the full API surface.
protocol RemoteSessionInvalidating: Sendable {
    func signOut() async throws
}

extension LiveAPIClient: RemoteSessionInvalidating {}

/// The identity/session facade every screen and `APIClient` (via
/// `BearerTokenProviding`) depends on — the ONE place that imports
/// `FirebaseAuth` directly.
///
/// `@MainActor` for the same reason as `BearerTokenProviding` (see its note):
/// the conformers are main-actor-confined, and every consumer here is already
/// on the main actor anyway — each is a SwiftUI view holding
/// `let authService: AuthServiceProtocol`.
@MainActor
protocol AuthServiceProtocol: BearerTokenProviding {
    /// Creates a new Firebase account and signs in as it in one step
    /// (register → immediately authenticated, per plan §Frontend's
    /// `SignInView`/`RegisterView` default). `displayName` is written to the
    /// Firebase user profile ONLY (`updateProfile` on the Firebase `User`) —
    /// per plan.md Open Question 3 / T13's explicit scope, it is NEVER sent
    /// to the backend (CLAUDE.md: "no local PII beyond the UID"; the backend
    /// has no display-name field anywhere in its schema).
    func register(email: String, password: String, displayName: String) async throws
    func signIn(email: String, password: String) async throws
    /// AC34: calls the server's `POST /me/signout` (revokes every
    /// outstanding refresh token, `check_revoked=True`) BEFORE clearing the
    /// locally cached token and signing out of the Firebase SDK — in that
    /// order, so a crash mid-sequence never leaves a revoked-server-side but
    /// still-locally-cached token.
    func signOut() async throws
    /// Re-authenticates the current user with their password to obtain a
    /// FRESH ID token (`auth_time` reset to now) — the client-side half of
    /// the backend's `require_fresh_reauth` guard (ASVS 7.5.1) that gates
    /// `DELETE /me`. Call this, then retry the delete, when a delete attempt
    /// comes back `.unauthorized` (see `AppStore.deleteAccount`).
    func reauthenticate(email: String, password: String) async throws
    var isSignedIn: Bool { get }
    /// The signed-in Firebase user's own display name / email — client-side
    /// ONLY (never sent to or read from the backend, which has no such
    /// columns; CLAUDE.md "no local PII beyond the UID"). `Screens/
    /// HomeView.swift`'s avatar monogram and `Screens/SettingsSheet.swift`'s
    /// profile card (T15) read these; `nil` when genuinely absent (an
    /// optional display name at register, T13).
    var currentUserDisplayName: String? { get }
    var currentUserEmail: String? { get }
}

/// Wraps the Firebase iOS SDK's `Auth` singleton behind `AuthServiceProtocol`.
/// `@MainActor`-confined rather than `Sendable`-audited: the Firebase SDK's
/// `Auth`/`User` types predate Swift 6 strict-concurrency auditing, so
/// confining every call to one actor is the correct, honest way to satisfy
/// data-race safety here (`swift-conventions`: "`@MainActor` correctness over
/// `@unchecked Sendable` shortcuts") rather than papering over an unaudited
/// type with `@unchecked Sendable`.
@MainActor
final class FirebaseAuthService: AuthServiceProtocol, Sendable {
    private let tokenStore: TokenStoring
    /// The remote session-invalidation call `signOut()` makes. Not a
    /// constructor parameter: `APIClient` itself depends on THIS type (via
    /// `BearerTokenProviding`) to attach bearer tokens, so the two objects
    /// have a genuine mutual dependency that can only be resolved by one
    /// side accepting its collaborator after both are constructed. The
    /// composition root (`App/OrbitApp.swift`, T13) constructs this service
    /// first, then `LiveAPIClient(tokenProvider: authService)`, then sets
    /// this property to the same `apiClient` instance before either is used
    /// for a real sign-out. `signOut()` documents the precondition.
    var remoteSession: RemoteSessionInvalidating?

    init(tokenStore: TokenStoring = KeychainTokenStore()) {
        self.tokenStore = tokenStore
    }

    var isSignedIn: Bool {
        Auth.auth().currentUser != nil
    }

    var currentUserDisplayName: String? {
        Auth.auth().currentUser?.displayName
    }

    var currentUserEmail: String? {
        Auth.auth().currentUser?.email
    }

    func register(email: String, password: String, displayName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        // Client-side-only profile write (see the protocol doc comment) — a
        // trimmed empty name is skipped rather than committing a blank
        // display name, since `RegisterView` treats the field as optional.
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = trimmedDisplayName
            try await changeRequest.commitChanges()
        }
        try await cacheFreshToken(for: result.user)
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        try await cacheFreshToken(for: result.user)
    }

    func signOut() async throws {
        // AC34's exact ordering: server-side revocation FIRST. `remoteSession`
        // must be wired by the composition root before this is ever called;
        // a nil value here is a startup-wiring bug, not a recoverable runtime
        // state, so it fails loudly rather than silently skipping revocation.
        guard let remoteSession else {
            preconditionFailure("AuthService.remoteSession must be wired before signOut() is called")
        }
        try await remoteSession.signOut()
        try tokenStore.clear()
        try Auth.auth().signOut()
    }

    func reauthenticate(email: String, password: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AppError.unauthorized(message: "No signed-in user to re-authenticate")
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await user.reauthenticate(with: credential)
        // Force a refresh (not just re-auth) so the cached token's `auth_time`
        // claim is genuinely current — `require_fresh_reauth` checks that
        // claim, not merely whether re-authentication succeeded.
        try await cacheFreshToken(for: result.user, forcingRefresh: true)
    }

    func currentIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AppError.unauthorized(message: "No signed-in user")
        }
        // `forcingRefresh: false` — the SDK itself only performs a network
        // refresh when the cached token is actually near expiry; this is the
        // documented, efficient way to "always get a currently-valid token"
        // without forcing a network round trip on every single API call.
        let token = try await user.getIDToken(forcingRefresh: false)
        try tokenStore.save(token: token)
        return token
    }

    /// Fetches and caches a fresh token right after register/sign-in/
    /// reauthenticate, so `KeychainTokenStore` never briefly holds a stale
    /// value from a previous session.
    /// `sending` because Firebase's `User` is not `Sendable`: awaiting
    /// `getIDToken` hands the instance to the SDK's own executor, so the
    /// compiler must know the caller keeps no reference it could race against.
    /// Every caller passes a `result.user` it does not touch afterward.
    private func cacheFreshToken(for user: sending User, forcingRefresh: Bool = false) async throws {
        let token = try await user.getIDToken(forcingRefresh: forcingRefresh)
        try tokenStore.save(token: token)
    }
}
