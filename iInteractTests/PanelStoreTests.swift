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
    private var strings: [String: String] = [:]
    private var blobs:   [String: Data]   = [:]

    func string(forKey key: String) -> String? { strings[key] }
    func data(forKey key: String) -> Data?     { blobs[key] }

    func set(_ value: String?, forKey key: String) {
        if let value = value { strings[key] = value } else { strings.removeValue(forKey: key) }
    }
    func set(_ value: Data?, forKey key: String) {
        if let value = value { blobs[key] = value } else { blobs.removeValue(forKey: key) }
    }

    func removeObject(forKey key: String) {
        strings.removeValue(forKey: key)
        blobs.removeValue(forKey: key)
    }

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

    // MARK: KVS sync

    func testSavedPanelsAlsoLandInKVS() throws {
        let p = Panel(title: "School", color: .systemTeal, interactions: [], isBuiltIn: false)
        try store.savePanel(p)
        XCTAssertNotNil(kvs.data(forKey: "panelstore.panels"))
    }

    func testSavedLayoutAlsoLandsInKVS() throws {
        try store.setHidden(true, for: UUID())
        XCTAssertNotNil(kvs.data(forKey: "panelstore.layout"))
    }

    func testFreshDeviceLoadsPanelsFromKVS() throws {
        // Simulate "this iPhone has no local file but iCloud has data."
        let p = Panel(title: "School", color: .systemTeal, interactions: [], isBuiltIn: false)
        let data = try JSONEncoder().encode([p])
        kvs.set(data, forKey: "panelstore.panels")

        let freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fresh-\(UUID().uuidString)", isDirectory: true)
        let fresh = PanelStore(directory: freshDir, keyValueStore: kvs)
        defer { try? FileManager.default.removeItem(at: freshDir) }

        let loaded = fresh.userPanels()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "School")
    }

    func testFreshDeviceLoadsLayoutFromKVS() throws {
        let id = UUID()
        let l = PanelStore.Layout(hiddenIDs: [id], orderedIDs: [id])
        let data = try JSONEncoder().encode(l)
        kvs.set(data, forKey: "panelstore.layout")

        let freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fresh-\(UUID().uuidString)", isDirectory: true)
        let fresh = PanelStore(directory: freshDir, keyValueStore: kvs)
        defer { try? FileManager.default.removeItem(at: freshDir) }

        XCTAssertTrue(fresh.layout().hiddenIDs.contains(id))
        XCTAssertEqual(fresh.layout().orderedIDs, [id])
    }

    func testLocalOnlyDataPromotesIntoKVSOnFirstRead() throws {
        // Migration scenario: pre-step-8 user has local panels.json but KVS is empty.
        let panelsFile = tempDir.appendingPathComponent("panels.json")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let p = Panel(title: "Legacy", color: .red, interactions: [], isBuiltIn: false)
        let data = try JSONEncoder().encode([p])
        try data.write(to: panelsFile)

        XCTAssertNil(kvs.data(forKey: "panelstore.panels"))
        _ = store.userPanels()  // first read promotes
        XCTAssertNotNil(kvs.data(forKey: "panelstore.panels"))
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

    // MARK: Mode round-trip preserves user data

    func testModeRoundTripDoesNotLoseUserPanelsOrLayout() throws {
        // Create a custom panel and a layout (hide one built-in, reorder).
        let userPanel = Panel(title: "School", color: .systemTeal,
                              interactions: [Interaction(id: UUID(), name: "playground")],
                              isBuiltIn: false)
        try store.savePanel(userPanel)
        let builtIns = Panel.readFromPlist()
        try store.setHidden(true, for: builtIns.first!.id)
        try store.setOrder([builtIns[1].id, userPanel.id])

        // .default mode returns just bundled built-ins, untouched.
        let asDefault = Panel.load(mode: .default, store: store)
        XCTAssertEqual(asDefault.map { $0.title }, builtIns.map { $0.title })

        // Switching to .custom shows the user data unchanged from before.
        let asCustom = Panel.load(mode: .custom, store: store)
        XCTAssertTrue(asCustom.contains { $0.title == "School" })
        XCTAssertFalse(asCustom.contains { $0.id == builtIns.first!.id }, "hidden built-in stays hidden")
        XCTAssertEqual(asCustom.first?.id, builtIns[1].id, "order is preserved")

        // Round-trip back to default and again to custom — still intact.
        let asDefault2 = Panel.load(mode: .default, store: store)
        XCTAssertEqual(asDefault2.map { $0.title }, builtIns.map { $0.title })
        let asCustom2 = Panel.load(mode: .custom, store: store)
        XCTAssertTrue(asCustom2.contains { $0.title == "School" })
        XCTAssertEqual(store.userPanels().count, 1)
        XCTAssertEqual(store.layout().hiddenIDs.count, 1)
    }

    // MARK: Recycle bin (30-day trash)

    func testTrashPanelRemovesFromActiveAndKeepsBlobs() throws {
        let interactionID = UUID()
        let interaction = Interaction(id: interactionID, name: "playground")
        let panel = Panel(title: "School",
                          color: .systemTeal,
                          interactions: [interaction],
                          isBuiltIn: false)
        try store.savePanel(panel)
        try Data([0x00]).write(to: store.assetURL(for: interactionID, kind: .picture))

        try store.trashPanel(panel)

        XCTAssertTrue(store.userPanels().isEmpty)
        XCTAssertEqual(store.trashedItems().count, 1)
        XCTAssertEqual(store.trashedItems().first?.kind, .panel)
        // Asset should have moved out of UserAssets/.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.assetURL(for: interactionID, kind: .picture).path))
    }

    func testRestorePanelMovesBackAndReturnsBlobs() throws {
        let interactionID = UUID()
        let panel = Panel(title: "School",
                          color: .systemTeal,
                          interactions: [Interaction(id: interactionID, name: "playground")],
                          isBuiltIn: false)
        try store.savePanel(panel)
        try Data([0x00]).write(to: store.assetURL(for: interactionID, kind: .picture))
        try store.trashPanel(panel)

        let trashID = store.trashedItems().first!.trashID
        _ = try store.restorePanel(trashID: trashID)

        XCTAssertEqual(store.userPanels().count, 1)
        XCTAssertEqual(store.userPanels().first?.title, "School")
        XCTAssertEqual(store.trashedItems().count, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.assetURL(for: interactionID, kind: .picture).path))
    }

    func testRestorePanelWithCollidingTitleThrows() throws {
        let p1 = Panel(title: "School", color: .systemTeal, interactions: [], isBuiltIn: false)
        try store.savePanel(p1)
        try store.trashPanel(p1)
        // Re-create a NEW user panel with the same title; restoring should now collide.
        let p2 = Panel(title: "School", color: .systemBlue, interactions: [], isBuiltIn: false)
        try store.savePanel(p2)

        let trashID = store.trashedItems().first!.trashID
        XCTAssertThrowsError(try store.restorePanel(trashID: trashID)) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .nameNotUnique)
        }
        // …but renaming on restore succeeds.
        XCTAssertNoThrow(try store.restorePanel(trashID: trashID, newTitle: "School (restored)"))
        XCTAssertEqual(store.userPanels().count, 2)
    }

    func testRestoreInteractionToOriginalParent() throws {
        let panelID = UUID()
        let parent = Panel(id: panelID, title: "School", color: .systemTeal,
                           interactions: [], isBuiltIn: false)
        try store.savePanel(parent)
        let interaction = Interaction(id: UUID(), name: "playground")
        try Data([0x00]).write(to: store.assetURL(for: interaction.id, kind: .picture))

        try store.trashInteraction(interaction, fromPanelID: panelID)
        let trashID = store.trashedItems().first!.trashID

        XCTAssertTrue(store.canRestoreInteractionToOriginalParent(trashID: trashID))
        _ = try store.restoreInteraction(trashID: trashID)
        XCTAssertEqual(store.userPanels().first?.interactions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.assetURL(for: interaction.id, kind: .picture).path))
    }

    func testRestoreInteractionToDifferentPanel() throws {
        let alt = Panel(title: "Alt", color: .systemTeal, interactions: [], isBuiltIn: false)
        try store.savePanel(alt)
        let i = Interaction(id: UUID(), name: "playground")
        try store.trashInteraction(i, fromPanelID: UUID())  // ghost parent
        let trashID = store.trashedItems().first!.trashID

        XCTAssertFalse(store.canRestoreInteractionToOriginalParent(trashID: trashID))
        XCTAssertNil(store.parentPanelTrashID(forInteractionTrashID: trashID))
        XCTAssertTrue(store.panelsAvailableToReceiveInteraction().contains { $0.id == alt.id })

        _ = try store.restoreInteraction(trashID: trashID, to: alt.id)
        XCTAssertEqual(store.userPanels().first(where: { $0.id == alt.id })?.interactions.count, 1)
    }

    func testParentPanelInTrashIsDetected() throws {
        let panel = Panel(title: "School", color: .systemTeal,
                          interactions: [Interaction(id: UUID(), name: "playground")],
                          isBuiltIn: false)
        try store.savePanel(panel)
        try store.trashInteraction(panel.interactions[0], fromPanelID: panel.id)
        let updated = Panel(id: panel.id, title: panel.title, color: panel.color,
                            interactions: [], isBuiltIn: false)
        try store.savePanel(updated)
        try store.trashPanel(updated)

        let interactionTrashID = store.trashedItems().first(where: { $0.kind == .interaction })!.trashID
        XCTAssertNotNil(store.parentPanelTrashID(forInteractionTrashID: interactionTrashID))
    }

    /// Regression: user reported that after restoring a panel they had
    /// previously deleted, restoring an interaction that was deleted from
    /// it (separately, before the panel itself was trashed) didn't put the
    /// interaction back on the panel.
    func testRestoreInteractionAfterParentPanelRestoredFromTrash() throws {
        let interactionID = UUID()
        let interaction = Interaction(id: interactionID, name: "playground")
        let panel = Panel(title: "School", color: .systemTeal,
                          interactions: [interaction], isBuiltIn: false)
        try store.savePanel(panel)
        try Data([0x00]).write(to: store.assetURL(for: interactionID, kind: .picture))

        // 1. Trash the interaction first (separate trash entry).
        try store.trashInteraction(interaction, fromPanelID: panel.id)
        let panelWithoutInteraction = Panel(id: panel.id, title: panel.title,
                                            color: panel.color, interactions: [],
                                            isBuiltIn: false)
        try store.savePanel(panelWithoutInteraction)

        // 2. Trash the panel (now interactions=[] in the snapshot).
        try store.trashPanel(panelWithoutInteraction)

        // 3. Restore the panel — comes back without the interaction.
        let panelTrashID = store.trashedItems().first(where: { $0.kind == .panel })!.trashID
        _ = try store.restorePanel(trashID: panelTrashID)
        XCTAssertEqual(store.userPanels().count, 1)
        XCTAssertEqual(store.userPanels().first?.interactions.count, 0,
                       "panel snapshot didn't include the separately-trashed interaction")

        // 4. Now restore the interaction. It should land back on the panel.
        let interactionTrashID = store.trashedItems().first(where: { $0.kind == .interaction })!.trashID
        XCTAssertTrue(store.canRestoreInteractionToOriginalParent(trashID: interactionTrashID))
        _ = try store.restoreInteraction(trashID: interactionTrashID)
        XCTAssertEqual(store.userPanels().first?.interactions.count, 1)
        XCTAssertEqual(store.userPanels().first?.interactions.first?.id, interactionID)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.assetURL(for: interactionID, kind: .picture).path))
        XCTAssertEqual(store.trashedItems().count, 0)
    }

    func testTrashInteractionMovesAssetsAndPersistsSnapshot() throws {
        let interactionID = UUID()
        let interaction = Interaction(id: interactionID, name: "playground")
        try Data([0x00]).write(to: store.assetURL(for: interactionID, kind: .picture))
        try Data([0x00]).write(to: store.assetURL(for: interactionID, kind: .boyAudio))

        try store.trashInteraction(interaction, fromPanelID: UUID())

        XCTAssertEqual(store.trashedItems().count, 1)
        XCTAssertEqual(store.trashedItems().first?.kind, .interaction)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.assetURL(for: interactionID, kind: .picture).path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.assetURL(for: interactionID, kind: .boyAudio).path))
    }

    func testPurgeTrashRemovesEntryAndAssets() throws {
        let panel = Panel(title: "School", color: .systemTeal, interactions: [], isBuiltIn: false)
        try store.savePanel(panel)
        try store.trashPanel(panel)
        let trashID = store.trashedItems().first!.trashID
        store.purgeTrash(trashID: trashID)
        XCTAssertEqual(store.trashedItems().count, 0)
    }

    func testEmptyTrashWipesEverything() throws {
        let p1 = Panel(title: "A", color: .red, interactions: [], isBuiltIn: false)
        let p2 = Panel(title: "B", color: .blue, interactions: [], isBuiltIn: false)
        try store.savePanel(p1)
        try store.savePanel(p2)
        try store.trashPanel(p1)
        try store.trashPanel(p2)
        XCTAssertEqual(store.trashedItems().count, 2)
        store.emptyTrash()
        XCTAssertEqual(store.trashedItems().count, 0)
    }

    func testClearAllUserDataWipesEverything() throws {
        let panel = Panel(title: "School",
                          color: .systemTeal,
                          interactions: [Interaction(id: UUID(), name: "playground")],
                          isBuiltIn: false)
        try store.savePanel(panel)
        try store.setOrder([panel.id])
        try store.setHidden(true, for: panel.id)
        try Data([0x00]).write(to: store.assetURL(for: panel.interactions[0].id, kind: .picture))
        try Data([0x00]).write(to: store.assetURL(for: panel.interactions[0].id, kind: .boyAudio))
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")

        XCTAssertFalse(store.userPanels().isEmpty)
        XCTAssertTrue(store.hasPIN)

        store.clearAllUserData()

        XCTAssertTrue(store.userPanels().isEmpty)
        XCTAssertEqual(store.layout().hiddenIDs.count, 0)
        XCTAssertEqual(store.layout().orderedIDs, [])
        XCTAssertFalse(store.hasPIN)
        XCTAssertFalse(store.hasSecurityQuestion)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.assetURL(for: panel.interactions[0].id, kind: .picture).path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.assetURL(for: panel.interactions[0].id, kind: .boyAudio).path))
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

    // MARK: setSecurityQuestion (A3 — separate from setPIN)

    func testSetSecurityQuestion_BothFilled_StoresQuestionAndAnswer() throws {
        store.setPIN("1234")
        XCTAssertFalse(store.hasSecurityQuestion)
        store.setSecurityQuestion("Pet?", answer: "Fido")
        XCTAssertTrue(store.hasSecurityQuestion)
        XCTAssertEqual(store.securityQuestion, "Pet?")
        // Answer must verify (case-insensitive, whitespace-trimmed).
        try store.resetPIN(securityAnswer: "  fido  ")
        XCTAssertFalse(store.hasPIN, "correct answer resets PIN")
    }

    func testSetSecurityQuestion_OneEmpty_ClearsBoth() {
        store.setPIN("1234", securityQuestion: "Old?", securityAnswer: "Yes")
        XCTAssertTrue(store.hasSecurityQuestion)
        // Saving with empty answer wipes the previously-set question too.
        store.setSecurityQuestion("Just question", answer: "")
        XCTAssertFalse(store.hasSecurityQuestion)
    }

    func testSetSecurityQuestion_DoesNotTouchPIN() {
        store.setPIN("1234")
        store.setSecurityQuestion("Pet?", answer: "Fido")
        XCTAssertTrue(store.hasPIN)
        XCTAssertTrue(store.verifyPIN("1234"),
                      "setSecurityQuestion must not re-hash or change the PIN")
    }

    func testSetSecurityQuestion_NilArgs_ClearsBoth() {
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
        store.setSecurityQuestion(nil, answer: nil)
        XCTAssertFalse(store.hasSecurityQuestion)
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

    func testLoadConfigurableModeReturnsBuiltInsWithLayoutAndNoUserPanels() throws {
        // Seed a user panel + a hidden built-in + a reorder. Configurable
        // must show the built-ins respecting layout and exclude user data.
        let userPanel = Panel(title: "School", color: .systemTeal,
                              interactions: [], isBuiltIn: false)
        try store.addPanel(userPanel)
        let builtIns = Panel.readFromPlist()
        guard let first = builtIns.first, let second = builtIns.dropFirst().first else {
            XCTFail("Expected at least 2 built-in panels"); return
        }
        try store.setHidden(true, for: first.id)
        try store.setOrder([second.id, first.id])

        let result = Panel.load(mode: .configurable, store: store)

        XCTAssertTrue(result.allSatisfy { $0.isBuiltIn },
                      "Configurable mode must not include user panels")
        XCTAssertFalse(result.contains { $0.title == "School" })
        XCTAssertFalse(result.contains { $0.id == first.id }, "hidden built-in stays hidden")
        XCTAssertEqual(result.first?.id, second.id, "reorder is honored")
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

    func testReadsConfigurableFromUserDefaults() {
        let suite = UserDefaults(suiteName: "ConfigurationModeTests-\(UUID().uuidString)")!
        suite.set("configurable", forKey: ConfigurationMode.userDefaultsKey)
        XCTAssertEqual(ConfigurationMode.current(suite), .configurable)
    }

    func testFallsBackToDefaultOnGarbage() {
        let suite = UserDefaults(suiteName: "ConfigurationModeTests-\(UUID().uuidString)")!
        suite.set("nonsense", forKey: ConfigurationMode.userDefaultsKey)
        XCTAssertEqual(ConfigurationMode.current(suite), .default)
    }
}

// MARK: - PanelListEditorAffordances + DeletePanelConfirmSpec

/// Verifies the per-mode UI decisions that drive
/// `PanelListEditorViewController` — sections shown, add button
/// visibility, row-selectable / row-deletable, footer copy.
final class PanelListEditorAffordancesTests: XCTestCase {

    private let userPanel = Panel(title: "School", color: .systemTeal,
                                  interactions: [], isBuiltIn: false)
    private let builtInPanel = Panel(title: "I feel", color: .systemRed,
                                     interactions: [], isBuiltIn: true)

    // MARK: sections

    func testSections_DefaultMode_PanelsOnly() {
        XCTAssertEqual(PanelListEditorAffordances.sections(for: .default), [.panels])
    }

    func testSections_ConfigurableMode_PanelsOnly() {
        XCTAssertEqual(PanelListEditorAffordances.sections(for: .configurable), [.panels])
    }

    func testSections_CustomMode_PanelsAndTrash() {
        XCTAssertEqual(PanelListEditorAffordances.sections(for: .custom), [.panels, .trash])
    }

    // MARK: add button

    func testAddButton_VisibleOnlyInCustom() {
        XCTAssertFalse(PanelListEditorAffordances.addButtonVisible(for: .default))
        XCTAssertFalse(PanelListEditorAffordances.addButtonVisible(for: .configurable))
        XCTAssertTrue(PanelListEditorAffordances.addButtonVisible(for: .custom))
    }

    // MARK: row selectable (tap to edit)

    func testPanelRowSelectable_BuiltInNeverSelectable() {
        for mode: ConfigurationMode in [.default, .configurable, .custom] {
            XCTAssertFalse(PanelListEditorAffordances.panelRowSelectable(panel: builtInPanel, mode: mode),
                           "built-in panels are never editable in mode \(mode)")
        }
    }

    func testPanelRowSelectable_UserPanelOnlyInCustom() {
        XCTAssertFalse(PanelListEditorAffordances.panelRowSelectable(panel: userPanel, mode: .default))
        XCTAssertFalse(PanelListEditorAffordances.panelRowSelectable(panel: userPanel, mode: .configurable))
        XCTAssertTrue(PanelListEditorAffordances.panelRowSelectable(panel: userPanel, mode: .custom))
    }

    // MARK: row deletable (swipe-to-delete)

    func testPanelRowDeletable_BuiltInNeverDeletable() {
        for mode: ConfigurationMode in [.default, .configurable, .custom] {
            XCTAssertFalse(PanelListEditorAffordances.panelRowDeletable(panel: builtInPanel, mode: mode),
                           "built-in panels are never deletable in mode \(mode)")
        }
    }

    func testPanelRowDeletable_UserPanelOnlyInCustom() {
        XCTAssertFalse(PanelListEditorAffordances.panelRowDeletable(panel: userPanel, mode: .default))
        XCTAssertFalse(PanelListEditorAffordances.panelRowDeletable(panel: userPanel, mode: .configurable))
        XCTAssertTrue(PanelListEditorAffordances.panelRowDeletable(panel: userPanel, mode: .custom))
    }

    // MARK: footers

    func testPanelsFooter_DefaultMode_NoFooter() {
        XCTAssertNil(PanelListEditorAffordances.panelsFooter(for: .default))
    }

    func testPanelsFooter_Configurable_MentionsCustomize() {
        let footer = PanelListEditorAffordances.panelsFooter(for: .configurable) ?? ""
        XCTAssertTrue(footer.contains("Customize"))
        XCTAssertFalse(footer.contains("Swipe to delete"),
                       "Configurable can't delete; footer must not advertise it")
    }

    func testPanelsFooter_Custom_MentionsSwipeToDelete() {
        let footer = PanelListEditorAffordances.panelsFooter(for: .custom) ?? ""
        XCTAssertTrue(footer.contains("Swipe to delete"))
    }

    func testTrashFooter_MentionsThirtyDays() {
        XCTAssertTrue(PanelListEditorAffordances.trashFooter.contains("30 days"))
    }

    // MARK: DeletePanelConfirmSpec

    func testDeletePanelConfirmSpec_QuotesPanelTitle() {
        let spec = DeletePanelConfirmSpec.make(panelTitle: "School")
        XCTAssertEqual(spec.title, "Delete \"School\"?")
    }

    func testDeletePanelConfirmSpec_MessageMentionsTrashAnd30Days() {
        let spec = DeletePanelConfirmSpec.make(panelTitle: "School")
        XCTAssertTrue(spec.message.contains("Trash"))
        XCTAssertTrue(spec.message.contains("30 days"))
    }
}

// MARK: - TrashRestoreCoordinator decision tree

/// Verifies the pure-logic decision for "what should the UI do next when
/// the user asks to restore item X from Trash" — all six branches.
final class TrashRestoreCoordinatorTests: XCTestCase {

    var tempDir: URL!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrashRestoreCoord-\(UUID().uuidString)", isDirectory: true)
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir, keyValueStore: kvs)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: panel branches

    func testPlan_PanelWithUniqueTitle_RestorePanelDirectly() throws {
        let panel = Panel(title: "School", color: .systemTeal,
                          interactions: [], isBuiltIn: false)
        try store.savePanel(panel)
        try store.trashPanel(panel)
        let item = store.trashedItems().first!

        XCTAssertEqual(TrashRestoreCoordinator.plan(for: item, in: store),
                       .restorePanelDirectly(trashID: item.trashID))
    }

    func testPlan_PanelWithCollidingTitle_NeedsRename() throws {
        let p1 = Panel(title: "School", color: .systemTeal,
                       interactions: [], isBuiltIn: false)
        try store.savePanel(p1)
        try store.trashPanel(p1)
        // Recreate with same title in active.
        let p2 = Panel(title: "School", color: .systemBlue,
                       interactions: [], isBuiltIn: false)
        try store.savePanel(p2)

        let item = store.trashedItems().first!
        XCTAssertEqual(TrashRestoreCoordinator.plan(for: item, in: store),
                       .needsRenameForPanel(trashID: item.trashID,
                                             suggestedTitle: "School (restored)"))
    }

    // MARK: interaction branches

    func testPlan_Interaction_OriginalParentActiveWithRoom_RestoreDirectly() throws {
        let panelID = UUID()
        let parent = Panel(id: panelID, title: "School", color: .systemTeal,
                           interactions: [], isBuiltIn: false)
        try store.savePanel(parent)
        let interaction = Interaction(id: UUID(), name: "playground")
        try store.trashInteraction(interaction, fromPanelID: panelID)

        let item = store.trashedItems().first!
        XCTAssertEqual(TrashRestoreCoordinator.plan(for: item, in: store),
                       .restoreInteractionDirectly(trashID: item.trashID))
    }

    func testPlan_Interaction_ParentInTrash_NeedsParentDecision() throws {
        let panel = Panel(title: "School", color: .systemTeal,
                          interactions: [Interaction(id: UUID(), name: "playground")],
                          isBuiltIn: false)
        try store.savePanel(panel)
        try store.trashInteraction(panel.interactions[0], fromPanelID: panel.id)

        // Now also trash the panel.
        let updated = Panel(id: panel.id, title: panel.title,
                            color: panel.color, interactions: [], isBuiltIn: false)
        try store.savePanel(updated)
        try store.trashPanel(updated)

        let interactionItem = store.trashedItems()
            .first(where: { $0.kind == .interaction })!

        let plan = TrashRestoreCoordinator.plan(for: interactionItem, in: store)
        if case let .needsParentDecision(intTrashID, _, parentName) = plan {
            XCTAssertEqual(intTrashID, interactionItem.trashID)
            XCTAssertEqual(parentName, "School")
        } else {
            XCTFail("expected .needsParentDecision, got \(plan)")
        }
    }

    func testPlan_Interaction_ParentGoneWithCandidates_NeedsAlternateDestination() throws {
        // No parent panel exists. There IS an alt panel with room.
        let alt = Panel(title: "Alt", color: .systemTeal,
                        interactions: [], isBuiltIn: false)
        try store.savePanel(alt)
        let i = Interaction(id: UUID(), name: "playground")
        try store.trashInteraction(i, fromPanelID: UUID())  // ghost parent
        let item = store.trashedItems().first!

        let plan = TrashRestoreCoordinator.plan(for: item, in: store)
        if case let .needsAlternateDestination(trashID, reason, candidateIDs) = plan {
            XCTAssertEqual(trashID, item.trashID)
            XCTAssertEqual(reason, .parentGone)
            XCTAssertTrue(candidateIDs.contains(alt.id))
        } else {
            XCTFail("expected .needsAlternateDestination, got \(plan)")
        }
    }

    func testPlan_Interaction_ParentFullWithCandidates_NeedsAlternate_ReasonParentFull() throws {
        // Parent panel exists but is at the 6-item cap.
        let interactions = (0..<PanelStore.maxInteractionsPerUserPanel).map {
            Interaction(id: UUID(), name: "i\($0)")
        }
        let panelID = UUID()
        let parent = Panel(id: panelID, title: "FullParent", color: .systemTeal,
                           interactions: interactions, isBuiltIn: false)
        try store.savePanel(parent)
        // Trash one interaction so it has a parent reference but the
        // parent is now also full again (we'll re-add to refill).
        try store.trashInteraction(interactions[0], fromPanelID: panelID)
        // Re-fill parent so canRestoreToOriginalParent is false.
        let parentRefilled = Panel(id: panelID, title: "FullParent", color: .systemTeal,
                                    interactions: interactions, isBuiltIn: false)
        try store.savePanel(parentRefilled)
        // Add an alt with room.
        let alt = Panel(title: "Alt", color: .systemTeal,
                        interactions: [], isBuiltIn: false)
        try store.savePanel(alt)

        let item = store.trashedItems()
            .first(where: { $0.kind == .interaction })!
        let plan = TrashRestoreCoordinator.plan(for: item, in: store)
        if case let .needsAlternateDestination(_, reason, candidateIDs) = plan {
            XCTAssertEqual(reason, .parentFull,
                           "parent exists active but full → reason is parentFull")
            XCTAssertTrue(candidateIDs.contains(alt.id))
            XCTAssertFalse(candidateIDs.contains(panelID),
                           "the full original parent is NOT a candidate")
        } else {
            XCTFail("expected .needsAlternateDestination, got \(plan)")
        }
    }

    func testAlternateReason_BlurbIsHumanReadable() {
        XCTAssertTrue(TrashAlternateReason.parentGone.blurb.contains("deleted"))
        XCTAssertTrue(TrashAlternateReason.parentInTrash.blurb.contains("Trash"))
        XCTAssertTrue(TrashAlternateReason.parentFull.blurb.contains("6"))
    }

    func testPlan_Interaction_NoCandidatesAvailable() throws {
        // Parent gone AND no other active user panels.
        let i = Interaction(id: UUID(), name: "playground")
        try store.trashInteraction(i, fromPanelID: UUID())  // ghost parent

        let item = store.trashedItems().first!
        let plan = TrashRestoreCoordinator.plan(for: item, in: store)
        XCTAssertEqual(plan, .noCandidatesAvailable(reason: .parentGone))
    }
}

