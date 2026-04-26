//
//  iInteractTests.swift
//  iInteractTests
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import XCTest
@testable import iInteract

class iInteractTests: XCTestCase {

    // MARK: - Panel Tests

    func testPanelReadFromPlistReturnsSevenPanels() {
        let panels = Panel.readFromPlist()
        XCTAssertEqual(panels.count, 7, "panels.plist should define exactly 7 panels")
    }

    func testPanelReadFromPlistAllHaveTitles() {
        let panels = Panel.readFromPlist()
        for panel in panels {
            XCTAssertFalse(panel.title.isEmpty, "Every panel must have a non-empty title")
        }
    }

    func testPanelReadFromPlistAllHaveInteractions() {
        let panels = Panel.readFromPlist()
        for panel in panels {
            XCTAssertGreaterThanOrEqual(panel.interactions.count, 3, "Each panel should have at least 3 interactions")
            XCTAssertLessThanOrEqual(panel.interactions.count, 4, "Each panel should have at most 4 interactions")
        }
    }

    func testPanelDirectInit() {
        let interaction = Interaction(interactionName: "happy", picture: UIImage(), boySound: nil, girlSound: nil)
        let panel = Panel(title: "I feel", color: .blue, interactions: [interaction])
        XCTAssertEqual(panel.title, "I feel")
        XCTAssertEqual(panel.interactions.count, 1)
    }

    func testPanelDataDictionaryInit() {
        let dict: [String: NSObject] = [
            "title": "I feel" as NSObject,
            "color": ["red": Float(255), "green": Float(0), "blue": Float(0)] as NSObject,
            "interactions": ["happy", "sad"] as NSObject
        ]
        let panel = Panel(dataDictionary: dict)
        XCTAssertEqual(panel.title, "I feel")
        XCTAssertEqual(panel.interactions.count, 2)
        XCTAssertEqual(panel.interactions[0].name, "happy")
        XCTAssertEqual(panel.interactions[1].name, "sad")
    }

    // MARK: - Interaction Tests

    func testInteractionDirectInitStoresProperties() {
        let image = UIImage()
        let sound = URL(fileURLWithPath: "/tmp/test.mp3")
        let interaction = Interaction(interactionName: "happy", picture: image, boySound: sound, girlSound: nil)
        XCTAssertEqual(interaction.name, "happy")
        XCTAssertEqual(interaction.picture, image)
        XCTAssertEqual(interaction.boySound, sound)
        XCTAssertNil(interaction.girlSound)
    }

    func testInteractionNameInitSetsName() {
        let interaction = Interaction(interactionName: "happy")
        XCTAssertEqual(interaction.name, "happy")
    }

    func testInteractionsSoundsLoadedForAllPanelItems() {
        let panels = Panel.readFromPlist()
        for panel in panels {
            for interaction in panel.interactions {
                XCTAssertNotNil(interaction.boySound, "Boy sound missing for '\(interaction.name ?? "")'")
                XCTAssertNotNil(interaction.girlSound, "Girl sound missing for '\(interaction.name ?? "")'")
            }
        }
    }

    func testInteractionImagesLoadedForAllPanelItems() {
        let panels = Panel.readFromPlist()
        for panel in panels {
            for interaction in panel.interactions {
                XCTAssertNotNil(interaction.picture, "Image missing for '\(interaction.name ?? "")'")
            }
        }
    }

    // MARK: - UserDefaults Tests

    func testDefaultSettingsRegistered() {
        // Use an isolated suite so prior app state doesn't interfere
        let defaults = UserDefaults(suiteName: "iInteractTests")!
        defaults.register(defaults: [
            "voice_enabled": "YES",
            "voice_style": "girl",
            ConfigurationMode.userDefaultsKey: ConfigurationMode.default.rawValue,
            "displaySplashScreen": "0.0"
        ])
        XCTAssertEqual(defaults.string(forKey: "voice_enabled"), "YES")
        XCTAssertEqual(defaults.string(forKey: "voice_style"), "girl")
        XCTAssertEqual(defaults.string(forKey: ConfigurationMode.userDefaultsKey), "default")
        XCTAssertEqual(ConfigurationMode.current(defaults), .default)
        XCTAssertEqual(defaults.string(forKey: "displaySplashScreen"), "0.0")
        defaults.removePersistentDomain(forName: "iInteractTests")
    }
}
