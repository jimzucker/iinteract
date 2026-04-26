//
//  PanelStoreTests.swift
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

// MARK: - In-memory KVS for tests

final class MemoryKeyValueStore: KeyValueStorage {
    private var storage: [String: String] = [:]

    func string(forKey key: String) -> String? { storage[key] }

    func set(_ value: String?, forKey key: String) {
        if let value = value { storage[key] = value }
        else { storage.removeValue(forKey: key) }
    }

    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }

    @discardableResult func synchronize() -> Bool { true }
}

// MARK: - Tests

final class PanelStoreTests: XCTestCase {

    var tempDir: URL!
    var kvs: MemoryKeyValueStore!
    var iCloudSignedIn = false
    var store: PanelStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelStoreTests-\(UUID().uuidString)", isDirectory: true)
        kvs = MemoryKeyValueStore()
        iCloudSignedIn = false
        store = PanelStore(directory: tempDir,
                           keyValueStore: kvs,
                           iCloudAvailability: { [unowned self] in self.iCloudSignedIn })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: JSON round-trip

    func testUserPanelRoundTripsThroughJSON() throws {
        let interaction = Interaction(id: UUID(), name: "playground")
        let panel = Panel(title: "School",
                          color: UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0),
                          interactions: [interaction],
                          isBuiltIn: false)
        try store.addPanel(panel)