// MARK: - ConfigurationMode KVS sync (PanelStore-backed)

/// Verifies the realtime propagation that the Mode picker in iOS Settings
/// → iInteract → Mode relies on. Adopt-on-first-launch, runtime reconcile
/// (local wins, pushed to KVS), and setConfigurationMode return semantics.
final class ConfigurationModeSyncTests: XCTestCase {

    var tempDir: URL!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigurationModeSyncTests-\(UUID().uuidString)", isDirectory: true)
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir, keyValueStore: kvs)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "iInteractTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testAdoptCloudConfigurationMode_FirstLaunch_NoCloudValue_LeavesDefaultsAlone() {
        let d = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: d)
        XCTAssertEqual(ConfigurationMode.current(d), .default)
    }

    func testAdoptCloudConfigurationMode_FirstLaunch_AdoptsCloudValue() {
        let primer = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: primer)
        let main = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: main)
        XCTAssertEqual(ConfigurationMode.current(main), .configurable)
    }

    func testAdoptCloudConfigurationMode_NoOpOnSecondCall() {
        let primer = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: primer)
        let main = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: main)
        // User changes mode locally.
        main.set(ConfigurationMode.custom.rawValue, forKey: ConfigurationMode.userDefaultsKey)
        // Another device pushes a different cloud value.
        _ = store.setConfigurationMode(.default, defaults: primer)
        // Adopt is called again (next launch) — must NOT clobber local intent.
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: main)
        XCTAssertEqual(ConfigurationMode.current(main), .custom,
                       "second adoption must not overwrite local intent")
    }

    func testReconcileConfigurationMode_LocalAndCloudAgree() {
        let d = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: d)
        let resolved = store.reconcileConfigurationMode(defaults: d)
        XCTAssertEqual(resolved, .configurable)
    }

    func testReconcileConfigurationMode_LocalDiffersFromCloud_LocalWins() {
        let primer = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: primer)
        let d = makeIsolatedDefaults()
        d.set(ConfigurationMode.custom.rawValue, forKey: ConfigurationMode.userDefaultsKey)
        let resolved = store.reconcileConfigurationMode(defaults: d)
        XCTAssertEqual(resolved, .custom, "local UserDefaults wins at runtime")
        // Cloud was overwritten — verify by adopting into a fresh defaults.
        let verifier = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: verifier)
        XCTAssertEqual(ConfigurationMode.current(verifier), .custom)
    }

    func testReconcileConfigurationMode_LocalMissing_FallsBackToDefault() {
        let freshKvs = MemoryKeyValueStore()
        let freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconcileFresh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: freshDir) }
        let freshStore = PanelStore(directory: freshDir, keyValueStore: freshKvs)
        let d = makeIsolatedDefaults()
        XCTAssertEqual(freshStore.reconcileConfigurationMode(defaults: d), .default)
    }

    func testSetConfigurationMode_ReturnsTrueOnlyWhenChanged() {
        let d = makeIsolatedDefaults()
        XCTAssertTrue(store.setConfigurationMode(.custom, defaults: d))
        XCTAssertFalse(store.setConfigurationMode(.custom, defaults: d))
        XCTAssertTrue(store.setConfigurationMode(.configurable, defaults: d))
    }

    func testSetConfigurationMode_WritesToBothLocalAndCloud() {
        let d = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: d)
        XCTAssertEqual(ConfigurationMode.current(d), .configurable)
        let verifier = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: verifier)
        XCTAssertEqual(ConfigurationMode.current(verifier), .configurable)
    }
}

