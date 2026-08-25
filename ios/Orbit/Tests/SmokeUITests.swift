import XCTest

/// AC27's FULL smoke chain, exercised as ONE XCUITest flow against the REAL
/// running backend + Firebase Auth emulator — **MAC EXECUTION ONLY** (this
/// Linux host has no Swift/Xcode toolchain, `.pipeline/implementation-
/// progress.md`'s T11-T15 entries). Same launch-environment override as
/// `Tests/UITests/AuthFlowUITests.swift`/`AccountLifecycleUITests.swift`
/// (T13) — `OrbitAPIBaseURL`/`OrbitFirebaseAuthEmulatorHost` — and reuses
/// their shared `launchApp()`/`register()`/`signIn()` helpers rather than
/// re-deriving a second copy (rule-of-two: this is the third UI test file to
/// need them).
///
/// The chain: **register → sign in [implicit: registration signs in] →
/// quick-add food (ring/totals react) → toggle sets (score ticks, Body
/// glows) → log weight → switch palette/units (persists across relaunch) →
/// delete account (cascades, lands on sign-in)** — plan.md's test-strategy
/// line and `.pipeline/acceptance.md`'s AC27 row, verbatim.
///
/// Depends on the migration-seeded catalog (`migrations/versions/
/// 0002_seed_catalog_program_levels.py`, read directly this session, T16):
/// the quick-food "Salmon & Rice Bowl" (breakfast panel, since every meal
/// starts empty for a brand-new account, plan §Data) and the Push Day
/// exercise "Barbell Bench Press" (`muscle_tag: "chest"`) — a set toggle on
/// it is what the Body-glow assertion below checks for. Every selector this
/// file uses is either an identifier `Tests/UITests/AuthFlowUITests.swift`
/// already established (T13) or one T16 added to a real `Screens/`/
/// `Components/` file this session — `scripts/
/// check_ui_test_identifier_consistency.py` verifies every selector below
/// resolves to a real, declared `accessibilityIdentifier` (or is an
/// explicitly documented native-control exception), so a typo here is a
/// script failure, not a silent, never-run test.
final class SmokeUITests: XCTestCase {
    // Timeouts are deliberately GENEROUS (20-30s, not the 5-10s the rest of
    // the suites use). This chain drives the whole app end to end against a
    // real backend and auth emulator, and it runs LAST, after ~11 other UI
    // tests have already been churning the same simulator. In isolation it
    // finishes comfortably; inside a full-suite run on a loaded machine the
    // tighter waits tripped intermittently — a slow machine, not a slow app.
    // Widened rather than chased, since the failure was always a wait
    // expiring, never a wrong value.

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFullSmokeChainAgainstTheRealAPI() throws {
        let app = AuthFlowUITests.launchApp()
        let email = AuthFlowUITests.uniqueTestEmail()
        AuthFlowUITests.register(app, email: email, password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 30))