        // Recreate the store from the same directory to prove it loaded from disk.
        let reloaded = PanelStore(directory: tempDir, keyValueStore: kvs).userPanels()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].id, panel.id)
        XCTAssertEqual(reloaded[0].title, "School")
        XCTAssertEqual(reloaded[0].interactions.count, 1)
        XCTAssertEqual(reloaded[0].interactions[0].name, "playground")
        XCTAssertFalse(reloaded[0].isBuiltIn)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        reloaded[0].color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Double(r), 0.1, accuracy: 0.01)
        XCTAssertEqual(Double(g), 0.2, accuracy: 0.01)
        XCTAssertEqual(Double(b), 0.3, accuracy: 0.01)
    }

    // MARK: Layout merge

    func testApplyLayoutFiltersHiddenAndOrders() throws {
        let p1 = Panel(title: "Alpha", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "Beta", color: .green, interactions: [], isBuiltIn: false)
        let p3 = Panel(title: "Gamma", color: .blue, interactions: [], isBuiltIn: false)

        try store.setHidden(true, for: p2.id)
        try store.setOrder([p3.id, p1.id])

        let result = store.applyLayout(to: [p1, p2, p3])
        XCTAssertEqual(result.map { $0.title }, ["Gamma", "Alpha"])
    }

    func testApplyLayoutWithEmptyLayoutReturnsAllInOriginalOrder() {
        let p1 = Panel(title: "A", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "B", color: .green, interactions: [], isBuiltIn: false)
        XCTAssertEqual(store.applyLayout(to: [p1, p2]).map { $0.title }, ["A", "B"])
    }

    func testApplyLayoutKeepsUnorderedPanelsAtEnd() throws {
        let p1 = Panel(title: "A", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "B", color: .green, interactions: [], isBuiltIn: false)
        let p3 = Panel(title: "C", color: .blue, interactions: [], isBuiltIn: false)
        try store.setOrder([p2.id])
        XCTAssertEqual(store.applyLayout(to: [p1, p2, p3]).map { $0.title }, ["B", "A", "C"])
    }

    func testLayoutPersistsAcrossInstances() throws {
        let id1 = UUID(), id2 = UUID()
        try store.setOrder([id1, id2])
        try store.setHidden(true, for: id1)

        let reloaded = PanelStore(directory: tempDir, keyValueStore: kvs).layout()
        XCTAssertEqual(reloaded.orderedIDs, [id1, id2])
        XCTAssertTrue(reloaded.hiddenIDs.contains(id1))
        XCTAssertFalse(reloaded.hiddenIDs.contains(id2))
    }

    // MARK: Validators

    func testIsNameAvailableRejectsEmptyAndBuiltIns() {
        XCTAssertFalse(store.isNameAvailable(""))
        XCTAssertFalse(store.isNameAvailable("   "))
        XCTAssertFalse(store.isNameAvailable("I feel"))   // built-in, exact
        XCTAssertFalse(store.isNameAvailable("i feel"))   // case-insensitive
        XCTAssertFalse(store.isNameAvailable(" I feel ")) // trim
        XCTAssertTrue(store.isNameAvailable("School"))
    }

    func testIsNameAvailableExcludesSelfAndRejectsOtherUserPanels() throws {
        let p = Panel(title: "Custom", color: .red, interactions: [], isBuiltIn: false)
        try store.addPanel(p)
        XCTAssertFalse(store.isNameAvailable("Custom"))
        XCTAssertTrue(store.isNameAvailable("Custom", excluding: p.id))
    }

    func testAddPanelEnforcesNameUniqueness() throws {
        let p1 = Panel(title: "Foo", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "Foo", color: .blue, interactions: [], isBuiltIn: false)
        XCTAssertNoThrow(try store.addPanel(p1))
        XCTAssertThrowsError(try store.addPanel(p2)) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .nameNotUnique)
        }
    }

    func testAddPanelRejectsMoreThanSixInteractions() {
        let interactions = (1...7).map { Interaction(id: UUID(), name: "i\($0)") }
        let p = Panel(title: "TooMany", color: .red, interactions: interactions, isBuiltIn: false)
        XCTAssertThrowsError(try store.addPanel(p)) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .capacityExceeded)
        }
    }

    func testCanAddInteractionAtSixIsFalse() throws {
        let interactions = (1...6).map { Interaction(id: UUID(), name: "i\($0)") }
        let p = Panel(title: "FullPage", color: .red, interactions: interactions, isBuiltIn: false)
        try store.addPanel(p)
        XCTAssertFalse(store.canAddInteraction(to: p.id))
    }

    func testCanAddInteractionUnderSixIsTrue() throws {
        let p = Panel(title: "AlmostFull",
                      color: .red,
                      interactions: [Interaction(id: UUID(), name: "x")],
                      isBuiltIn: false)
        try store.addPanel(p)
        XCTAssertTrue(store.canAddInteraction(to: p.id))
    }

    // MARK: PIN + reset paths

    func testSetAndVerifyPIN() {
        XCTAssertFalse(store.hasPIN)
        store.setPIN("1234")
        XCTAssertTrue(store.hasPIN)
        XCTAssertTrue(store.verifyPIN("1234"))
        XCTAssertFalse(store.verifyPIN("0000"))
    }

    func testClearPINRemovesItAndAnyQuestion() {
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
        XCTAssertTrue(store.hasPIN)
        XCTAssertTrue(store.hasSecurityQuestion)
        store.clearPIN()
        XCTAssertFalse(store.hasPIN)
        XCTAssertFalse(store.hasSecurityQuestion)
    }

    func testResetPINViaICloudSucceedsWhenSignedIn() throws {
        store.setPIN("1234")
        iCloudSignedIn = true
        try store.resetPINViaICloudAccount()
        XCTAssertFalse(store.hasPIN)
    }

    func testResetPINViaICloudFailsWhenSignedOut() {
        store.setPIN("1234")
        iCloudSignedIn = false
        XCTAssertThrowsError(try store.resetPINViaICloudAccount()) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .iCloudUnavailable)
        }
        XCTAssertTrue(store.hasPIN)
    }

    func testResetPINViaSecurityAnswerSucceedsOnMatch() throws {
        store.setPIN("1234", securityQuestion: "Street?", securityAnswer: "Maple")
        try store.resetPIN(securityAnswer: "  maple  ")  // case + whitespace insensitive
        XCTAssertFalse(store.hasPIN)
    }

    func testResetPINViaSecurityAnswerFailsOnWrong() {
        store.setPIN("1234", securityQuestion: "Street?", securityAnswer: "Maple")
        XCTAssertThrowsError(try store.resetPIN(securityAnswer: "Oak")) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .incorrectAnswer)
        }
        XCTAssertTrue(store.hasPIN)
    }

    func testResetPINViaSecurityAnswerFailsWhenNoQuestionSet() {
        store.setPIN("1234")
        XCTAssertThrowsError(try store.resetPIN(securityAnswer: "anything")) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .noSecurityQuestionSet)
        }
    }

    // MARK: Stable IDs for built-ins

    func testStableIDIsDeterministic() {
        XCTAssertEqual(Interaction.stableID(for: "I feel"), Interaction.stableID(for: "I feel"))
        XCTAssertNotEqual(Interaction.stableID(for: "I feel"), Interaction.stableID(for: "I need"))
    }
}

// MARK: - ConfigurationMode

final class ConfigurationModeTests: XCTestCase {
    func testDefaultsToDefaultWhenUnset() {
        let suite = UserDefaults(suiteName: "ConfigurationModeTests-\(UUID().uuidString)")!
        XCTAssertEqual(ConfigurationMode.current(suite), .default)
    }

    func testReadsCustomFromUserDefaults() {
        let suite = UserDefaults(suiteName: "ConfigurationModeTests-\(UUID().uuidString)")!
        suite.set("custom", forKey: ConfigurationMode.userDefaultsKey)
        XCTAssertEqual(ConfigurationMode.current(suite), .custom)
    }

    func testFallsBackToDefaultOnGarbage() {
        let suite = UserDefaults(suiteName: "ConfigurationModeTests-\(UUID().uuidString)")!
        suite.set("nonsense", forKey: ConfigurationMode.userDefaultsKey)
        XCTAssertEqual(ConfigurationMode.current(suite), .default)
    }
}