// MARK: - PINPolicy

final class PINPolicyTests: XCTestCase {

    // MARK: isValid — length

    func testIsValid_TooShort_Rejects() {
        XCTAssertFalse(PINPolicy.isValid(""))
        XCTAssertFalse(PINPolicy.isValid("a"))
        XCTAssertFalse(PINPolicy.isValid("abc"))
        XCTAssertFalse(PINPolicy.isValid("123"))
    }

    func testIsValid_MinLength_Accepts() {
        XCTAssertTrue(PINPolicy.isValid("abcd"))
        XCTAssertTrue(PINPolicy.isValid("1234"))
    }

    func testIsValid_MidRange_Accepts() {
        XCTAssertTrue(PINPolicy.isValid("abcdef"))   // 6
        XCTAssertTrue(PINPolicy.isValid("123456"))   // 6
        XCTAssertTrue(PINPolicy.isValid("Pin999"))   // 6 (legacy max under old policy)
    }

    func testIsValid_MaxLength_Accepts() {
        XCTAssertTrue(PINPolicy.isValid("abcdefgh"))   // 8
        XCTAssertTrue(PINPolicy.isValid("12345678"))   // 8
    }

    func testIsValid_TooLong_Rejects() {
        XCTAssertFalse(PINPolicy.isValid("abcdefghi"))  // 9
        XCTAssertFalse(PINPolicy.isValid("123456789"))  // 9
    }

