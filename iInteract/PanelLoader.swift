//
//  PanelLoader.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  iOS-only. Lives outside Panel.swift so the watchOS extension target,
//  which doesn't link PanelStore/ConfigurationMode, still compiles Panel.

import Foundation

extension Panel {
    /// Returns the panels to display for the current configuration mode.
    /// - `.default`: bundled panels in plist order, exactly like v1.x.
    /// - `.custom`:  bundled panels merged with the user's panels, then
    ///               filtered + reordered per `PanelStore.layout()`.
    class func load(mode: ConfigurationMode, store: PanelStore = .shared) -> [Panel] {
        let builtIns = readFromPlist()
        switch mode {
        case .default:
            return builtIns
        case .custom:
            let combined = builtIns + store.userPanels()
            return store.applyLayout(to: combined)
        }
    }
}
