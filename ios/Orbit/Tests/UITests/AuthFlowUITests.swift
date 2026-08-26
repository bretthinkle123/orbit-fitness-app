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
        // Start every auth test signed OUT. A Firebase session survives app
        // relaunch AND uninstall (it lives in the simulator's device-wide
        // Keychain), so without this the app opens on the signed-in tab shell
        // and every one of these tests fails hunting for sign-in fields that
        // aren't on screen. Handled by `OrbitApp.resetAuthStateIfRequested`.
        app.launchArguments.append("-OrbitUITestResetAuth")
        app.launch()
        return app
    }

    /// Taps a text field, waits for it to actually take keyboard focus, then
    /// types.
    ///
    /// `tap()` returning does not mean the field is focused — the keyboard may
    /// still be coming up, especially on a sheet that is animating in. Typing
    /// into an unfocused field fails with "Neither element nor any descendant
    /// has keyboard focus" AFTER three internal retries, so it presents as a
    /// slow, intermittent failure rather than an obvious one. Observed on the
    /// smoke chain's weight-entry sheet.
    static func typeInto(_ field: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field never appeared", file: file, line: line)
        field.tap()
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed,
                       "field never took keyboard focus", file: file, line: line)
        field.typeText(text)
    }

    /// Relaunches the app KEEPING the signed-in session.
    ///
    /// `launchApp()` passes `-OrbitUITestResetAuth` so each test starts signed
    /// out, and `XCUIApplication` RETAINS its launch arguments across
    /// relaunches — so a plain `app.terminate(); app.launch()` signs the user
    /// out again mid-test. Any test relaunching to prove something PERSISTS
    /// (the smoke chain's theme/units-survive-restart check) must strip the
    /// flag first, or it lands on the sign-in screen instead of the tab shell.
    static func relaunchPreservingSession(_ app: XCUIApplication) {
        app.launchArguments.removeAll { $0 == "-OrbitUITestResetAuth" }
        app.terminate()
        app.launch()
    }

    /// Dismisses iOS's "Use Strong Password?" AutoFill sheet if it appears.
    ///
    /// Tapping a `.newPassword` secure field pops this sheet from a SEPARATE
    /// process (it surfaces inside the app's element tree as a remote view).
    /// It swallows the subsequent `typeText`, so the password never lands, the
    /// submit button stays `Disabled`, and the tap on it silently no-ops —
    /// XCUITest does NOT fail when you tap a disabled button. The visible
    /// symptom is a register flow that runs green through every step and then
    /// times out waiting for the signed-in screen, with no account ever
    /// created. Closing the sheet keeps the app's real `.newPassword` content
    /// type intact rather than weakening production behaviour for the tests.
    static func dismissStrongPasswordSheetIfPresent(_ app: XCUIApplication) {
        let closeButton = app.buttons["xmark"]
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        }
    }

    /// Dismisses iOS's "Save Password?" prompt, which appears AFTER a
    /// successful register/sign-in submit.
    ///
    /// Like the strong-password sheet, it is drawn by another process on top
    /// of the app. It is especially treacherous because `waitForExistence`
    /// still resolves elements UNDERNEATH it — so a test that only asserts
    /// "the signed-in screen exists" passes, and the NEXT test that tries to
    /// TAP anything fails instead, one step removed from the actual cause.
    /// That is exactly how the smoke chain failed on its first `tab-fuel` tap
    /// while the register test alongside it passed.
    static func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: 5) else { return }

        // POLL rather than dismiss once. Two distinct hazards:
        //  1. The prompt animates out, so a tap issued during that animation
        //     still lands on the prompt — which reads as "the app ignored my
        //     tap" one step later. Hence waiting for non-existence, not just
        //     for the tap to be sent.
        //  2. It can appear LATE — after the first dismissal has already
        //     returned — and then silently swallow the next tab tap. That is
        //     what made the muscle-row and smoke tests intermittent: each
        //     failed on the assertion right after a tab tap, at points that
        //     had passed in earlier runs.
        // Dismissing repeatedly until it has stayed gone covers both.
        for _ in 0..<3 {
            guard notNow.exists else { break }
            notNow.tap()
            _ = notNow.waitForNonExistence(timeout: 5)
        }
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
        dismissSavePasswordPromptIfPresent(app)
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
        dismissStrongPasswordSheetIfPresent(app)
        passwordField.typeText(password)

        app.buttons["register-submit"].tap()
        dismissSavePasswordPromptIfPresent(app)
    }
}