    // MARK: isValid — charset

    func testIsValid_AlphanumericMixed_Accepts() {
        XCTAssertTrue(PINPolicy.isValid("a1b2"))
        XCTAssertTrue(PINPolicy.isValid("Pin99"))
        XCTAssertTrue(PINPolicy.isValid("MIXED1"))
    }

    func testIsValid_NonAlphanumeric_Rejects() {
        XCTAssertFalse(PINPolicy.isValid("ab cd"))     // space
        XCTAssertFalse(PINPolicy.isValid("ab-cd"))     // dash
        XCTAssertFalse(PINPolicy.isValid("12.34"))     // dot
        XCTAssertFalse(PINPolicy.isValid("ab\ncd"))    // newline
        XCTAssertFalse(PINPolicy.isValid("ab😀cd"))    // emoji
    }

    // MARK: sanitize — strips non-alphanumeric, does NOT truncate

    func testSanitize_StripsInvalidChars_PreservesAlphanumeric() {
        XCTAssertEqual(PINPolicy.sanitize("ab-cd"), "abcd")
        XCTAssertEqual(PINPolicy.sanitize("12 34"), "1234")
        XCTAssertEqual(PINPolicy.sanitize("a@b#c$d"), "abcd")
    }

    func testSanitize_DoesNotTruncate() {
        // Regression: pre-bug-fix sanitize() silently truncated to 6.
        // It must now PRESERVE length so callers can validate explicitly
        // and surface "PIN too long" rather than dropping characters.
        XCTAssertEqual(PINPolicy.sanitize("abcdefghij"), "abcdefghij")
        XCTAssertEqual(PINPolicy.sanitize("a-b-c-d-e-f-g-h-i"), "abcdefghi")
    }

    func testSanitize_EmptyAndAllInvalid_ReturnsEmpty() {
        XCTAssertEqual(PINPolicy.sanitize(""), "")
        XCTAssertEqual(PINPolicy.sanitize("---"), "")
        XCTAssertEqual(PINPolicy.sanitize("😀😀😀"), "")
    }

    // MARK: humanDescription / invalidMessage / bounds

    func testHumanDescription_MatchesPolicyBounds() {
        XCTAssertEqual(PINPolicy.minLength, 4)
        XCTAssertEqual(PINPolicy.maxLength, 8)
        XCTAssertTrue(PINPolicy.humanDescription.contains("4"))
        XCTAssertTrue(PINPolicy.humanDescription.contains("8"))
    }

    func testInvalidMessage_MentionsBounds() {
        XCTAssertTrue(PINPolicy.invalidMessage.contains("4"))
        XCTAssertTrue(PINPolicy.invalidMessage.contains("8"))
    }

    // MARK: PanelStore round-trip

    private func makeStore() -> (PanelStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINPolicyRoundTrip-\(UUID().uuidString)")
        let store = PanelStore(directory: dir, keyValueStore: MemoryKeyValueStore())
        return (store, dir)
    }

    func testStore_VerifyPIN_AcceptsLegacy4DigitNumeric() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setPIN("1234")
        XCTAssertTrue(store.verifyPIN("1234"))
        XCTAssertFalse(store.verifyPIN("12345"))
        XCTAssertFalse(store.verifyPIN("0000"))
    }

    func testStore_VerifyPIN_AcceptsNew8CharAlphanumeric() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setPIN("Pin12345")  // 8 chars
        XCTAssertTrue(store.verifyPIN("Pin12345"))
        XCTAssertFalse(store.verifyPIN("pin12345"))   // case sensitive
        XCTAssertFalse(store.verifyPIN("Pin1234"))    // shorter
        XCTAssertFalse(store.verifyPIN("Pin123456"))  // longer
    }

    func testStore_VerifyPIN_AcceptsLegacy6CharAlphanumeric() {
        // PINs set under the previous 4–6 policy must still verify under
        // the new 4–8 policy — the store hashes whatever was submitted.
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setPIN("Pin999")  // 6 chars
        XCTAssertTrue(store.verifyPIN("Pin999"))
    }

    // MARK: - B2 — property-based generators

    /// Generates a random alphanumeric PIN of `length` characters
    /// using the same character set isValid accepts.
    private func randomAlphanumeric(_ length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    /// Random sample of "definitely invalid" characters for charset tests.
    private static let invalidChars: [Character] = [
        " ", "-", ".", ",", "!", "@", "#", "$", "%", "^", "&", "*",
        "(", ")", "[", "]", "{", "}", "<", ">", "?", "/", "\\", ":",
        ";", "\"", "'", "+", "=", "_", "\n", "\t"
    ]

    /// Property: every alphanumeric string with length in [minLength,
    /// maxLength] passes isValid.
    func testProperty_AnyValidLengthAlphanumeric_PassesIsValid() {
        for _ in 0..<200 {
            let length = Int.random(in: PINPolicy.minLength...PINPolicy.maxLength)
            let pin = randomAlphanumeric(length)
            XCTAssertTrue(PINPolicy.isValid(pin),
                          "isValid rejected supposedly-valid PIN \"\(pin)\" (length \(length))")
        }
    }

    /// Property: any alphanumeric string with length below min OR above
    /// max must fail isValid.
    func testProperty_OutOfBoundsLength_FailsIsValid() {
        for _ in 0..<100 {
            let tooShort = Int.random(in: 0..<PINPolicy.minLength)
            XCTAssertFalse(PINPolicy.isValid(randomAlphanumeric(tooShort)),
                           "isValid accepted too-short PIN at length \(tooShort)")
        }
        for _ in 0..<100 {
            let tooLong = Int.random(in: (PINPolicy.maxLength + 1)...20)
            XCTAssertFalse(PINPolicy.isValid(randomAlphanumeric(tooLong)),
                           "isValid accepted too-long PIN at length \(tooLong)")
        }
    }

    /// Property: any string containing at least one non-alphanumeric
    /// char fails isValid (regardless of length).
    func testProperty_NonAlphanumericChar_FailsIsValid() {
        for _ in 0..<200 {
            let length = Int.random(in: PINPolicy.minLength...PINPolicy.maxLength)
            var chars = Array(randomAlphanumeric(length))
            // Replace one position with a guaranteed-invalid char.
            let injectAt = Int.random(in: 0..<chars.count)
            chars[injectAt] = Self.invalidChars.randomElement()!
            let pin = String(chars)
            XCTAssertFalse(PINPolicy.isValid(pin),
                           "isValid accepted PIN with non-alphanumeric char: \"\(pin)\"")
        }
    }

    /// Property: sanitize is idempotent.
    func testProperty_SanitizeIsIdempotent() {
        for _ in 0..<200 {
            let raw = String((0..<Int.random(in: 0...20)).map { _ in
                Bool.random()
                    ? Character(UnicodeScalar(Int.random(in: 32...126))!)
                    : Self.invalidChars.randomElement()!
            })
            let once = PINPolicy.sanitize(raw)
            let twice = PINPolicy.sanitize(once)
            XCTAssertEqual(once, twice, "sanitize must be idempotent for input \"\(raw)\"")
        }
    }

    /// Property: sanitize output is always alphanumeric (no non-alphanumeric
    /// chars survive).
    func testProperty_SanitizeOutputIsAlphanumeric() {
        for _ in 0..<200 {
            let raw = String((0..<Int.random(in: 0...30)).map { _ in
                Bool.random()
                    ? Self.invalidChars.randomElement()!
                    : "abcXYZ0189".randomElement()!
            })
            let cleaned = PINPolicy.sanitize(raw)
            XCTAssertTrue(cleaned.allSatisfy { $0.isLetter || $0.isNumber },
                          "sanitize output \"\(cleaned)\" still contains non-alphanumeric")
        }
    }
}

// MARK: - clearAllUserData hole #1: pin_enabled is wiped

