//
//  ConfigurationMode.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation

enum ConfigurationMode: String {
    case `default`
    case custom

    static let userDefaultsKey = "configuration_mode"

    static func current(_ defaults: UserDefaults = .standard) -> ConfigurationMode {
        let raw = defaults.string(forKey: userDefaultsKey) ?? ConfigurationMode.default.rawValue
        return ConfigurationMode(rawValue: raw) ?? .default
    }
}
