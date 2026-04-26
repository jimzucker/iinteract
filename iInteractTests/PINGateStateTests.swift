//
//  PINGateStateTests.swift
//  iInteractTests
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import XCTest
@testable import iInteract

final class PINGateStateTests: XCTestCase {

    var tempDir: URL!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINGateStateTests-\(UUID().uuidString)", isDirectory: true)
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir, keyValueStore: kvs)
        store.setPIN("1234")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCorrectPINReturnsSuccess() {
        let state = PINGateState(store: store)
        XCTAssertEqual(state.attempt("1234"), .success)
    }

    func testWrongPINReturnsRemainingAttempts() {
        let state = PINGateState(store: store)
        XCTAssertEqual(state.attempt("0000"),
                       .wrong(remainingAttempts: PINGateState.maxAttempts - 1))
    }

    func testFiveWrongAttemptsLockOut() {
        let state = PINGateState(store: store)
        for _ in 0..<(PINGateState.maxAttempts - 1) {
            _ = state.attempt("0000")
        }
        let last = state.attempt("0000")
        if case .lockedOut(let secs) = last {
            XCTAssertGreaterThan(secs, 0)
            XCTAssertLessThanOrEqual(secs, Int(PINGateState.lockoutDuration))
        } else {
            XCTFail("Expected lockedOut, got \(last)")
        }
        XCTAssertTrue(state.isLocked)
    }

    func testWhileLockedAttemptStillReturnsLockedOut() {
        let state = PINGateState(store: store)
        for _ in 0..<PINGateState.maxAttempts { _ = state.attempt("0000") }
        XCTAssertTrue(state.isLocked)
        // Even a *correct* PIN during lockout returns lockedOut, not success.
        if case .lockedOut = state.attempt("1234") {
            // expected
        } else {
            XCTFail("Locked state must reject all attempts including correct ones")
        }
    }

    func testLockoutExpiresAfterDuration() {
        var fakeNow = Date(timeIntervalSinceReferenceDate: 0)
        let state = PINGateState(store: store, now: { fakeNow })
        for _ in 0..<PINGateState.maxAttempts { _ = state.attempt("0000") }
        XCTAssertTrue(state.isLocked)
        // Advance time past the lockout window.
        fakeNow = fakeNow.addingTimeInterval(PINGateState.lockoutDuration + 1)
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(state.attempt("1234"), .success)
    }

    func testSuccessResetsAttempts() {
        let state = PINGateState(store: store)
        _ = state.attempt("0000")
        _ = state.attempt("0000")
        XCTAssertEqual(state.attempts, 2)
        _ = state.attempt("1234")
        XCTAssertEqual(state.attempts, 0)
    }
}
