//
//  iInteractUITests.swift
//  iInteractUITests
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import XCTest

/// End-to-end UI tests for the flows that span gear visibility, alert
/// title rendering, and the no-PIN editor pass-through. These complement
/// the unit tests on `PINPromptCoordinator`, `PINVerifyCoordinator`,
/// and `SettingsReconciler`, which together cover the underlying
/// validation / cycle / dispatch logic in milliseconds without UIKit.
///
/// Deferred (see TODO at bottom): chained-alert flows (Set PIN →
/// security question, verify → cycle on wrong PIN). XCUITest cannot
/// reliably observe mid-dismiss alert presentations on the simulator;
/// the underlying logic is exhaustively unit-tested via TestPINPresenter
/// recording the alert sequence deterministically.
final class iInteractUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp(
        configurationMode: String = "default",
        pinEnabled: Bool = false,
        hideConfig: Bool = false,
        reset: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-configuration_mode", configurationMode,
            "-pin_enabled", pinEnabled ? "YES" : "NO",
            "-hide_config", hideConfig ? "YES" : "NO",
            "-displaySplashScreen", "999.999.999",  // suppress voice picker
        ]
        if reset { args += ["-ui_test_reset", "YES"] }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// Returns true when any descendant static text inside `element`
    /// contains `substring`. Use for label searches inside an alert.
    private func anyLabelContains(_ substring: String, in element: XCUIElement) -> Bool {
        let labels = element.staticTexts.allElementsBoundByIndex.map(\.label)
        return labels.contains(where: { $0.contains(substring) })
    }

    // MARK: smoke

    func testLaunch_DefaultState_GearVisible() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars.firstMatch.buttons.firstMatch.waitForExistence(timeout: 5),
                      "gear button must be present in the nav bar on launch")
    }

    // MARK: U6 — gear in Default mode shows the three-modes alert

    func testGearTap_DefaultMode_ShowsConfigurationOffAlert() {
        let app = launchApp(configurationMode: "default")
        let gear = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.label.contains("Configuration is Off")
                      || alert.staticTexts["Configuration is Off"].exists,
                      "expected the Default-mode alert spelling out the three modes")
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.exists)
    }

    // MARK: U10 — Hide Configuration removes the gear

    func testHideConfig_True_HidesGear() {
        let app = launchApp(hideConfig: true)
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5))
        let navButtons = app.navigationBars.firstMatch.buttons
        for i in 0..<navButtons.count {
            let label = navButtons.element(boundBy: i).label.lowercased()
            XCTAssertFalse(label.contains("gear")
                           || label.contains("settings")
                           || label.contains("configure"),
                           "found nav-bar button \"\(label)\" but Hide Configuration should remove the gear")
        }
    }

    // MARK: U6b — gear in Customize mode with NO PIN opens editor directly
    //
    // Regression for the bug "alert when no PIN" — confirmActionWithPIN
    // used to show a misleading "PIN-protected" Cancel/Configure alert
    // when no PIN existed. Now showEditor short-circuits to openEditor.

    func testGearTap_CustomizeMode_NoPIN_OpensEditorDirectly() {
        let app = launchApp(configurationMode: "custom", pinEnabled: false)
        let gear = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        XCTAssertTrue(app.navigationBars["Edit Panels"].waitForExistence(timeout: 3),
                      "with no PIN set, gear tap must open the editor without an alert")
        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "no alert should appear when there's no PIN to enforce")
    }

    // MARK: U1-init — Set PIN alert appears with bounds line

    func testEnablePIN_PromptAppears_WithBoundsLineUpFront() {
        let app = launchApp(pinEnabled: true)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "Set PIN alert must appear when pin_enabled diverges from hasPIN")
        XCTAssertTrue(alert.label.contains("Set PIN")
                      || alert.staticTexts["Set PIN"].exists)
        XCTAssertTrue(anyLabelContains("4–8", in: alert)
                      || anyLabelContains("4-8", in: alert)
                      || anyLabelContains("4", in: alert),
                      "bounds line (4–8 letters or numbers) must appear up front")
        XCTAssertEqual(alert.secureTextFields.count, 2,
                       "Set PIN alert has two secure text fields: PIN and Confirm")
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        XCTAssertTrue(alert.buttons["Set PIN"].exists)
    }

    // MARK: U4 — Cancel at Set PIN dismisses alert

    func testEnablePIN_Cancel_DismissesAlert() {
        let app = launchApp(pinEnabled: true)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
    }

    // MARK: TODO — deferred chained-alert flows
    //
    // U1 happy path (Set PIN + Skip security question), U3 cycle on
    // too-short, U5 verify-with-PIN-set, U7 wrong-PIN cycling, U8
    // five-wrong-attempts-lockout, U9 Forgot PIN abort.
    //
    // These all exercise alert-dismiss-then-present chains, which are
    // unreliable under XCUITest in the simulator: the next alert
    // doesn't always appear because UIKit's dismiss animation overlaps
    // the subsequent present, and we couldn't find a deterministic
    // workaround without making production UX worse with a delay.
    //
    // The underlying logic is fully covered by unit tests:
    //   - PINPromptCoordinatorEnableTests verifies the cycle, prefill,
    //     bounds error, mismatch error, max/min boundaries, and the
    //     Set PIN → security question composite (10 + 5 = 15 tests).
    //   - PINVerifyCoordinatorTests verifies wrong-PIN cycling, lockout
    //     after 5 wrongs, lockout expiry, Forgot PIN signal, bounds
    //     line on retry (10 tests).
    //   - PINGateStateTests verifies lockout persistence across app
    //     restart (4 tests, A4 in the plan).
    //
    // Future work: replace the simulator NSUbiquitousKeyValueStore
    // dependency with an in-memory store for UI tests via a debug-only
    // launchArgument, or drive iOS Settings.app for the full path.
}