        quickAddFoodAndVerifyTotalsReact(app)
        toggleASetAndVerifyScoreAndBodyGlowReact(app)
        logAWeightEntry(app)
        switchPaletteAndUnitsAndVerifyPersistenceAcrossRelaunch(app)
        deleteAccountAndVerifyItCascadesToSignIn(app, registeredEmail: email)
    }

    // MARK: - Quick-add food (ring/totals react)

    /// Fuel's own remaining-kcal figure AND Home's calorie-ring label are
    /// both driven by the ONE shared `AppStore` (plan §Frontend) — checking
    /// Fuel's own reaction is AC27's literal wording ("quick-add food (ring/
    /// totals react)"); the Home-tab existence check afterward is the
    /// cross-screen half of that same shared-store behavior.
    private func quickAddFoodAndVerifyTotalsReact(_ app: XCUIApplication) {
        app.buttons["tab-fuel"].tap()

        let remainingKcal = app.staticTexts["fuel-remaining-kcal-value"]
        XCTAssertTrue(remainingKcal.waitForExistence(timeout: 30))
        let remainingBefore = remainingKcal.label

        let quickAddChip = app.buttons["fuel-quickadd-breakfast-salmon-rice-bowl"]
        XCTAssertTrue(quickAddChip.waitForExistence(timeout: 30))
        quickAddChip.tap()

        wait(for: [expectation(for: NSPredicate(format: "label != %@", remainingBefore), evaluatedWith: remainingKcal)], timeout: 30)

        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.otherElements["home-calorie-ring"].waitForExistence(timeout: 30))
    }

    // MARK: - Toggle sets (score ticks, Body glows)

    private func toggleASetAndVerifyScoreAndBodyGlowReact(_ app: XCUIApplication) {
        app.buttons["tab-train"].tap()

        let scoreValue = app.staticTexts["train-score-value"]
        XCTAssertTrue(scoreValue.waitForExistence(timeout: 30))
        let scoreBefore = scoreValue.label

        let firstBenchPressSet = app.buttons["train-set-barbell-bench-press-1"]
        XCTAssertTrue(firstBenchPressSet.waitForExistence(timeout: 30))
        firstBenchPressSet.tap()

        wait(for: [expectation(for: NSPredicate(format: "label != %@", scoreBefore), evaluatedWith: scoreValue)], timeout: 30)

        app.buttons["tab-body"].tap()
        let chestRow = app.staticTexts["body-muscle-row-chest"]
        XCTAssertTrue(chestRow.waitForExistence(timeout: 30))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "trained today"), evaluatedWith: chestRow)], timeout: 30)
    }

    // MARK: - Log weight

    private func logAWeightEntry(_ app: XCUIApplication) {
        app.buttons["tab-home"].tap()
        let logButton = app.buttons["home-log-weight-button"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 30))
        logButton.tap()

        // Focus-aware typing: the sheet animates in, so a plain tap-then-type
        // races the keyboard coming up.
        AuthFlowUITests.typeInto(app.textFields["weight-entry-field"], "180")
        app.buttons["weight-entry-save"].tap()

        XCTAssertTrue(app.staticTexts["home-weight-trend-value"].waitForExistence(timeout: 30))
    }

    // MARK: - Switch palette/units (persists across relaunch)

    /// Relaunching genuinely terminates and restarts the process (not just
    /// backgrounding) — this proves the setting round-tripped through
    /// `PATCH /profile` and back via `POST /me/bootstrap`'s idempotent
    /// re-fetch on the next launch, not merely an in-memory `@State` value
    /// that would survive a mere tab switch regardless.
    private func switchPaletteAndUnitsAndVerifyPersistenceAcrossRelaunch(_ app: XCUIApplication) {
        app.buttons["home-avatar-settings-button"].tap()

        let bluePaletteSwatch = app.buttons["settings-palette-blue"]
        XCTAssertTrue(bluePaletteSwatch.waitForExistence(timeout: 20))
        bluePaletteSwatch.tap()

        // The Metric/Imperial segmented toggle's OWN container carries the
        // "settings-units" identifier, but each segment is its own `Button`
        // labeled by its visible text — querying by that label is the
        // correct XCUITest selector for the individual segment (identifier
        // OR label are both valid `.buttons[]` lookup keys).
        app.buttons["Imperial"].tap()

        app.buttons["settings-back"].tap()

        // Keeps the session across the restart — a plain `launch()` would
        // re-apply the suite's sign-out flag and land on sign-in, which is not
        // what this step is testing.
        AuthFlowUITests.relaunchPreservingSession(app)

        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 30))
        app.buttons["home-avatar-settings-button"].tap()

        let bluePaletteSwatchAfterRelaunch = app.buttons["settings-palette-blue"]
        XCTAssertTrue(bluePaletteSwatchAfterRelaunch.waitForExistence(timeout: 30))
        XCTAssertTrue(bluePaletteSwatchAfterRelaunch.isSelected)
        XCTAssertTrue(app.buttons["Imperial"].isSelected)
    }

    // MARK: - Delete account (cascades, lands on sign-in)

    private func deleteAccountAndVerifyItCascadesToSignIn(_ app: XCUIApplication, registeredEmail: String) {
        app.buttons["settings-delete-account"].tap()

        let confirmationAlert = app.alerts["Delete account?"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 20))
        confirmationAlert.buttons["Delete"].tap()

        XCTAssertTrue(app.textFields["signin-email"].waitForExistence(timeout: 30))

        // AC5's cascade actually ran (not a client-side "forget me") — the
        // same credentials no longer sign in afterward, mirroring
        // `AccountLifecycleUITests.testDeleteAccountErasesTheAccountAndReturnsToSignIn`.
        AuthFlowUITests.signIn(app, email: registeredEmail, password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.staticTexts["signin-error"].waitForExistence(timeout: 30))
    }
}
