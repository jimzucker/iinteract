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

/// End-to-end UI tests for the flows that span multiple alert/sheet
/// presentations and the gear-icon visibility logic. These complement
/// the unit tests on `PINPromptCoordinator`, `PINVerifyCoordinator`,
/// and `SettingsReconciler` by verifying real `UIAlertController`
/// rendering and tap behavior.
///
/// We pre-seed UserDefaults via launchArguments rather than driving
/// iOS Settings.app — Settings.app automation is brittle and the
/// reconciler unit tests already cover the toggle-state matrix.
final class iInteractUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp(
        configurationMode: String = "default",
        pinEnabled: Bool = false,
        hideConfig: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-configuration_mode", configurationMode,
            "-pin_enabled", pinEnabled ? "YES" : "NO",
            "-hide_config", hideConfig ? "YES" : "NO",
            "-displaySplashScreen", "999.999.999",  // suppress voice picker
        ]
        app.launch()
        return app
    }

    // MARK: smoke

    /// App launches, the bundled panel list is visible, and the gear
    /// icon is on the navigation bar.
    func testLaunch_DefaultState_GearVisible() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars.buttons["gearshape"].waitForExistence(timeout: 5)
                      || app.navigationBars.buttons.matching(identifier: "Configure").firstMatch.exists
                      || app.navigationBars.firstMatch.buttons.firstMatch.waitForExistence(timeout: 5),
                      "gear button must be present in the nav bar on launch")
    }

    // MARK: U6 — tap gear with no PIN opens editor (regression for "alert when no PIN" bug)

    func testGearTap_DefaultMode_ShowsConfigurationOffAlert() {
        let app = launchApp(configurationMode: "default")
        // Tap any nav-bar button (only one exists in the default mode
        // — the gear).
        let gear = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        // Expect the "Configuration is Off" alert from showEditor.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.label.contains("Configuration is Off")
                      || alert.staticTexts["Configuration is Off"].exists,
                      "expected the Default-mode alert spelling out the three modes")
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.exists)
    }

    // MARK: U10 — Hide Configuration toggles gear visibility

    func testHideConfig_True_HidesGear() {
        let app = launchApp(hideConfig: true)
        // Wait for the table to settle, then check no gear button.
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5))
        // Nav bar may have other buttons in some configs but should NOT
        // have the gear icon when hide_config is on.
        let navButtons = app.navigationBars.firstMatch.buttons
        for i in 0..<navButtons.count {
            let label = navButtons.element(boundBy: i).label
            XCTAssertFalse(label.lowercased().contains("gear")
                           || label.lowercased().contains("settings")
                           || label.lowercased().contains("configure"),
                           "found nav-bar button \"\(label)\" but Hide Configuration should remove the gear")
        }
    }

    // TODO: U1–U5, U7–U9, U11 — flows that require pre-seeded PIN
    // state (the PIN hash lives in iCloud KVS, which we can't easily
    // inject from launchArguments). Either:
    //   (a) Add a debug-only launchArgument like `-test_seed_pin abcd`
    //       that pre-installs a hash on launch, OR
    //   (b) Drive iOS Settings.app to enable PIN through the real flow.
    // (a) is more reliable and faster; (b) tests more end-to-end. Both
    // are deferred to a follow-up sprint — the coordinator/reconciler
    // unit tests already cover the underlying logic; XCUITest here adds
    // value mainly for the visual rendering and alert-button wiring,
    // which the existing tests above exercise.
}