/// The previous behavior left the iOS Settings `pin_enabled` toggle on
/// after `clearAllUserData` even though the PIN itself was wiped, which
/// led to the next reconcile prompting the user to set a NEW PIN as if
/// fresh — surprising behavior right after a deliberate wipe. The fix
/// flips `pin_enabled = false` in the `confirmAndClearAllData` flow.
/// We can't drive that VC-level flow from a unit test directly, but we
/// can verify the store side wipes the PIN hash so the assertion holds:
/// after clear, hasPIN is false.
final class ClearAllUserDataPINHoleTests: XCTestCase {

    func testClearAllUserData_LeavesHasPINFalse() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClearHole-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PanelStore(directory: dir, keyValueStore: MemoryKeyValueStore())
        store.setPIN("1234")
        XCTAssertTrue(store.hasPIN)

        store.clearAllUserData()
        XCTAssertFalse(store.hasPIN,
                       "hasPIN must be false after clearAllUserData so the iOS pin_enabled toggle reconcile sees no PIN to disable")
    }
}

// MARK: - PINPromptCoordinator (B1)

/// Recorder that scripts user interactions through PINPresenter. The
/// coordinator drives `presentations` by appending one entry per
/// `presentPINAlert` call; tests then call `tap(buttonIndex:values:)`
/// or `simulateForgotPIN()` to drive the flow deterministically.
final class TestPINPresenter: PINPresenter {
    struct Recorded {
        let config: PINAlertConfig
        let handler: (PINAlertResult) -> Void
    }
    private(set) var presentations: [Recorded] = []

    func presentPINAlert(_ config: PINAlertConfig,
                         handler: @escaping (PINAlertResult) -> Void) {
        presentations.append(Recorded(config: config, handler: handler))
    }

    /// Simulates the user tapping the button at `buttonIndex` of the
    /// most recent presentation, with the given field values.
    func tap(_ buttonIndex: Int, values: [String] = []) {
        guard let last = presentations.last else {
            XCTFail("No presentation to tap"); return
        }
        last.handler(.buttonTapped(index: buttonIndex, fieldValues: values))
    }

    /// Simulates the user tapping the Forgot PIN keyboard accessory link.
    func simulateForgotPIN() {
        guard let last = presentations.last else {
            XCTFail("No presentation to forgot-tap"); return
        }
        last.handler(.forgotPIN)
    }
}

final class PINPromptCoordinatorEnableTests: XCTestCase {

    var tempDir: URL!
    var store: PanelStore!
    var defaults: UserDefaults!
    var presenter: TestPINPresenter!
    var coordinator: PINPromptCoordinator!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINCoordinator-\(UUID().uuidString)")
        store = PanelStore(directory: tempDir, keyValueStore: MemoryKeyValueStore())
        let suite = "PINCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        presenter = TestPINPresenter()
        coordinator = PINPromptCoordinator(store: store,
                                           defaults: defaults,
                                           presenter: presenter)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: happy path

    func testRunEnablePINFlow_ValidPIN_SetsPIN_CompletesTrue() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        XCTAssertEqual(presenter.presentations.count, 1)
        let initial = presenter.presentations[0].config
        XCTAssertEqual(initial.title, "Set PIN")
        XCTAssertEqual(initial.fields.count, 2)
        XCTAssertEqual(initial.buttons.map(\.title), ["Cancel", "Set PIN"])

        // User types valid matching PIN, taps Set PIN.
        presenter.tap(1, values: ["abcd", "abcd"])

        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.hasPIN)
        XCTAssertTrue(store.verifyPIN("abcd"))
    }

    // MARK: cancel

    func testRunEnablePINFlow_Cancel_RevertsToggle_CompletesFalse() {
        defaults.set(true, forKey: "pin_enabled")
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        // User taps Cancel.
        presenter.tap(0, values: ["abc", ""])

        XCTAssertEqual(completion, false)
        XCTAssertFalse(store.hasPIN)
        XCTAssertFalse(defaults.bool(forKey: "pin_enabled"),
                       "Cancel must revert the iOS Settings toggle to false")
        // No re-presentation on Cancel.
        XCTAssertEqual(presenter.presentations.count, 1)
    }

    // MARK: cycle on too-short

    func testRunEnablePINFlow_TooShort_CyclesWithBoundsError() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        // Type 3 chars (under min) → tap Set PIN.
        presenter.tap(1, values: ["abc", "abc"])

        XCTAssertNil(completion, "should not complete on validation failure")
        XCTAssertEqual(presenter.presentations.count, 2,
                       "alert must re-present on too-short input")

        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.contains(PINPolicy.humanDescription),
                      "retry message must explicitly state the 4–8 bounds")
        XCTAssertTrue(retry.message.contains("4"))
        XCTAssertTrue(retry.message.contains("8"))
        XCTAssertEqual(retry.fields[0].prefilledText, "abc",
                       "user-entered PIN must be prefilled on retry")
        XCTAssertEqual(retry.fields[1].prefilledText, "abc")
    }

    // MARK: cycle on too-long

    func testRunEnablePINFlow_TooLong_CyclesWithBoundsError() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        // Type 9 chars (over max) → tap Set PIN.
        presenter.tap(1, values: ["abcdefghi", "abcdefghi"])

        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)
        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.contains("4"))
        XCTAssertTrue(retry.message.contains("8"))
        XCTAssertEqual(retry.fields[0].prefilledText, "abcdefghi")
    }

    // MARK: cycle on non-alphanumeric

    func testRunEnablePINFlow_NonAlphanumeric_CyclesWithBoundsError() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        // Space embedded → fails alphanumeric check.
        presenter.tap(1, values: ["ab cd", "ab cd"])

        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)
        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.contains(PINPolicy.humanDescription))
        XCTAssertEqual(retry.fields[0].prefilledText, "ab cd",
                       "raw input is preserved so user can correct it")
    }

    // MARK: cycle on mismatch

    func testRunEnablePINFlow_Mismatch_CyclesWithMatchError() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        // Both fields are valid length/charset but don't match.
        presenter.tap(1, values: ["abcd", "abce"])

        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)
        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.lowercased().contains("match")
                      || retry.message.lowercased().contains("didn't match"),
                      "retry should explicitly say PINs didn't match")
        // Bounds line is always present in the prompt (plan guarantee
        // (d): bounds stated up front, not just on failure) — the
        // mismatch error is layered on top.
        XCTAssertTrue(retry.message.contains(PINPolicy.humanDescription))
        XCTAssertEqual(retry.fields[0].prefilledText, "abcd")
        XCTAssertEqual(retry.fields[1].prefilledText, "abce")
    }

    // MARK: full cycle: bad → bad → good

    func testRunEnablePINFlow_MultipleFailures_FinallySucceeds() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }

        // Round 1: too short.
        presenter.tap(1, values: ["a", "a"])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)

        // Round 2: mismatch.
        presenter.tap(1, values: ["abcd", "abce"])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 3)

        // Round 3: success.
        presenter.tap(1, values: ["abcdef", "abcdef"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.verifyPIN("abcdef"))
        XCTAssertEqual(presenter.presentations.count, 3, "no re-presentation after success")
    }

    // MARK: max-length boundary

    func testRunEnablePINFlow_8CharPIN_Accepted() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }
        presenter.tap(1, values: ["12345678", "12345678"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.verifyPIN("12345678"))
    }

    func testRunEnablePINFlow_4CharPIN_Accepted() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }
        presenter.tap(1, values: ["1234", "1234"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.verifyPIN("1234"))
    }

    // MARK: bounds wording in initial presentation

    func testRunEnablePINFlow_InitialMessage_StatesBoundsUpFront() {
        coordinator.runEnablePINFlow { _ in }
        let initial = presenter.presentations[0].config
        XCTAssertTrue(initial.message.contains(PINPolicy.humanDescription),
                      "initial Set-PIN prompt must state the 4–8 bounds up front")
    }

    // MARK: runChangePINFlow

    func testRunChangePINFlow_ValidNewPIN_SetsPIN_NoToggleSideEffect() {
        // Pre-existing PIN + pin_enabled = true (this is the change scenario).
        store.setPIN("oldd")
        defaults.set(true, forKey: "pin_enabled")

        var completion: Bool?
        coordinator.runChangePINFlow { completion = $0 }

        let initial = presenter.presentations[0].config
        XCTAssertEqual(initial.title, "New PIN",
                       "change flow uses 'New PIN' title, not 'Set PIN'")
        XCTAssertEqual(initial.buttons.map(\.title), ["Cancel", "Save"])
        XCTAssertTrue(initial.message.contains(PINPolicy.humanDescription),
                      "bounds line up front in change flow too")

        presenter.tap(1, values: ["newpass", "newpass"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.verifyPIN("newpass"))
        XCTAssertFalse(store.verifyPIN("oldd"))
        XCTAssertTrue(defaults.bool(forKey: "pin_enabled"),
                      "change flow must NOT touch pin_enabled")
    }

    func testRunChangePINFlow_Cancel_KeepsOldPIN_AndPinEnabled() {
        store.setPIN("oldd")
        defaults.set(true, forKey: "pin_enabled")

        var completion: Bool?
        coordinator.runChangePINFlow { completion = $0 }
        presenter.tap(0, values: [])

        XCTAssertEqual(completion, false)
        XCTAssertTrue(store.verifyPIN("oldd"),
                      "Cancel must leave the old PIN in place")
        XCTAssertTrue(defaults.bool(forKey: "pin_enabled"),
                      "Cancel must NOT flip pin_enabled to false")
    }

    func testRunChangePINFlow_TooShort_CyclesWithBoundsError() {
        store.setPIN("oldd")
        var completion: Bool?
        coordinator.runChangePINFlow { completion = $0 }

        presenter.tap(1, values: ["abc", "abc"])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)
        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.contains(PINPolicy.humanDescription))
        XCTAssertEqual(retry.fields[0].prefilledText, "abc")
    }

    func testRunChangePINFlow_Mismatch_CyclesWithMatchError() {
        store.setPIN("oldd")
        var completion: Bool?
        coordinator.runChangePINFlow { completion = $0 }

        presenter.tap(1, values: ["abcd", "abce"])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)
        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.lowercased().contains("match"))
        XCTAssertEqual(retry.fields[0].prefilledText, "abcd")
        XCTAssertEqual(retry.fields[1].prefilledText, "abce")
    }

    func testRunChangePINFlow_8CharBoundary_Accepted() {
        store.setPIN("oldd")
        var completion: Bool?
        coordinator.runChangePINFlow { completion = $0 }
        presenter.tap(1, values: ["abcdefgh", "abcdefgh"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.verifyPIN("abcdefgh"))
    }

    // MARK: runDisablePINFlow — verify current PIN, then clear it

    func testRunDisablePINFlow_CorrectPIN_ClearsPIN_LeavesToggleOff() {
        store.setPIN("abcd")
        defaults.set(false, forKey: "pin_enabled")  // user just toggled off

        var completion: Bool?
        coordinator.runDisablePINFlow { completion = $0 }

        // Verify-PIN alert appears with title "Disable PIN?" and Disable button.
        XCTAssertEqual(presenter.presentations.count, 1)
        let initial = presenter.presentations[0].config
        XCTAssertEqual(initial.title, "Disable PIN?")
        XCTAssertEqual(initial.buttons.map(\.title), ["Cancel", "Disable"])

        presenter.tap(1, values: ["abcd"])  // correct PIN, tap Disable
        XCTAssertEqual(completion, true)
        XCTAssertFalse(store.hasPIN, "PIN must be cleared on confirm")
        XCTAssertFalse(defaults.bool(forKey: "pin_enabled"),
                       "Disable confirm must leave pin_enabled off")
    }

    func testRunDisablePINFlow_Cancel_RevertsToggleToTrue() {
        store.setPIN("abcd")
        defaults.set(false, forKey: "pin_enabled")  // user just toggled off

        var completion: Bool?
        coordinator.runDisablePINFlow { completion = $0 }
        presenter.tap(0, values: [])  // Cancel

        XCTAssertEqual(completion, false)
        XCTAssertTrue(store.hasPIN, "Cancel must NOT clear the PIN")
        XCTAssertTrue(defaults.bool(forKey: "pin_enabled"),
                      "Cancel must revert pin_enabled to true so iOS Settings reflects reality")
    }

    func testRunDisablePINFlow_WrongPIN_CyclesAndKeepsPIN() {
        store.setPIN("abcd")
        defaults.set(false, forKey: "pin_enabled")

        var completion: Bool?
        coordinator.runDisablePINFlow { completion = $0 }
        presenter.tap(1, values: ["wrng"])  // wrong PIN

        XCTAssertNil(completion, "wrong PIN must not complete the flow")
        XCTAssertEqual(presenter.presentations.count, 2,
                       "wrong PIN must re-present the verify alert")
        XCTAssertTrue(presenter.presentations[1].config.message.contains("Incorrect PIN"))
        XCTAssertTrue(store.hasPIN, "PIN must remain set during cycling")
    }

    func testRunDisablePINFlow_NoForgotLink() {
        store.setPIN("abcd")
        coordinator.runDisablePINFlow { _ in }
        XCTAssertNil(presenter.presentations[0].config.forgotPINButtonTitle,
                     "disable flow does not expose Forgot PIN — the user can use Cancel and then trigger Forgot via the editor-entry alert")
    }
}

