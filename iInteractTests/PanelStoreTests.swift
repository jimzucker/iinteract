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

    // MARK: savePanel (upsert)

    func testSavePanelInsertsThenUpdates() throws {
        let p = Panel(title: "School", color: .systemTeal, interactions: [], isBuiltIn: false)
        try store.savePanel(p)
        XCTAssertEqual(store.userPanels().count, 1)

        // Mutate and save again with the same id — should replace, not append.
        p.title = "School 2"
        p.interactions = [Interaction(id: UUID(), name: "playground")]
        try store.savePanel(p)
        XCTAssertEqual(store.userPanels().count, 1)
        XCTAssertEqual(store.userPanels().first?.title, "School 2")
        XCTAssertEqual(store.userPanels().first?.interactions.count, 1)
    }

    func testSavePanelLetsRenameStayUniqueWhenUsingExcludeSelf() throws {
        let p = Panel(title: "Original", color: .red, interactions: [], isBuiltIn: false)
        try store.savePanel(p)
        // Rename to a different unique value — should succeed, not collide with itself.
        p.title = "Renamed"
        XCTAssertNoThrow(try store.savePanel(p))
        XCTAssertEqual(store.userPanels().first?.title, "Renamed")
    }

    func testSavePanelRejectsRenameToBuiltIn() throws {
        let p = Panel(title: "MyPanel", color: .red, interactions: [], isBuiltIn: false)
        try store.savePanel(p)
        p.title = "I feel"  // collides with a built-in
        XCTAssertThrowsError(try store.savePanel(p)) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .nameNotUnique)
        }
    }

    // MARK: Hydration

    func testHydrateNoOpsForBuiltIn() {
        let builtIn = Interaction(interactionName: "happy")
        let originalPicture = builtIn.picture
        let originalBoy = builtIn.boySound
        store.hydrate(builtIn)
        // Built-ins keep their bundle assets — hydrate should leave them alone.
        XCTAssertNotNil(builtIn.picture)
        XCTAssertEqual(builtIn.picture, originalPicture)
        XCTAssertEqual(builtIn.boySound, originalBoy)
    }

    func testHydrateAttachesPictureAndAudioFromAssetsDirectory() throws {
        let interaction = Interaction(id: UUID(), name: "playground")
        // Picture starts unset.
        XCTAssertNil(interaction.picture)
        XCTAssertNil(interaction.boySound)
        XCTAssertNil(interaction.girlSound)

        // Write a real JPEG and two stub audio files at the expected paths.
        let img = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 16, height: 16)))
        }
        try store.saveInteractionPicture(img, id: interaction.id)
        try Data([0x00]).write(to: store.assetURL(for: interaction.id, kind: .boyAudio))
        try Data([0x00]).write(to: store.assetURL(for: interaction.id, kind: .girlAudio))

        store.hydrate(interaction)
        XCTAssertNotNil(interaction.picture)
        XCTAssertEqual(interaction.boySound, store.assetURL(for: interaction.id, kind: .boyAudio))
        XCTAssertEqual(interaction.girlSound, store.assetURL(for: interaction.id, kind: .girlAudio))
    }

    func testDeleteInteractionAssetsRemovesFiles() throws {
        let id = UUID()
        try Data([0x00]).write(to: store.assetURL(for: id, kind: .picture))
        try Data([0x00]).write(to: store.assetURL(for: id, kind: .boyAudio))
        try Data([0x00]).write(to: store.assetURL(for: id, kind: .girlAudio))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(for: id, kind: .picture).path))
        store.deleteInteractionAssets(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetURL(for: id, kind: .picture).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetURL(for: id, kind: .boyAudio).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetURL(for: id, kind: .girlAudio).path))
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

    // MARK: applyOrder / applyHiddenFilter

    func testApplyOrderAloneDoesNotFilterHidden() throws {
        let p1 = Panel(title: "A", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "B", color: .green, interactions: [], isBuiltIn: false)
        try store.setHidden(true, for: p1.id)
        try store.setOrder([p2.id, p1.id])
        // applyOrder keeps p1 even though it's hidden — the editor needs this.
        XCTAssertEqual(store.applyOrder(to: [p1, p2]).map { $0.title }, ["B", "A"])
    }

    func testApplyHiddenFilterAloneDoesNotReorder() throws {
        let p1 = Panel(title: "A", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "B", color: .green, interactions: [], isBuiltIn: false)
        try store.setHidden(true, for: p2.id)
        try store.setOrder([p2.id, p1.id])
        // applyHiddenFilter drops p2 but doesn't reorder the rest.
        XCTAssertEqual(store.applyHiddenFilter(to: [p1, p2]).map { $0.title }, ["A"])
    }

    // MARK: Mode-aware loading

    func testLoadDefaultModeReturnsBundledPanelsVerbatim() {
        let direct = Panel.readFromPlist()
        let viaLoad = Panel.load(mode: .default, store: store)
        XCTAssertEqual(viaLoad.count, direct.count)
        XCTAssertEqual(viaLoad.map { $0.title }, direct.map { $0.title })
        XCTAssertTrue(viaLoad.allSatisfy { $0.isBuiltIn })
    }

    func testLoadCustomModeWithEmptyStoreReturnsAllBuiltIns() {
        let viaLoad = Panel.load(mode: .custom, store: store)
        let direct = Panel.readFromPlist()
        XCTAssertEqual(viaLoad.map { $0.title }, direct.map { $0.title })
    }

    func testLoadCustomModeMergesUserPanelsAfterBuiltIns() throws {
        let userPanel = Panel(title: "School", color: .systemTeal, interactions: [], isBuiltIn: false)
        try store.addPanel(userPanel)
        let result = Panel.load(mode: .custom, store: store)
        XCTAssertEqual(result.last?.title, "School")
        XCTAssertEqual(result.count, Panel.readFromPlist().count + 1)
    }

    func testLoadCustomModeAppliesHiddenAndOrder() throws {
        let builtIns = Panel.readFromPlist()
        guard let first = builtIns.first, let second = builtIns.dropFirst().first else {
            XCTFail("Expected at least 2 built-in panels"); return
        }
        try store.setHidden(true, for: first.id)
        try store.setOrder([second.id])
        let result = Panel.load(mode: .custom, store: store)
        XCTAssertFalse(result.contains { $0.id == first.id })
        XCTAssertEqual(result.first?.id, second.id)
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
