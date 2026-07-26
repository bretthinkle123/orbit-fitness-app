import XCTest

/// T16's accessibility pass — **MAC EXECUTION ONLY** (same Linux-host
/// caveat as every other `Tests/UITests/*`/`Tests/SmokeUITests.swift` file,
/// `.pipeline/implementation-progress.md` T11-T16). Reuses
/// `Tests/UITests/AuthFlowUITests.swift`'s shared `launchApp`/`register`
/// helpers rather than re-deriving them a fourth time.
///
/// Three concerns, each verified the way XCUITest can actually mechanically
/// check it (rather than pretending a black-box UI-test process can inspect
/// SwiftUI internals it has no access to):
///
/// 1. **Reduce Motion** — the FREEZE mechanism itself
///    (`DesignSystem/MotionPreference.swift`) is unit-proven at the Swift
///    Testing level (`MotionPreferenceTests`, `Tests/ThemeTests.swift`):
///    `repeatingAnimationsAllowed(reduceMotion: true) == false`, the exact
///    condition `Figures/MuscleFigure.swift`'s `startFloatingIfAllowed()` and
///    `Components/HourTimeline.swift`'s `startPulsingIfAllowed()` both gate
///    on. This file's `testReduceMotionScreensStillRenderCorrectly` is the
///    DEVICE-LEVEL half: XCUITest has no public, documented API to toggle
///    Reduce Motion in-process, so it drives the Settings app's own
///    Accessibility > Motion switch (the standard, widely-used — if
///    unofficial — technique for this; the exact cell/label path is iOS-
///    version-dependent and may need adjustment on the operator's Mac,
///    flagged here rather than silently assumed stable) and asserts the app
///    still renders/navigates correctly with the real system setting
///    engaged, rather than asserting on an offset XCUITest cannot read.
/// 2. **VoiceOver-exposed value/trait shape** — VoiceOver itself does not
///    need to be literally toggled on for XCUITest to verify what it WOULD
///    read: `XCUIElement.label` and `.traits`-derived properties
///    (`.isSelected`) already reflect the exact accessibility tree VoiceOver
///    consumes. This is the standard, non-fragile technique (running real
///    VoiceOver during XCUITest actively conflicts with XCUITest's own
///    synthetic touch events) — these tests assert the LABEL SHAPE the
///    design README's own acceptance criteria name verbatim.
/// 3. **Hit-target audit** — `XCUIElement.frame` is a real, measurable
///    `CGRect` XCUITest can read directly; asserts width/height ≥ 44pt
///    (`apple-hig-compliance`) for a representative sample of controls
///    whose GLYPH is smaller than that (36pt set circles, 32pt palette
///    swatches) — the exact cases `.pipeline/implementation-progress.md`'s
///    T14/T15 hit-target tables already hand-verified from source; this is
///    the MACHINE-MEASURED confirmation of that same claim.
final class AccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Reduce Motion (device-level, best-effort)

    func testReduceMotionScreensStillRenderCorrectly() throws {
        toggleSystemReduceMotion(to: true)
        defer { toggleSystemReduceMotion(to: false) }

        let app = AuthFlowUITests.launchApp()
        AuthFlowUITests.register(app, email: AuthFlowUITests.uniqueTestEmail(), password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        // Body hosts the ONE continuously-repeating animation that ships
        // today (`MuscleFigure`'s float loop) — with Reduce Motion engaged
        // the screen must still render both figures without hanging.
        app.buttons["tab-body"].tap()
        XCTAssertTrue(app.staticTexts["Front"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Back"].waitForExistence(timeout: 5))

        // Fuel hosts the OTHER one (HourTimeline's pulsing "Now" marker,
        // visible on the By-hour page) — same "still renders" check.
        // "Meals"/"By hour" are the `SegmentedToggle` segment BUTTONS (their
        // label comes from the segment's own `Text`), not static text.
        app.buttons["tab-fuel"].tap()
        XCTAssertTrue(app.buttons["Meals"].waitForExistence(timeout: 10))
    }

    /// Drives the Settings app's Accessibility > Motion > Reduce Motion
    /// switch. Best-effort: the exact navigation path has shifted across
    /// iOS major versions before and may need adjusting on the Mac this
    /// actually runs on — flagged explicitly rather than assumed stable,
    /// same disclosure posture as `AccountLifecycleUITests`'
    /// `testDeleteAccountWithStaleSessionShowsTheReauthPrompt` skip.
    private func toggleSystemReduceMotion(to isOn: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        settings.tables.staticTexts["Accessibility"].tap()
        settings.tables.staticTexts["Motion"].tap()
        let reduceMotionSwitch = settings.tables.switches["Reduce Motion"]
        if reduceMotionSwitch.waitForExistence(timeout: 5), let currentValue = reduceMotionSwitch.value as? String {
            let isCurrentlyOn = currentValue == "1"
            if isCurrentlyOn != isOn {
                reduceMotionSwitch.tap()
            }
        }
        settings.terminate()
    }

    // MARK: - 2. VoiceOver-exposed value/trait shape (README's verbatim acceptance criteria)

    /// README: "rings/bars expose value + target ('1,303 of 2,350
    /// kilocalories')". Asserts the SHAPE (an "N of M kilocalories" string),
    /// not a hardcoded number — a brand-new account's own real baseline
    /// values are whatever `POST /me/bootstrap` returns.
    func testCalorieRingExposesValueAndTargetToVoiceOver() throws {
        let app = AuthFlowUITests.launchApp()
        AuthFlowUITests.register(app, email: AuthFlowUITests.uniqueTestEmail(), password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        let ring = app.otherElements["home-calorie-ring"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        let label = ring.label
        XCTAssertTrue(label.contains(" of "), "expected an \"N of M kilocalories\" shape, got: \(label)")
        XCTAssertTrue(label.contains("kilocalories"), "expected the word \"kilocalories\", got: \(label)")
    }

    /// README: "set circles expose 'Set n, done/not done' toggles". Toggles
    /// a known seeded set (Barbell Bench Press, set 1) and asserts BOTH the
    /// label text flips AND the `.isSelected` trait flips with it — the
    /// trait is what a real assistive-technology client (Switch Control,
    /// full keyboard access) reads independently of the spoken label.
    func testSetCircleExposesDoneStateAsLabelAndSelectedTrait() throws {
        let app = AuthFlowUITests.launchApp()
        AuthFlowUITests.register(app, email: AuthFlowUITests.uniqueTestEmail(), password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        app.buttons["tab-train"].tap()
        let firstSet = app.buttons["train-set-barbell-bench-press-1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 10))

        XCTAssertEqual(firstSet.label, "Set 1, not done")
        XCTAssertFalse(firstSet.isSelected)

        firstSet.tap()

        wait(for: [expectation(for: NSPredicate(format: "label == %@", "Set 1, done"), evaluatedWith: firstSet)], timeout: 10)
        XCTAssertTrue(firstSet.isSelected)
    }

    /// README: "muscle rows read '{group}, {level}, trained today'". Reads
    /// the by-muscle-group row's label BOTH before and after training chest
    /// (Barbell Bench Press), asserting the ", trained today" suffix is
    /// ABSENT then PRESENT — the exact verbatim shape, not a paraphrase.
    func testMuscleRowExposesGroupLevelAndTrainedTodayToVoiceOver() throws {
        let app = AuthFlowUITests.launchApp()
        AuthFlowUITests.register(app, email: AuthFlowUITests.uniqueTestEmail(), password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        app.buttons["tab-body"].tap()
        let chestRow = app.otherElements["body-muscle-row-chest"]
        XCTAssertTrue(chestRow.waitForExistence(timeout: 10))
        XCTAssertFalse(chestRow.label.contains("trained today"))
        XCTAssertTrue(chestRow.label.hasPrefix("Chest, "))

        app.buttons["tab-train"].tap()
        let firstSet = app.buttons["train-set-barbell-bench-press-1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 10))
        firstSet.tap()

        app.buttons["tab-body"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "trained today"), evaluatedWith: chestRow)], timeout: 10)
        XCTAssertTrue(chestRow.label.hasSuffix(", trained today"))
    }

    // MARK: - 3. Hit-target audit (≥44pt, measured via `XCUIElement.frame`)

    /// Extends `.pipeline/implementation-progress.md`'s T14/T15 hand-
    /// verified hit-target tables with a MACHINE-MEASURED confirmation for a
    /// representative sample of controls whose visible glyph is smaller
    /// than 44pt (36pt set circles, 32pt palette swatches) — the cases
    /// `apple-hig-compliance`'s "pad the tappable area, not the glyph" rule
    /// exists for.
    func testRepresentativeSmallGlyphControlsMeetTheMinimumHitTarget() throws {
        let minimumHitTarget: CGFloat = 44

        let app = AuthFlowUITests.launchApp()
        AuthFlowUITests.register(app, email: AuthFlowUITests.uniqueTestEmail(), password: AuthFlowUITests.testPassword)
        XCTAssertTrue(app.buttons["home-avatar-settings-button"].waitForExistence(timeout: 10))

        // Measure the avatar (Home tab) BEFORE navigating away — the button
        // only exists on `HomeView`, not the other 3 tabs.
        assertMeetsMinimumHitTarget(app.buttons["home-avatar-settings-button"], minimum: minimumHitTarget, name: "Avatar (30pt glyph)")

        app.buttons["tab-train"].tap()
        let setCircle = app.buttons["train-set-barbell-bench-press-1"]
        XCTAssertTrue(setCircle.waitForExistence(timeout: 10))
        assertMeetsMinimumHitTarget(setCircle, minimum: minimumHitTarget, name: "SetCircle (36pt glyph)")

        app.buttons["tab-home"].tap()
        app.buttons["home-avatar-settings-button"].tap()
        let paletteSwatch = app.buttons["settings-palette-blue"]
        XCTAssertTrue(paletteSwatch.waitForExistence(timeout: 5))
        assertMeetsMinimumHitTarget(paletteSwatch, minimum: minimumHitTarget, name: "Palette swatch (32pt glyph)")
    }

    private func assertMeetsMinimumHitTarget(_ element: XCUIElement, minimum: CGFloat, name: String) {
        XCTAssertGreaterThanOrEqual(element.frame.width, minimum, "\(name) width below the \(minimum)pt minimum hit target")
        XCTAssertGreaterThanOrEqual(element.frame.height, minimum, "\(name) height below the \(minimum)pt minimum hit target")
    }
}