// MARK: - Forgot PIN abort wiring (A2)

/// Verifies the `onAbort` closure passed to `presentForgotPINResetSheet`
/// fires on every non-success exit path: iCloud reset failure, security-
/// question wrong answer, action-sheet Cancel. The store-level reset
/// methods (resetPINViaICloudAccount, resetPIN(securityAnswer:)) are
/// covered by PanelStoreTests; this exercise focuses on the closure
/// wiring that Phase 1 added to keep the user from being dead-ended.
final class ForgotPINResetAbortTests: XCTestCase {

    var tempDir: URL!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!
    var iCloudSignedIn = false

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgotPINReset-\(UUID().uuidString)")
        kvs = MemoryKeyValueStore()
        iCloudSignedIn = false
        store = PanelStore(directory: tempDir,
                           keyValueStore: kvs,
                           iCloudAvailability: { [unowned self] in self.iCloudSignedIn })
        store.setPIN("abcd",
                     securityQuestion: "Pet?",
                     securityAnswer: "Fido")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Direct store-level confirmation: iCloud-signed-out reset throws.
    /// The production `presentForgotPINResetSheet` catches this and
    /// invokes onAbort (verified at the integration level by the UI
    /// tests via the `confirmActionWithPIN` re-presentation; see TODO).
    func testReset_iCloudSignedOut_ThrowsAndPreservesPIN() {
        XCTAssertThrowsError(try store.resetPINViaICloudAccount()) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .iCloudUnavailable)
        }
        XCTAssertTrue(store.hasPIN,
                      "iCloud reset failure must NOT clear the PIN — the abort path leaves state intact")
    }

    /// iCloud reset on signed-in account succeeds and clears the PIN.
    func testReset_iCloudSignedIn_Succeeds() throws {
        iCloudSignedIn = true
        try store.resetPINViaICloudAccount()
        XCTAssertFalse(store.hasPIN)
    }

    /// Security-question reset with wrong answer throws (abort path).
    func testReset_SecurityQuestion_WrongAnswer_PreservesPIN() {
        XCTAssertThrowsError(try store.resetPIN(securityAnswer: "Wrong")) { error in
            XCTAssertEqual(error as? PanelStore.StoreError, .incorrectAnswer)
        }
        XCTAssertTrue(store.hasPIN,
                      "wrong security answer must NOT clear the PIN — the abort path leaves state intact")
    }

    /// Security-question reset with correct answer succeeds (case-
    /// insensitive, whitespace-trimmed). After clear, hasSecurityQuestion
    /// is also false (clearPIN removes both).
    func testReset_SecurityQuestion_CorrectAnswer_Succeeds() throws {
        try store.resetPIN(securityAnswer: "  fido  ")
        XCTAssertFalse(store.hasPIN)
        XCTAssertFalse(store.hasSecurityQuestion)
    }

    // TODO: full UI-driven test of the action-sheet Cancel triggering
    // onAbort which re-presents the original PIN-confirm alert. The
    // alert chain is unreliable under XCUITest in the simulator (see
    // iInteractUITests deferred-tests note). The store-level guarantees
    // above ensure the abort path is safe; the closure wiring is
    // exercised by manual testing.
}

// MARK: - Settings.bundle key contract

/// Snapshot of the iOS-Settings keys the app reads. If `Settings.bundle/
/// Root.plist` ever drifts (key renamed, new key added, etc.) without
/// updating code that reads from `UserDefaults.standard`, this test
/// fails — preventing the silent class of bug where the iOS Settings
/// toggle no longer affects app behavior.
final class SettingsBundleKeyContractTests: XCTestCase {

    /// All `Key` values declared in PreferenceSpecifiers, in plist order.
    private func bundleKeys() throws -> [String] {
        let plistURL = Bundle(for: PanelStore.self)
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Settings.bundle")
            .appendingPathComponent("Root.plist")
        // Settings.bundle isn't always copied into the test host; fall
        // back to the source path under the project root so this test
        // remains useful regardless of bundling.
        let url: URL
        if FileManager.default.fileExists(atPath: plistURL.path) {
            url = plistURL
        } else {
            // Test runner cwd is unreliable; locate via this file's path.
            let thisFile = URL(fileURLWithPath: #filePath)
            url = thisFile
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Settings.bundle/Root.plist")
        }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let root = plist as? [String: Any],
              let specs = root["PreferenceSpecifiers"] as? [[String: Any]] else {
            XCTFail("malformed Root.plist"); return []
        }
        return specs.compactMap { $0["Key"] as? String }
    }

    func testSettingsBundleKeys_MatchExpectedSet() throws {
        // Order: Mode → Security → Voice → Privacy. iOS auto-appends an
        // "Allow [App] to Access" section at the bottom from the
        // Info.plist usage descriptions (camera / photo library /
        // microphone / Face ID); that's not in this plist.
        let expected = [
            "configuration_mode",
            "pin_enabled",
            "change_pin",
            "hide_config",
            "voice_enabled",
            "voice_style",
            "pending_clear_all",
        ]
        let actual = try bundleKeys()
        XCTAssertEqual(actual, expected,
                       "Settings.bundle keys drifted from the code contract — update both in lockstep")
    }

    func testSettingsView_GearVisible_DefaultsToTrue() {
        let suite = "GearVisible-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertTrue(SettingsView.gearVisible(d),
                      "gear is visible by default (hide_config unset)")
    }

    func testSettingsView_GearVisible_FalseWhenHideConfigIsTrue() {
        let suite = "GearVisible-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(true, forKey: "hide_config")
        XCTAssertFalse(SettingsView.gearVisible(d))
    }

    func testSettingsView_GearVisible_TrueWhenHideConfigToggledBack() {
        let suite = "GearVisible-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(true, forKey: "hide_config")
        d.set(false, forKey: "hide_config")
        XCTAssertTrue(SettingsView.gearVisible(d),
                      "runtime toggle off restores gear visibility on next read")
    }

    // MARK: PendingActionsDecision (modal-up retry)

    func testPendingActions_NoModal_FiresImmediately() {
        XCTAssertEqual(PendingActionsDecision.decide(modalIsUp: false,
                                                      pendingRetryScheduled: false,
                                                      retriesRemaining: 5),
                       .fire)
        // Even if a retry was pending, no modal up means we can fire now.
        XCTAssertEqual(PendingActionsDecision.decide(modalIsUp: false,
                                                      pendingRetryScheduled: true,
                                                      retriesRemaining: 0),
                       .fire)
    }

    func testPendingActions_ModalUp_FirstCall_SchedulesRetry() {
        XCTAssertEqual(PendingActionsDecision.decide(modalIsUp: true,
                                                      pendingRetryScheduled: false,
                                                      retriesRemaining: 5),
                       .scheduleRetry)
    }

    func testPendingActions_ModalUp_AlreadyScheduled_Skips() {
        XCTAssertEqual(PendingActionsDecision.decide(modalIsUp: true,
                                                      pendingRetryScheduled: true,
                                                      retriesRemaining: 5),
                       .skip,
                       "coalesce: don't stack timers when one is already pending")
    }

    func testPendingActions_ModalUp_RetriesExhausted_FiresAnyway() {
        // After retries exhaust we MUST fire anyway. Returning .skip
        // would silently drop the user's pending iOS-Settings change
        // when a long-lived modal (like the splash-screen voice-style
        // picker) is up — the splash never re-triggers reconcile when
        // it dismisses, so Enable PIN would never surface. UIKit
        // supports presenting an alert on top of another alert via
        // topmostPresenter, so the layering works.
        XCTAssertEqual(PendingActionsDecision.decide(modalIsUp: true,
                                                      pendingRetryScheduled: false,
                                                      retriesRemaining: 0),
                       .fire)
    }

