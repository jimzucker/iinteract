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
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINGateStateTests-\(UUID().uuidString)", isDirectory: true)
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir, keyValueStore: kvs)
        store.setPIN("1234")
        // Isolate UserDefaults per test so the persisted lockout state
        // (A4) doesn't leak across tests.
        let suite = "PINGateStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeState(now: @escaping () -> Date = Date.init) -> PINGateState {
        PINGateState(store: store, now: now, defaults: defaults)
    }

    func testCorrectPINReturnsSuccess() {
        let state = makeState()
        XCTAssertEqual(state.attempt("1234"), .success)
    }

    func testWrongPINReturnsRemainingAttempts() {
        let state = makeState()
        XCTAssertEqual(state.attempt("0000"),
                       .wrong(remainingAttempts: PINGateState.maxAttempts - 1))
    }

    func testFiveWrongAttemptsLockOut() {
        let state = makeState()
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
        let state = makeState()
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
        let state = makeState { fakeNow }
        for _ in 0..<PINGateState.maxAttempts { _ = state.attempt("0000") }
        XCTAssertTrue(state.isLocked)
        // Advance time past the lockout window.
        fakeNow = fakeNow.addingTimeInterval(PINGateState.lockoutDuration + 1)
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(state.attempt("1234"), .success)
    }

    func testSuccessResetsAttempts() {
        let state = makeState()
        _ = state.attempt("0000")
        _ = state.attempt("0000")
        XCTAssertEqual(state.attempts, 2)
        _ = state.attempt("1234")
        XCTAssertEqual(state.attempts, 0)
    }

    // MARK: - A4 — persistence across instances (simulates app restart)

    /// 5 wrong attempts then "kill app" (drop the state instance).
    /// A fresh instance reading the same UserDefaults must still be locked.
    func testLockoutPersistsAcrossInstances() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let state1 = makeState { now }
        for _ in 0..<PINGateState.maxAttempts { _ = state1.attempt("0000") }
        XCTAssertTrue(state1.isLocked)

        // Simulate app restart — fresh state, same defaults, same clock.
        let state2 = makeState { now }
        XCTAssertTrue(state2.isLocked,
                      "lockout must survive app restart so kill-and-relaunch can't bypass the 5-attempt counter")
        // 6th attempt with correct PIN is still rejected because we're locked.
        if case .lockedOut = state2.attempt("1234") {} else {
            XCTFail("Locked state on restart must reject even correct PIN")
        }
    }

    /// Lockout naturally expires after 60s of wall clock — restart inside
    /// the window stays locked, restart outside the window is fresh.
    func testLockoutExpires_OnRestartAfterWindow() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let state1 = makeState { clock }
        for _ in 0..<PINGateState.maxAttempts { _ = state1.attempt("0000") }
        XCTAssertTrue(state1.isLocked)

        // Simulate restart 61s later — past the 60s window.
        clock = clock.addingTimeInterval(PINGateState.lockoutDuration + 1)
        let state2 = makeState { clock }
        XCTAssertFalse(state2.isLocked)
        XCTAssertEqual(state2.attempt("1234"), .success)
    }

    /// Successful verify clears the persisted attempt counter so the
    /// next "first wrong" reports 4 attempts remaining (not 0).
    func testSuccessClearsPersistedAttempts() {
        let state1 = makeState()
        _ = state1.attempt("0000")
        _ = state1.attempt("0000")
        _ = state1.attempt("1234")  // success — clears persisted state

        let state2 = makeState()
        XCTAssertEqual(state2.attempt("0000"),
                       .wrong(remainingAttempts: PINGateState.maxAttempts - 1),
                       "after successful verify, persisted attempts is cleared")
    }

    /// First-launch / no-prior-state: nothing in defaults, fresh counter.
    func testFreshDefaults_StartUnlockedAtZeroAttempts() {
        let state = makeState()
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(state.attempts, 0)
    }
}
