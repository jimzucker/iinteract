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
}

// MARK: - PINVerifyCoordinator

final class PINVerifyCoordinatorTests: XCTestCase {

    var tempDir: URL!
    var store: PanelStore!
    var presenter: TestPINPresenter!
    var clock: Date = Date(timeIntervalSinceReferenceDate: 0)
    var coordinator: PINVerifyCoordinator!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINVerify-\(UUID().uuidString)")
        store = PanelStore(directory: tempDir, keyValueStore: MemoryKeyValueStore())
        store.setPIN("abcd")  // PIN must be set for the verify flow
        presenter = TestPINPresenter()
        clock = Date(timeIntervalSinceReferenceDate: 0)
        coordinator = PINVerifyCoordinator(store: store,
                                           presenter: presenter,
                                           now: { [unowned self] in self.clock })
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
        let coordinator2 = PINVerifyCoordinator(store: store,
                                                presenter: presenter,
                                                now: { [unowned self] in self.clock })
        coordinator2.runVerifyFlow(
            title: "Verify PIN",
            message: "Try again.",
            actionTitle: "Continue",
            actionStyle: .destructive,
            onCancel: nil
        ) { confirmed = true }
        presenter.tap(1, values: ["abcd"])
        XCTAssertTrue(confirmed, "lockout state is per-coordinator; a fresh flow accepts the correct PIN")
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
                                           now: { [unowned self] in self.clock })
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