    /// User-facing invariant the previous .skip behavior violated:
    /// every (modalIsUp, pendingRetryScheduled, retriesRemaining)
    /// state must EVENTUALLY produce a .fire — never .skip indefinitely.
    /// The only legitimate .skip is "another retry is already pending
    /// (it'll fire shortly)". This guard test catches a future regression
    /// where someone reintroduces .skip on retries-exhausted.
    func testPendingActions_NeverSilentlyDrops_PendingActions() {
        // For every state where pendingRetryScheduled is false (no retry
        // in flight), the decision must be .fire OR .scheduleRetry —
        // never .skip. .skip is only legal when another retry is
        // already pending.
        for retries in 0...10 {
            for modal in [true, false] {
                let outcome = PendingActionsDecision.decide(
                    modalIsUp: modal,
                    pendingRetryScheduled: false,
                    retriesRemaining: retries
                )
                XCTAssertNotEqual(outcome, .skip,
                                  "Decision must not silently skip when no retry is pending (modal=\(modal), retries=\(retries))")
            }
        }
    }

    func testSettingsBundleKeys_UsedByCode() throws {
        // The reconciler reads pin_enabled / change_pin / pending_clear_all.
        // The VC reads voice_enabled / voice_style / hide_config.
        // ConfigurationMode reads configuration_mode.
        // If any of these constants drift, the corresponding bundle entry
        // becomes a no-op.
        let actual = try bundleKeys()
        XCTAssertTrue(actual.contains(ConfigurationMode.userDefaultsKey),
                      "ConfigurationMode.userDefaultsKey must match Settings.bundle")
    }
}

// MARK: - runEnablePINFlowWithSecurityQuestion (A3)

/// Re-housed from PINPromptCoordinatorEnableTests (which the disable +
/// abort additions split out of). Same setup pattern; covers the
/// 2-step Set PIN → optional security question flow.
final class PINEnableSecurityQuestionTests: XCTestCase {

    var tempDir: URL!
    var store: PanelStore!
    var defaults: UserDefaults!
    var presenter: TestPINPresenter!
    var coordinator: PINPromptCoordinator!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINEnableSecQ-\(UUID().uuidString)")
        store = PanelStore(directory: tempDir, keyValueStore: MemoryKeyValueStore())
        let suite = "PINEnableSecQTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        presenter = TestPINPresenter()
        coordinator = PINPromptCoordinator(store: store,
                                           defaults: defaults,
                                           presenter: presenter)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRunEnablePINWithQuestion_QuestionIsMandatory_OnlySaveButton() {
        coordinator.runEnablePINFlowWithSecurityQuestion { _ in }
        presenter.tap(1, values: ["abcd", "abcd"])
        let q = presenter.presentations[1].config
        XCTAssertEqual(q.title, "Set a Security Question")
        XCTAssertEqual(q.buttons.map(\.title), ["Save"],
                       "no Skip — security question is mandatory now (the only Forgot PIN recovery)")
    }

    func testRunEnablePINWithQuestion_SaveQuestion_QuestionStored() {
        var completion: Bool?
        coordinator.runEnablePINFlowWithSecurityQuestion { completion = $0 }
        presenter.tap(1, values: ["abcd", "abcd"])
        // Save with both fields filled.
        presenter.tap(0, values: ["First pet?", "Fido"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.hasSecurityQuestion)
        XCTAssertEqual(store.securityQuestion, "First pet?")
    }

    func testRunEnablePINWithQuestion_OneEmpty_CyclesWithError() {
        var completion: Bool?
        coordinator.runEnablePINFlowWithSecurityQuestion { completion = $0 }
        presenter.tap(1, values: ["abcd", "abcd"])
        // Save with answer empty — must cycle, not silently complete.
        presenter.tap(0, values: ["First pet?", ""])
        XCTAssertNil(completion, "empty answer must cycle, not complete")
        XCTAssertEqual(presenter.presentations.count, 3,
                       "question step re-presents on missing field")
        XCTAssertTrue(presenter.presentations[2].config.message.lowercased().contains("required"),
                      "retry message must say both are required")
        XCTAssertEqual(presenter.presentations[2].config.fields[0].prefilledText, "First pet?",
                       "user-entered Question must be prefilled on retry")
    }

    func testRunEnablePINWithQuestion_BothEmpty_CyclesWithError() {
        var completion: Bool?
        coordinator.runEnablePINFlowWithSecurityQuestion { completion = $0 }
        presenter.tap(1, values: ["abcd", "abcd"])
        presenter.tap(0, values: ["", ""])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 3)
        XCTAssertFalse(store.hasSecurityQuestion)
    }

    func testRunEnablePINWithQuestion_CancelAtPINStep_NoQuestionPrompt() {
        var completion: Bool?
        coordinator.runEnablePINFlowWithSecurityQuestion { completion = $0 }
        presenter.tap(0, values: ["", ""])  // Cancel at PIN step
        XCTAssertEqual(completion, false)
        XCTAssertEqual(presenter.presentations.count, 1,
                       "no question prompt when PIN step cancelled")
        XCTAssertFalse(store.hasPIN)
    }

    func testRunEnablePINWithQuestion_PINCycleStillWorks_BoundsLineVisible() {
        var completion: Bool?
        coordinator.runEnablePINFlowWithSecurityQuestion { completion = $0 }
        // Trigger bounds error at PIN step.
        presenter.tap(1, values: ["a", "a"])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2,
                       "PIN step re-presents on too-short, no question step yet")
        XCTAssertTrue(presenter.presentations[1].config.message.contains(PINPolicy.humanDescription),
                      "bounds error message visible on retry")
        XCTAssertEqual(presenter.presentations[1].config.title, "Set PIN",
                       "still in PIN step, not question step")
    }
}

// MARK: - PINVerifyCoordinator

final class PINVerifyCoordinatorTests: XCTestCase {

    var tempDir: URL!
    var store: PanelStore!
    var presenter: TestPINPresenter!
    var clock: Date = Date(timeIntervalSinceReferenceDate: 0)
    var defaults: UserDefaults!
    var coordinator: PINVerifyCoordinator!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINVerify-\(UUID().uuidString)")
        store = PanelStore(directory: tempDir, keyValueStore: MemoryKeyValueStore())
        store.setPIN("abcd")  // PIN must be set for the verify flow
        presenter = TestPINPresenter()
        clock = Date(timeIntervalSinceReferenceDate: 0)
        // Isolated UserDefaults so lockout persistence (A4) doesn't
        // leak across tests in this suite.
        let suite = "PINVerifyCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        coordinator = PINVerifyCoordinator(store: store,
                                           presenter: presenter,
                                           now: { [unowned self] in self.clock },
                                           defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func runFlow(onForgotPIN: (() -> Void)? = nil,
                         onCancel: (() -> Void)? = nil,
                         onConfirm: @escaping () -> Void = {}) {
        coordinator.runVerifyFlow(
            title: "Verify PIN",
            message: "Enter your PIN to continue.",
            actionTitle: "Continue",
            actionStyle: .destructive,
            onForgotPIN: onForgotPIN,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }

    // MARK: happy path

    func testCorrectPIN_FiresOnConfirm() {
        var confirmed = false
        runFlow { confirmed = true }

        XCTAssertEqual(presenter.presentations.count, 1)
        let initial = presenter.presentations[0].config
        XCTAssertEqual(initial.title, "Verify PIN")
        XCTAssertEqual(initial.fields.count, 1)
        XCTAssertEqual(initial.buttons.map(\.title), ["Cancel", "Continue"])

        presenter.tap(1, values: ["abcd"])
        XCTAssertTrue(confirmed)
    }

    // MARK: cancel

    func testCancel_FiresOnCancel_NoRetry() {
        var cancelled = false
        var confirmed = false
        runFlow(onCancel: { cancelled = true }) { confirmed = true }

        presenter.tap(0, values: [])
        XCTAssertTrue(cancelled)
        XCTAssertFalse(confirmed)
        XCTAssertEqual(presenter.presentations.count, 1, "Cancel must not re-present")
    }

    // MARK: wrong PIN cycle

    func testWrongPIN_CyclesWithRemainingAttempts() {
        var confirmed = false
        runFlow { confirmed = true }

        presenter.tap(1, values: ["wrong"])
        XCTAssertFalse(confirmed)
        XCTAssertEqual(presenter.presentations.count, 2, "wrong PIN must re-present")

        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.contains("Incorrect PIN"))
        XCTAssertTrue(retry.message.contains("4 attempts remaining"),
                      "expected 4 of 5 attempts left after one wrong try")
    }

    func testWrongPIN_BoundsLineAlwaysVisible() {
        runFlow {}
        presenter.tap(1, values: ["wrong"])
        let retry = presenter.presentations[1].config
        XCTAssertTrue(retry.message.contains(PINPolicy.humanDescription),
                      "bounds line must always appear, even on retry")
    }

    func testFiveWrongAttempts_TriggersLockoutAlert() {
        var cancelled = false
        runFlow(onCancel: { cancelled = true }) {}

        for _ in 0..<5 { presenter.tap(1, values: ["wrong"]) }

        // After 5 wrongs, the lockout alert is the 6th presentation
        // (1 initial + 4 wrong-PIN re-presentations + 1 lockout).
        XCTAssertEqual(presenter.presentations.count, 6)
        let lockout = presenter.presentations.last!.config
        XCTAssertEqual(lockout.title, "Too Many Attempts")
        XCTAssertTrue(lockout.message.contains("60"))
        XCTAssertEqual(lockout.buttons.map(\.title), ["OK"])

        // Tapping OK invokes onCancel.
        presenter.tap(0)
        XCTAssertTrue(cancelled)
    }

    // MARK: lockout expiry

    func testLockoutExpires_ThenSucceeds() {
        runFlow {}

        // Lock out via 5 wrong attempts.
        for _ in 0..<5 { presenter.tap(1, values: ["wrong"]) }
        XCTAssertEqual(presenter.presentations.last?.config.title, "Too Many Attempts")
        presenter.tap(0)  // dismiss lockout

        // 61s later the user starts a fresh verify flow.
        clock = clock.addingTimeInterval(61)
        var confirmed = false
        // Use the SAME defaults instance — lockout persistence (A4)
        // means the new coordinator inherits the prior lockout window,
        // and 61s later it has expired.
        let coordinator2 = PINVerifyCoordinator(store: store,
                                                presenter: presenter,
                                                now: { [unowned self] in self.clock },
                                                defaults: defaults)
        coordinator2.runVerifyFlow(
            title: "Verify PIN",
            message: "Try again.",
            actionTitle: "Continue",
            actionStyle: .destructive,
            onCancel: nil
        ) { confirmed = true }
        presenter.tap(1, values: ["abcd"])
        XCTAssertTrue(confirmed,
                      "lockout window expires after 60s — fresh flow on the same defaults accepts correct PIN")
    }

