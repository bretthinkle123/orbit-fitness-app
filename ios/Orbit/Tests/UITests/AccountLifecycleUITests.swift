import XCTest

/// XCUITest skeleton (T13) — **MAC EXECUTION ONLY**, same real-backend +
/// Firebase-emulator requirement as `AuthFlowUITests` (see its header
/// comment for the exact launch-environment override). Exercises AC34
/// (sign-out) and AC5 (delete-account) end-to-end through the UI.
///
/// The STRICT internal ordering AC34 also requires (`POST /me/signout`
/// called before the Keychain token is cleared, before the Firebase SDK's
/// own `signOut()`) is unit-proven at the `Core` layer
/// (`Tests/CoreTests.swift` — `AuthService.signOut()` is a single, small,
/// sequential function that cannot silently reorder without a code change).
/// This UI test proves the user-VISIBLE outcome of that ordering instead:
/// after signing out, the app is genuinely back at the sign-in screen (not
/// a stuck or half-signed-out state) and a fresh sign-in with the SAME
/// account works immediately afterward.
final class AccountLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Sign out from Settings returns to the sign-in screen, and signing
    /// back in with the same seeded account immediately afterward succeeds
    /// — the SESSION ended, the ACCOUNT did not.
    func testSignOutReturnsToSignInAndAFreshSignInWorksAfterward() throws {
        let app = AuthFlowUITests.launchApp()
        AuthFlowUITests.signIn(app, email: AuthFlowUITests.seededTestEmail, password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        app.buttons["home-avatar-settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-sign-out"].waitForExistence(timeout: 5))
        app.buttons["settings-sign-out"].tap()

        XCTAssertTrue(app.textFields["signin-email"].waitForExistence(timeout: 10))

        AuthFlowUITests.signIn(app, email: AuthFlowUITests.seededTestEmail, password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))
    }

    /// Delete Account (immediately after registering, so the session's
    /// `auth_time` is fresh and the backend's `require_fresh_reauth` guard —
    /// ASVS 7.5.1 — is satisfied on the FIRST attempt, with no reauth prompt
    /// needed) erases the account and returns to the sign-in screen; the
    /// same credentials no longer sign in afterward — AC5's cascade actually
    /// ran, not merely a client-side "forget me."
    func testDeleteAccountErasesTheAccountAndReturnsToSignIn() throws {
        let app = AuthFlowUITests.launchApp()
        let email = AuthFlowUITests.uniqueTestEmail()
        AuthFlowUITests.register(app, email: email, password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        app.buttons["home-avatar-settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-delete-account"].waitForExistence(timeout: 5))
        app.buttons["settings-delete-account"].tap()

        let confirmationAlert = app.alerts["Delete account?"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5))
        confirmationAlert.buttons["Delete"].tap()

        XCTAssertTrue(app.textFields["signin-email"].waitForExistence(timeout: 10))

        AuthFlowUITests.signIn(app, email: email, password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.staticTexts["signin-error"].waitForExistence(timeout: 10))
    }

    /// A stale-session delete attempt (`auth_time` older than the backend's
    /// 5-minute `require_fresh_reauth` window, ASVS 7.5.1) shows the
    /// re-authentication prompt rather than silently failing — this test is
    /// a documented SKELETON: forcing a genuinely stale `auth_time` requires
    /// either a long real wait (impractical in CI) or a test-only backdoor
    /// this app deliberately does not build (no test hooks ship in release
    /// source, AC32/SC-7) — left for the Mac-phase operator to decide how to
    /// simulate (e.g. a short-lived test Firebase project config) rather
    /// than fabricating a fake shortcut here.
    func testDeleteAccountWithStaleSessionShowsTheReauthPrompt() throws {
        throw XCTSkip("Requires a controlled way to force a stale auth_time — see the method doc comment.")
    }
}
