//
//  AppDelegate.swift`x
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. 
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        defaultSettings()
        applyUITestSeedIfPresent()
        // First-launch only: a brand-new device with iCloud signed in adopts
        // the mode another device set. After that, UserDefaults is the source
        // of intent — runtime reconcile (in FeelingTableViewController) pushes
        // local changes from iOS Settings up to KVS.
        PanelStore.shared.adoptCloudConfigurationModeIfFirstLaunch()
        // Kick off the CloudKit push drainer when iCloud is signed in
        // and the AssetStore is CloudKit-backed (see PanelStore.shared
        // factory). No-op when running on an iCloud-signed-out device.
        // Also seeds the queue with all existing user panels +
        // interactions on the first CloudKit launch.
        PanelStore.shared.startCloudKitSyncIfNeeded()
        WatchSync.shared.start()
        return true
    }

    /// Debug-only hook for XCUITest to pre-seed PIN state at launch.
    /// Recognized launch arguments (pass via `app.launchArguments`):
    /// - `-ui_test_reset YES` — wipes the PIN hash and any persisted
    ///   lockout state (`pin_attempts`, `pin_locked_until_epoch`) so
    ///   each test starts clean.
    /// - `-ui_test_pin <pin>` — installs the given PIN after reset.
    /// Both gated by `#if DEBUG` so they cannot ship in release.
    private func applyUITestSeedIfPresent() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "ui_test_reset") {
            PanelStore.shared.clearAllUserData()
            defaults.removeObject(forKey: "panelstore.pin_attempts")
            defaults.removeObject(forKey: "panelstore.pin_locked_until_epoch")
        }
        if let pin = defaults.string(forKey: "ui_test_pin"), !pin.isEmpty {
            PanelStore.shared.setPIN(pin)
        }
        #endif
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // MARK: - Settings

    // registerDefaults only updates values not previously set, safe to call every launch.
    fileprivate func defaultSettings() {
        UserDefaults.standard.register(defaults: [
            "voice_enabled": "YES",
            "voice_style": "girl",
            ConfigurationMode.userDefaultsKey: ConfigurationMode.default.rawValue,
            "displaySplashScreen": "0.0"
        ])
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
}