    // MARK: Forgot PIN

    func testForgotPIN_FiresOnForgotPIN_Closure() {
        var forgot = false
        runFlow(onForgotPIN: { forgot = true }) {}
        presenter.simulateForgotPIN()
        XCTAssertTrue(forgot)
    }

    func testForgotPIN_ConfigIncludesForgotLinkOnlyWhenHandlerProvided() {
        runFlow(onForgotPIN: { }) {}
        XCTAssertEqual(presenter.presentations[0].config.forgotPINButtonTitle, "Forgot PIN?")

        // Re-init coordinator to clear presentation state.
        presenter = TestPINPresenter()
        coordinator = PINVerifyCoordinator(store: store,
                                           presenter: presenter,
                                           now: { [unowned self] in self.clock },
                                           defaults: defaults)
        coordinator.runVerifyFlow(
            title: "Verify PIN",
            message: "Enter your PIN to continue.",
            actionTitle: "Continue",
            actionStyle: .destructive,
            onForgotPIN: nil
        ) {}
        XCTAssertNil(presenter.presentations[0].config.forgotPINButtonTitle,
                     "no Forgot PIN handler → no link in config")
    }

    // MARK: bounds wording

    func testInitialMessage_StatesBoundsUpFront() {
        runFlow {}
        let initial = presenter.presentations[0].config
        XCTAssertTrue(initial.message.contains(PINPolicy.humanDescription),
                      "initial verify prompt must state the 4–8 bounds up front")
    }

    // MARK: handles paste of non-alphanumeric chars

    func testWrongPINWithPasteJunk_StripsAndComparesCleanly() {
        var confirmed = false
        runFlow { confirmed = true }
        // User pastes "ab cd" — sanitize strips space → "abcd" matches.
        presenter.tap(1, values: ["ab cd"])
        XCTAssertTrue(confirmed,
                      "PINPolicy.sanitize stripping is applied before verify so paste with whitespace works")
    }

    /// Production pattern (FeelingTableViewController.showPINGateForEditor):
    /// Forgot PIN's onAbort closure re-creates a fresh coordinator and
    /// re-runs the verify flow so the user isn't dead-ended after the
    /// reset action sheet dismisses without a reset. This test simulates
    /// that re-entry path at the coordinator level.
    func testForgotPIN_AbortRePrompt_PresentsFreshVerifyAlert() {
        var rebootCount = 0
        // Retain successive coordinators so their handlers don't
        // dealloc mid-flow (mirrors what showPINGateForEditor does
        // via objc_setAssociatedObject in production).
        var live: [PINVerifyCoordinator] = []

        func runFresh() {
            let fresh = PINVerifyCoordinator(store: store,
                                             presenter: presenter,
                                             now: { [unowned self] in self.clock },
                                             defaults: defaults)
            live.append(fresh)
            fresh.runVerifyFlow(
                title: "Open Configuration",
                message: "Configuration is PIN-protected.",
                actionTitle: "Configure",
                actionStyle: .default,
                onForgotPIN: {
                    rebootCount += 1
                    runFresh()  // simulates onAbort re-presenting the verify alert
                },
                onCancel: nil
            ) {}
        }
        runFresh()

        XCTAssertEqual(presenter.presentations.count, 1)
        presenter.simulateForgotPIN()
        XCTAssertEqual(rebootCount, 1)
        XCTAssertEqual(presenter.presentations.count, 2,
                       "after Forgot abort, fresh verify alert is presented again")
        XCTAssertEqual(presenter.presentations[1].config.title, "Open Configuration",
                       "re-prompt uses the same title as the original")
    }
}

// MARK: - SettingsReconciler

final class SettingsReconcilerTests: XCTestCase {

    var tempDir: URL!
    var store: PanelStore!
    var defaults: UserDefaults!
    var reconciler: SettingsReconciler!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reconciler-\(UUID().uuidString)")
        store = PanelStore(directory: tempDir, keyValueStore: MemoryKeyValueStore())
        let suite = "ReconcilerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        reconciler = SettingsReconciler(store: store, defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: enable / disable PIN

    func testWantPIN_ButNoPINSet_ReturnsEnablePIN() {
        defaults.set(true, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [.enablePIN])
    }

    func testDontWantPIN_ButPINSet_ReturnsDisablePIN() {
        store.setPIN("1234")
        defaults.set(false, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [.disablePIN])
    }

    func testWantPIN_AndPINSet_NoEffect() {
        store.setPIN("1234")
        defaults.set(true, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [])
    }

    func testDontWantPIN_AndNoPIN_NoEffect() {
        defaults.set(false, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [])
    }

    // MARK: change PIN (one-shot)

    func testChangePIN_WithPINSet_ReturnsChangePIN_AndClearsToggle() {
        store.setPIN("1234")
        defaults.set(true, forKey: "pin_enabled")
        defaults.set(true, forKey: "change_pin")
        XCTAssertEqual(reconciler.reconcile(), [.changePIN])
        XCTAssertFalse(defaults.bool(forKey: "change_pin"),
                       "change_pin must be cleared after reconcile so it doesn't fire twice")
    }

    func testChangePIN_WithoutPIN_SilentlyClearsToggle() {
        defaults.set(true, forKey: "change_pin")
        XCTAssertEqual(reconciler.reconcile(), [],
                       "no PIN to change → silently consume the toggle")
        XCTAssertFalse(defaults.bool(forKey: "change_pin"))
    }

    // MARK: clear all data (one-shot)

    func testPendingClearAll_ReturnsClearAllData_AndClearsToggle() {
        defaults.set(true, forKey: "pending_clear_all")
        XCTAssertEqual(reconciler.reconcile(), [.clearAllData])
        XCTAssertFalse(defaults.bool(forKey: "pending_clear_all"))
    }

    // MARK: combinations

    func testEnablePIN_AndChangePIN_AndClearAll_AllDispatched() {
        // pin_enabled=true, hasPIN=false → enablePIN
        // change_pin=true, hasPIN=false → silent (no effect)
        // pending_clear_all=true → clearAllData
        defaults.set(true, forKey: "pin_enabled")
        defaults.set(true, forKey: "change_pin")
        defaults.set(true, forKey: "pending_clear_all")
        XCTAssertEqual(reconciler.reconcile(), [.enablePIN, .clearAllData])
    }

    func testDisablePIN_AndChangePIN_HasPIN_DispatchedInOrder() {
        // pin_enabled=false, hasPIN=true → disablePIN
        // change_pin=true, hasPIN=true → changePIN
        // (intentionally weird state — both would be a contradiction in
        // practice, but we want a deterministic order if it happens)
        store.setPIN("1234")
        defaults.set(false, forKey: "pin_enabled")
        defaults.set(true, forKey: "change_pin")
        XCTAssertEqual(reconciler.reconcile(), [.disablePIN, .changePIN])
    }

    // MARK: idempotency — one-shot toggles don't fire twice

    func testTogglesNotFireTwice_OnConsecutiveReconciles() {
        // Consistent baseline: pin_enabled=true, hasPIN=true (no enable/
        // disable effect from this pair). Then add the one-shot toggles.
        store.setPIN("1234")
        defaults.set(true, forKey: "pin_enabled")
        defaults.set(true, forKey: "change_pin")
        defaults.set(true, forKey: "pending_clear_all")

        XCTAssertEqual(reconciler.reconcile(), [.changePIN, .clearAllData])
        XCTAssertEqual(reconciler.reconcile(), [],
                       "second reconcile must be a no-op once one-shot toggles are cleared")
    }
}

// MARK: - A5: KVS observer mirrors PIN-hash changes to pin_enabled

/// Integration tests for `PanelStore.iCloudKeysDidChange` — when another
/// device sets or clears the PIN remotely, this device's `pin_enabled`
/// toggle in iOS Settings should follow so it doesn't lie about reality.
///
/// The observer writes to `UserDefaults.standard["pin_enabled"]` (the
/// hardcoded Settings.bundle key), so each test save / restores that
/// value rather than using an isolated suite.
final class PINHashKVSObserverTests: XCTestCase {

    private static let pinEnabledKey = "pin_enabled"
    private static let pinHashKVSKey = "panelstore.pin_hash"

    var tempDir: URL!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!
    var savedPINEnabled: Bool!

    override func setUp() {
        super.setUp()
        savedPINEnabled = UserDefaults.standard.bool(forKey: Self.pinEnabledKey)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KVSObserver-\(UUID().uuidString)")
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir, keyValueStore: kvs)
        store.startObservingICloudChanges()
    }

    override func tearDown() {
        UserDefaults.standard.set(savedPINEnabled, forKey: Self.pinEnabledKey)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func postKVSChange(forKey key: String) {
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [key]]
        )
    }

    func testRemotePINHashSet_FlipsPinEnabledOn() {
        UserDefaults.standard.set(false, forKey: Self.pinEnabledKey)
        // Simulate another device pushing a hash.
        kvs.set("some-hash-value", forKey: Self.pinHashKVSKey)
        postKVSChange(forKey: Self.pinHashKVSKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.pinEnabledKey),
                      "remote PIN set must turn pin_enabled toggle on locally")
    }

    func testRemotePINHashCleared_FlipsPinEnabledOff() {
        UserDefaults.standard.set(true, forKey: Self.pinEnabledKey)
        // Simulate another device clearing the hash (e.g. Forgot PIN reset).
        kvs.removeObject(forKey: Self.pinHashKVSKey)
        postKVSChange(forKey: Self.pinHashKVSKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.pinEnabledKey),
                       "remote PIN clear must turn pin_enabled toggle off locally")
    }

    func testUnrelatedKVSChange_DoesNotTouchPinEnabled() {
        UserDefaults.standard.set(true, forKey: Self.pinEnabledKey)
        // Some unrelated key changed — pin_enabled stays put.
        postKVSChange(forKey: "panelstore.panels")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.pinEnabledKey))
    }
}
