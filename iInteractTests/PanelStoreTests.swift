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

// MARK: - ConfigurationMode KVS sync (PanelStore-backed)

/// Tests adopt / reconcile / setConfigurationMode using a shared in-memory
/// KVS and isolated `UserDefaults` suites. All assertions are black-box —
/// state is seeded by the SUT's own write paths so we don't depend on
/// private KVS key strings.
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

    /// Fresh `UserDefaults` per call — registered defaults from AppDelegate
    /// don't leak in because suite names are unique.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "iInteractTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: adoptCloudConfigurationModeIfFirstLaunch

    func testAdoptCloudConfigurationMode_FirstLaunch_NoCloudValue_LeavesDefaultsAlone() {
        let d = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: d)
        // No KVS value to adopt → mode falls through to .default.
        XCTAssertEqual(ConfigurationMode.current(d), .default)
    }

    func testAdoptCloudConfigurationMode_FirstLaunch_AdoptsCloudValue() {
        // Seed the KVS via a "primer" UserDefaults so we use the production
        // write path without touching the test's main `defaults`.
        let primer = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: primer)

        let main = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: main)
        XCTAssertEqual(ConfigurationMode.current(main), .configurable)
    }

    func testAdoptCloudConfigurationMode_NoOpOnSecondCall() {
        // 1. Seed cloud + adopt once.
        let primer = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: primer)

        let main = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: main)
        XCTAssertEqual(ConfigurationMode.current(main), .configurable)

        // 2. User changes mode locally.
        main.set(ConfigurationMode.custom.rawValue, forKey: ConfigurationMode.userDefaultsKey)

        // 3. Another device pushes a different cloud value.
        _ = store.setConfigurationMode(.default, defaults: primer)

        // 4. Adopt is called again (next launch). Should be a no-op because
        //    we already adopted — local intent must NOT be clobbered.
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: main)
        XCTAssertEqual(ConfigurationMode.current(main), .custom,
                       "second adoption must not overwrite local intent")
    }

    // MARK: reconcileConfigurationMode

    func testReconcileConfigurationMode_LocalAndCloudAgree() {
        let d = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: d)
        // Both local and cloud now hold "configurable".
        let resolved = store.reconcileConfigurationMode(defaults: d)
        XCTAssertEqual(resolved, .configurable)
        XCTAssertEqual(ConfigurationMode.current(d), .configurable)
    }

    func testReconcileConfigurationMode_LocalDiffersFromCloud_LocalWins() {
        // Cloud holds "configurable" (via primer); local intent is "custom".
        let primer = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: primer)

        let d = makeIsolatedDefaults()
        d.set(ConfigurationMode.custom.rawValue, forKey: ConfigurationMode.userDefaultsKey)

        let resolved = store.reconcileConfigurationMode(defaults: d)
        XCTAssertEqual(resolved, .custom, "local UserDefaults wins at runtime")

        // Cloud was overwritten — verify by adopting into a fresh defaults.
        let verifier = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: verifier)
        XCTAssertEqual(ConfigurationMode.current(verifier), .custom,
                       "reconcile must have pushed local intent up to KVS")
    }

    func testReconcileConfigurationMode_LocalMissing_FallsBackToDefault() {
        // Use a fresh store with an empty KVS to ensure no carry-over from
        // setUp's shared `kvs` (which is empty here anyway, but be explicit).
        let freshKvs = MemoryKeyValueStore()
        let freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconcileFresh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: freshDir) }
        let freshStore = PanelStore(directory: freshDir, keyValueStore: freshKvs)

        let d = makeIsolatedDefaults()
        let resolved = freshStore.reconcileConfigurationMode(defaults: d)
        XCTAssertEqual(resolved, .default)
    }

    // MARK: setConfigurationMode

    func testSetConfigurationMode_ReturnsTrueOnlyWhenChanged() {
        let d = makeIsolatedDefaults()
        let changed1 = store.setConfigurationMode(.custom, defaults: d)
        let changed2 = store.setConfigurationMode(.custom, defaults: d)
        let changed3 = store.setConfigurationMode(.configurable, defaults: d)
        XCTAssertTrue(changed1, "default → custom is a change")
        XCTAssertFalse(changed2, "custom → custom is a no-op")
        XCTAssertTrue(changed3, "custom → configurable is a change")
    }

    func testSetConfigurationMode_WritesToBothLocalAndCloud() {
        let d = makeIsolatedDefaults()
        _ = store.setConfigurationMode(.configurable, defaults: d)
        // Local was written.
        XCTAssertEqual(ConfigurationMode.current(d), .configurable)
        // Cloud was written — verify by adopting into a fresh defaults.
        let verifier = makeIsolatedDefaults()
        store.adoptCloudConfigurationModeIfFirstLaunch(defaults: verifier)
        XCTAssertEqual(ConfigurationMode.current(verifier), .configurable)
    }
}
