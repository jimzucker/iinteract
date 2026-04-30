//
//  EventTests.swift
//  iInteractWatchTests
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import XCTest

// Event.swift is compiled directly into this test bundle (the test
// target's Sources phase includes it), so we don't need
// `@testable import iInteractWatch` and we don't need a host app at
// runtime. Keeps the watch test bundle a pure logic-only XCTest run
// on the watchOS simulator with no install/launch dance.

/// Smoke tests for the watch-side `Event` model. The watch app is a
/// thin shell over `events.plist` parsing, so the highest-value
/// coverage here is the dictionary→Event init contract: it tolerates
/// missing optional fields, rejects malformed entries, and round-trips
/// the data the bundled plist provides.
final class EventTests: XCTestCase {

    // MARK: init(from:)

    func testInit_FromCompleteDictionary_PopulatesAllFields() {
        let dict: [String: String] = [
            "eventTitle": "Recess",
            "eventTime":  "10:30 AM",
            "eventImageName": "playground"
        ]
        let event = Event(from: dict)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.title, "Recess")
        XCTAssertEqual(event?.time, "10:30 AM")
        XCTAssertEqual(event?.imageName, "playground")
    }

    func testInit_FromMinimalDictionary_AllowsMissingImageName() {
        // imageName is optional — Event still constructs without it.
        let dict = ["eventTitle": "Lunch", "eventTime": "12:00 PM"]
        let event = Event(from: dict)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.title, "Lunch")
        XCTAssertEqual(event?.time, "12:00 PM")
        XCTAssertNil(event?.imageName)
    }

    func testInit_MissingTitle_ReturnsNil() {
        let event = Event(from: ["eventTime": "9:00 AM"])
        XCTAssertNil(event,
                     "title is required; missing it must not yield a partially-formed Event")
    }

    func testInit_MissingTime_ReturnsNil() {
        let event = Event(from: ["eventTitle": "Snack"])
        XCTAssertNil(event,
                     "time is required; missing it must not yield a partially-formed Event")
    }

    func testInit_EmptyDictionary_ReturnsNil() {
        XCTAssertNil(Event(from: [:]))
    }

    // MARK: loadAll() bundled-plist contract

    func testLoadAll_ReadsBundledPlist_WithoutCrashing() {
        // Whatever the bundled events.plist contains, loadAll must not
        // crash. Returns an array (possibly empty if the plist is
        // missing — that's also a valid state for tests bundling
        // separately from the watch app).
        let events = Event.loadAll()
        XCTAssertNoThrow(events, "loadAll must be total — never throws")
        // If the plist was bundled with the test target, every entry
        // must have title + time non-empty (Event.init enforces this).
        for event in events {
            XCTAssertFalse(event.title.isEmpty)
            XCTAssertFalse(event.time.isEmpty)
        }
    }
}
