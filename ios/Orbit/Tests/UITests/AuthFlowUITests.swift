import XCTest

/// XCUITest skeleton (T13) — marked for **MAC EXECUTION ONLY** (this Linux
/// host has no Swift/Xcode toolchain — `.pipeline/implementation-
/// progress.md`'s T11-T13 entries). Requires a REAL running backend
/// (`poetry run uvicorn src.orbit.main:app --port 8001`, migrations
/// applied) + a REAL running Firebase Auth emulator (`firebase emulators:
/// start --only auth`), pointed at via the app's XCUITest
/// launch-environment override (`App/OrbitApp.swift`'s
/// `resolveAPIBaseURL()`/`configureFirebaseAuthEmulatorIfConfigured()` —
/// both check `ProcessInfo.processInfo.environment` before falling back to
/// `Info.plist`, the standard XCUITest override pattern). Matches plan.md's
/// test-strategy line "XCUITest for the end-to-end smoke flow against the
/// real API" (AC27) and this task's scope ("XCUITest: sign-in/register").
final class AuthFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Registers a brand-new account (a unique email per run, mirroring the
    /// backend's own `firebase_test_user` fixture convention,
    /// `tests/conftest.py`) and expects to land on the signed-in tab shell
    /// — identified by `RootTabView`'s Home-tab avatar button, since
    /// `Screens/HomeView` itself is T15.
    func testRegisterNewAccountReachesTheSignedInTabShell() throws {
        let app = Self.launchApp()
        Self.register(app, email: Self.uniqueTestEmail(), password: Self.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))
    }

    /// Signs in with a pre-existing seeded test account (the Mac-phase
    /// operator seeds one against the Firebase Auth emulator, mirroring
    /// `scripts/seed_dast_user.py`'s server-side pattern) and expects the
    /// same signed-in landing as registration.
    func testSignInWithExistingAccountReachesTheSignedInTabShell() throws {
        let app = Self.launchApp()
        Self.signIn(app, email: Self.seededTestEmail, password: Self.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))
    }

    /// A wrong password surfaces the inline error state, not a crash or a
    /// silent no-op.
    func testSignInWithWrongPasswordShowsAnInlineError() throws {
        let app = Self.launchApp()
        Self.signIn(app, email: Self.seededTestEmail, password: "definitely-the-wrong-password")
        XCTAssertTrue(app.staticTexts["signin-error"].waitForExistence(timeout: 10))
    }

    // MARK: - Shared fixtures + flow helpers (also used by `AccountLifecycleUITests`)

    static let testPassword = "orbit-ui-test-pw-1"
    /// A test account the Mac-phase operator seeds once against the
    /// Firebase Auth emulator — a fixture identifier, not a real hardcoded
    /// production credential.
    static let seededTestEmail = "orbit-ui-tests-seeded@example.com"

    static func uniqueTestEmail() -> String {
        "orbit-ui-test-\(UUID().uuidString.prefix(8))@example.com"
    }

    static func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OrbitAPIBaseURL"] = "http://localhost:8001"
        app.launchEnvironment["OrbitFirebaseAuthEmulatorHost"] = "localhost:9099"
        app.launch()
        return app
    }

    static func signIn(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["signin-email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["signin-password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["signin-submit"].tap()
    }

    static func register(_ app: XCUIApplication, email: String, password: String, displayName: String = "Test Astronaut") {
        app.buttons["signin-go-to-register"].tap()

        let displayNameField = app.textFields["register-display-name"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 5))
        displayNameField.tap()
        displayNameField.typeText(displayName)

        let emailField = app.textFields["register-email"]
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["register-password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["register-submit"].tap()
    }
}
