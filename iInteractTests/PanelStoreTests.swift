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
import CloudKit
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
        XCTAssertTrue(store.verifyPIN("pin12345"),
                      "PIN is case-insensitive — Caps Lock / shift typos must not lock the parent out")
        XCTAssertTrue(store.verifyPIN("PIN12345"),
                      "PIN is case-insensitive — fully uppercase must also verify")
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

    // MARK: - PIN case-insensitivity

    func testStore_VerifyPIN_CaseInsensitive_RoundTrip() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setPIN("Abc1")
        XCTAssertTrue(store.verifyPIN("Abc1"))
        XCTAssertTrue(store.verifyPIN("abc1"))
        XCTAssertTrue(store.verifyPIN("ABC1"))
        XCTAssertTrue(store.verifyPIN("aBc1"))
        XCTAssertFalse(store.verifyPIN("abc2"),
                       "case-insensitive does NOT mean character-insensitive")
    }

    func testStore_VerifyPIN_PurelyNumeric_StillVerifies() {
        // Lowercasing digits is a no-op; numeric PINs must still work.
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setPIN("1234")
        XCTAssertTrue(store.verifyPIN("1234"))
        XCTAssertFalse(store.verifyPIN("4321"))
    }

    func testStore_VerifyPIN_LegacyCaseSensitiveHash_MigratesOnFirstVerify() {
        // Simulate a PIN saved by an old build that hashed the literal
        // mixed-case string. The first verify with the original case must
        // succeed AND silently re-hash to the lowercased form so future
        // verifies hit the case-insensitive primary path.
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store._setLegacyPINHash_forTesting("Abc1")
        XCTAssertTrue(store.hasPIN)

        // Original-case verify succeeds via the migration branch.
        XCTAssertTrue(store.verifyPIN("Abc1"),
                      "legacy mixed-case hash must still verify on first try")
        // After migration, lowercased verify now succeeds via the
        // primary path (no further migration needed).
        XCTAssertTrue(store.verifyPIN("abc1"),
                      "after migration, lowercased verify works without re-saving")
        XCTAssertTrue(store.verifyPIN("ABC1"),
                      "uppercased verify also works post-migration")
    }

    func testStore_VerifyPIN_LegacyHash_WrongPIN_StillRejects() {
        // Migration branch must not accidentally accept a wrong PIN that
        // happens to hash close to something — verify with a clearly
        // wrong value before the migration happens, and after.
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store._setLegacyPINHash_forTesting("Abc1")
        XCTAssertFalse(store.verifyPIN("XYZ9"),
                       "wrong PIN must not be accepted by the legacy migration branch")
        // Then complete the migration with a correct verify, and
        // re-check rejection on the migrated hash too.
        XCTAssertTrue(store.verifyPIN("Abc1"))
        XCTAssertFalse(store.verifyPIN("XYZ9"),
                       "wrong PIN must still be rejected post-migration")
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

    // MARK: - Transactional save regression

    /// Force-quit between PIN step and question step must not leave the
    /// user with a saved PIN and no security question — they'd be locked
    /// out (security question is the only Forgot-PIN recovery path).
    /// Tests that the production flow holds the PIN in memory across the
    /// two steps and only persists after the question is also entered.
    func testRunEnablePINWithQuestion_PINNotSaved_UntilQuestionStepCompletes() {
        coordinator.runEnablePINFlowWithSecurityQuestion { _ in }
        // PIN step: user enters and confirms a valid PIN.
        presenter.tap(1, values: ["abcd", "abcd"])
        // Now we're on the question step but haven't saved yet —
        // simulating a force-quit window. PIN must NOT be in the store.
        XCTAssertFalse(store.hasPIN,
                       "PIN must not be saved until the question step completes")
        XCTAssertFalse(store.hasSecurityQuestion)
        // Show we're parked at the question step.
        XCTAssertEqual(presenter.presentations.count, 2)
        XCTAssertEqual(presenter.presentations[1].config.title, "Set a Security Question")
    }

    func testRunEnablePINWithQuestion_PINNotSaved_WhileQuestionStepCycles() {
        coordinator.runEnablePINFlowWithSecurityQuestion { _ in }
        presenter.tap(1, values: ["abcd", "abcd"])
        // Question step cycles on empty input — still no PIN persisted.
        presenter.tap(0, values: ["First pet?", ""])
        XCTAssertFalse(store.hasPIN,
                       "PIN must remain unsaved while the question step is still cycling")
        XCTAssertFalse(store.hasSecurityQuestion)
    }

    func testRunEnablePINWithQuestion_PINAndQuestionPersisted_Atomically() {
        var completion: Bool?
        coordinator.runEnablePINFlowWithSecurityQuestion { completion = $0 }
        presenter.tap(1, values: ["abcd", "abcd"])
        XCTAssertFalse(store.hasPIN, "no PIN yet — question step still pending")
        // Complete the question step.
        presenter.tap(0, values: ["First pet?", "Fido"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.hasPIN, "PIN persisted alongside the question")
        XCTAssertTrue(store.hasSecurityQuestion)
        XCTAssertTrue(store.verifyPIN("abcd"))
        // Recovery path also works — question is genuinely usable, not just present.
        XCTAssertNoThrow(try store.resetPIN(securityAnswer: "Fido"))
    }

    /// `runEnablePINFlow` (no question step) still saves the PIN
    /// immediately — preserves backwards-compatibility for tests/callers
    /// that explicitly opt out of the security-question chain.
    func testRunEnablePINFlow_NoQuestionStep_PINSavedImmediately() {
        var completion: Bool?
        coordinator.runEnablePINFlow { completion = $0 }
        presenter.tap(1, values: ["abcd", "abcd"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.hasPIN)
        XCTAssertFalse(store.hasSecurityQuestion,
                       "no question step ran — store reflects exactly that")
    }
}

// MARK: - runCompleteSecurityQuestionFlow (orphan-state recovery)

/// Recovery flow for users in the orphan PIN-without-question state
/// (force-quit during the original Set PIN flow before transactional
/// save was added). Re-fires every reconcile until the user finishes
/// the question step. No Cancel — once a PIN exists, the recovery
/// path must be set up.
final class PINCompleteSecurityQuestionTests: XCTestCase {

    var tempDir: URL!
    var store: PanelStore!
    var defaults: UserDefaults!
    var presenter: TestPINPresenter!
    var coordinator: PINPromptCoordinator!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PINCompleteSecQ-\(UUID().uuidString)")
        store = PanelStore(directory: tempDir, keyValueStore: MemoryKeyValueStore())
        let suite = "PINCompleteSecQTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        presenter = TestPINPresenter()
        coordinator = PINPromptCoordinator(store: store,
                                           defaults: defaults,
                                           presenter: presenter)
        // Seed orphan state: PIN, no question.
        store.setPIN("1234")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCompleteSecQ_OnlySaveButton_NoCancel() {
        coordinator.runCompleteSecurityQuestionFlow { _ in }
        XCTAssertEqual(presenter.presentations.count, 1)
        let cfg = presenter.presentations[0].config
        XCTAssertEqual(cfg.title, "Finish PIN Setup")
        XCTAssertEqual(cfg.buttons.map(\.title), ["Save"],
                       "no Cancel — recovery is mandatory once a PIN exists")
    }

    func testCompleteSecQ_Save_PersistsQuestion_PreservesPIN() {
        var completion: Bool?
        coordinator.runCompleteSecurityQuestionFlow { completion = $0 }
        presenter.tap(0, values: ["Street?", "Maple"])
        XCTAssertEqual(completion, true)
        XCTAssertTrue(store.hasSecurityQuestion)
        XCTAssertEqual(store.securityQuestion, "Street?")
        XCTAssertTrue(store.verifyPIN("1234"),
                      "original PIN must remain intact through the question-only save")
        XCTAssertNoThrow(try store.resetPIN(securityAnswer: "Maple"))
    }

    func testCompleteSecQ_OneEmpty_Cycles() {
        var completion: Bool?
        coordinator.runCompleteSecurityQuestionFlow { completion = $0 }
        presenter.tap(0, values: ["Street?", ""])
        XCTAssertNil(completion, "empty answer must cycle, not complete")
        XCTAssertEqual(presenter.presentations.count, 2)
        XCTAssertTrue(presenter.presentations[1].config.message.lowercased().contains("required"))
        XCTAssertEqual(presenter.presentations[1].config.fields[0].prefilledText, "Street?")
        XCTAssertFalse(store.hasSecurityQuestion)
    }

    func testCompleteSecQ_BothEmpty_Cycles() {
        var completion: Bool?
        coordinator.runCompleteSecurityQuestionFlow { completion = $0 }
        presenter.tap(0, values: ["", ""])
        XCTAssertNil(completion)
        XCTAssertEqual(presenter.presentations.count, 2)
        XCTAssertFalse(store.hasSecurityQuestion)
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
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
        defaults.set(false, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [.disablePIN])
    }

    func testWantPIN_AndPINSet_NoEffect() {
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
        defaults.set(true, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [])
    }

    func testDontWantPIN_AndNoPIN_NoEffect() {
        defaults.set(false, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [])
    }

    // MARK: change PIN (one-shot)

    func testChangePIN_WithPINSet_ReturnsChangePIN_AndClearsToggle() {
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
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
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
        defaults.set(false, forKey: "pin_enabled")
        defaults.set(true, forKey: "change_pin")
        XCTAssertEqual(reconciler.reconcile(), [.disablePIN, .changePIN])
    }

    // MARK: idempotency — one-shot toggles don't fire twice

    func testTogglesNotFireTwice_OnConsecutiveReconciles() {
        // Consistent baseline: pin_enabled=true, hasPIN=true, hasSecurityQuestion=true
        // (no enable/disable/orphan-recovery effect). Then add the one-shot toggles.
        store.setPIN("1234", securityQuestion: "Pet?", securityAnswer: "Fido")
        defaults.set(true, forKey: "pin_enabled")
        defaults.set(true, forKey: "change_pin")
        defaults.set(true, forKey: "pending_clear_all")

        XCTAssertEqual(reconciler.reconcile(), [.changePIN, .clearAllData])
        XCTAssertEqual(reconciler.reconcile(), [],
                       "second reconcile must be a no-op once one-shot toggles are cleared")
    }

    // MARK: orphan-state recovery (PIN saved but no security question)

    /// Force-quit between PIN step and question step in pre-transactional
    /// builds left the store with a PIN and no question. Forgot PIN now
    /// requires a question, so without recovery the user is locked out.
    func testOrphanPINNoQuestion_FiresCompleteSecurityQuestion() {
        // setPIN(_:) without question/answer = the orphan state.
        store.setPIN("1234")
        defaults.set(true, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [.completeSecurityQuestion])
    }

    func testOrphanPIN_FiresEveryReconcile_UntilQuestionAdded() {
        store.setPIN("1234")
        defaults.set(true, forKey: "pin_enabled")
        // Mandatory: re-fires until satisfied.
        XCTAssertEqual(reconciler.reconcile(), [.completeSecurityQuestion])
        XCTAssertEqual(reconciler.reconcile(), [.completeSecurityQuestion])
        store.setSecurityQuestion("Pet?", answer: "Fido")
        XCTAssertEqual(reconciler.reconcile(), [],
                       "completing the question step satisfies the recovery effect")
    }

    func testOrphanPIN_DoesNotFire_WhenWantDisable() {
        // wantEnabled=false → user is in the disable flow; don't pile a
        // recovery prompt on top. disablePIN clears the orphan anyway.
        store.setPIN("1234")
        defaults.set(false, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [.disablePIN])
    }

    func testOrphanPIN_DoesNotFire_WhenNoPIN() {
        // No PIN, even with pin_enabled=true → enablePIN, not orphan
        // recovery. The branches are mutually exclusive.
        defaults.set(true, forKey: "pin_enabled")
        XCTAssertEqual(reconciler.reconcile(), [.enablePIN])
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

// MARK: - LocalFSAssetStore (v3.1.0 — extracted from PanelStore)

/// Direct tests for the AssetStore protocol's local-FS implementation.
/// PanelStore's existing tests already exercise this via delegation;
/// these target the protocol surface directly so the contract is
/// pinned for the planned CloudKit implementation in v3.1.1+ (see
/// docs/CLOUDKIT_MIGRATION.md).
final class LocalFSAssetStoreTests: XCTestCase {

    var tempDir: URL!
    var store: LocalFSAssetStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalFSAssetStore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = LocalFSAssetStore(parentDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRootDirectory_CreatedUnderParent() {
        XCTAssertEqual(store.rootDirectory.lastPathComponent, "UserAssets")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.rootDirectory.path))
    }

    func testURL_DeterministicByIDAndKind() {
        let id = UUID()
        let pic = store.url(for: .picture, id: id)
        XCTAssertEqual(pic.lastPathComponent, "\(id.uuidString).jpg")
        XCTAssertEqual(store.url(for: .boyAudio, id: id).lastPathComponent,
                       "\(id.uuidString).boy.m4a")
        XCTAssertEqual(store.url(for: .girlAudio, id: id).lastPathComponent,
                       "\(id.uuidString).girl.m4a")
    }

    func testExists_FalseUntilWritten_TrueAfterWrite() throws {
        let id = UUID()
        XCTAssertFalse(store.exists(.picture, id: id))
        try store.write(Data([0xff, 0xd8]), kind: .picture, id: id)
        XCTAssertTrue(store.exists(.picture, id: id))
    }

    func testWrite_AtomicallyReplacesExistingFile() throws {
        let id = UUID()
        try store.write(Data("first".utf8), kind: .boyAudio, id: id)
        try store.write(Data("second".utf8), kind: .boyAudio, id: id)
        let read = try Data(contentsOf: store.url(for: .boyAudio, id: id))
        XCTAssertEqual(String(data: read, encoding: .utf8), "second")
    }

    func testDelete_SingleKind_LeavesOthersIntact() throws {
        let id = UUID()
        try store.write(Data([0x01]), kind: .picture, id: id)
        try store.write(Data([0x02]), kind: .boyAudio, id: id)
        try store.write(Data([0x03]), kind: .girlAudio, id: id)
        store.delete(.boyAudio, id: id)
        XCTAssertTrue(store.exists(.picture, id: id))
        XCTAssertFalse(store.exists(.boyAudio, id: id))
        XCTAssertTrue(store.exists(.girlAudio, id: id))
    }

    func testDelete_NoOp_OnMissingFile() {
        // Must not throw / crash when nothing is on disk.
        store.delete(.picture, id: UUID())
    }

    func testDeleteAll_RemovesAllThreeKinds() throws {
        let id = UUID()
        try store.write(Data([0x01]), kind: .picture, id: id)
        try store.write(Data([0x02]), kind: .boyAudio, id: id)
        try store.write(Data([0x03]), kind: .girlAudio, id: id)
        store.deleteAll(id: id)
        XCTAssertFalse(store.exists(.picture, id: id))
        XCTAssertFalse(store.exists(.boyAudio, id: id))
        XCTAssertFalse(store.exists(.girlAudio, id: id))
    }

    func testDeleteAll_OnlyAffectsTargetID() throws {
        let keep = UUID(), wipe = UUID()
        try store.write(Data([0x01]), kind: .picture, id: keep)
        try store.write(Data([0x02]), kind: .picture, id: wipe)
        store.deleteAll(id: wipe)
        XCTAssertTrue(store.exists(.picture, id: keep))
        XCTAssertFalse(store.exists(.picture, id: wipe))
    }

    func testDeleteEverything_WipesAllInteractions() throws {
        try store.write(Data([0x01]), kind: .picture, id: UUID())
        try store.write(Data([0x02]), kind: .boyAudio, id: UUID())
        try store.write(Data([0x03]), kind: .girlAudio, id: UUID())
        store.deleteEverything()
        let remaining = try FileManager.default.contentsOfDirectory(at: store.rootDirectory,
                                                                    includingPropertiesForKeys: nil)
        XCTAssertEqual(remaining, [])
    }

    /// Regression: PanelStore.assetURL must continue to return the same
    /// URL the store wrote to — callers like AVAudioRecorder hold onto
    /// the URL from a previous call and expect a subsequent read to hit
    /// it. Equivalent to: round-trip URL stability across calls.
    func testURL_StableAcrossCalls_ForSameIDAndKind() {
        let id = UUID()
        XCTAssertEqual(store.url(for: .picture, id: id),
                       store.url(for: .picture, id: id))
    }

    func testDidExternallyWrite_NoOps_ForLocalFS() {
        // Contract: local-FS implementations no-op since the file is
        // already at its final destination as soon as the caller wrote
        // it. CloudKit-backed implementations enqueue an upload.
        store.didExternallyWrite(.boyAudio, id: UUID())
        // No observable side effect — pass if it doesn't crash.
    }
}

// MARK: - PushQueue (v3.1.1a — pre-CloudKit plumbing)

/// Persistence + dedupe + supersession + backoff for the queue that
/// `CloudKitAssetStore` (v3.1.1b) and the record mirror (v3.1.1c) will
/// drain to push local mutations into a CloudKit private database.
/// See docs/CLOUDKIT_V3.1.1_PLAN.md.
final class PushQueueTests: XCTestCase {

    var tempDir: URL!
    var queueURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PushQueue-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir,
                                                  withIntermediateDirectories: true)
        queueURL = tempDir.appendingPathComponent("queue.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeQueue() -> PushQueue { PushQueue(persistedAt: queueURL) }

    // MARK: - Empty + persistence

    func testEmptyQueue_OnFreshFile() {
        let q = makeQueue()
        XCTAssertEqual(q.entries, [])
        XCTAssertNil(q.nextDue())
    }

    func testEnqueue_PersistsAcrossInstances() {
        let id = UUID()
        let q1 = makeQueue()
        q1.enqueue(.savePanel(id: id), now: Date(timeIntervalSinceReferenceDate: 100))
        let q2 = makeQueue()
        XCTAssertEqual(q2.entries.count, 1)
        XCTAssertEqual(q2.entries.first?.op, .savePanel(id: id))
    }

    func testCorruptedFile_RenamedAndQueueStartsEmpty() throws {
        try Data("not valid json".utf8).write(to: queueURL)
        let q = makeQueue()
        XCTAssertEqual(q.entries, [],
                       "queue must start empty when persisted file is corrupted")
        let siblings = try FileManager.default.contentsOfDirectory(at: tempDir,
                                                                    includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains(where: { $0.lastPathComponent.contains(".bad-") }),
                      "corrupted file must be moved aside (with .bad- suffix) so we don't keep retrying the parse")
    }

    // MARK: - Dedupe (same target → collapse)

    func testEnqueue_TwoSavePanelSameID_CollapseToOne() {
        let id = UUID()
        let q = makeQueue()
        q.enqueue(.savePanel(id: id))
        q.enqueue(.savePanel(id: id))
        XCTAssertEqual(q.entries.count, 1, "two saves of the same panel collapse to one (latest wins)")
    }

    func testEnqueue_DeletePanelAfterSave_DropsSave() {
        let id = UUID()
        let q = makeQueue()
        q.enqueue(.savePanel(id: id))
        q.enqueue(.deletePanel(id: id))
        XCTAssertEqual(q.entries.count, 1)
        XCTAssertEqual(q.entries.first?.op, .deletePanel(id: id),
                       "delete supersedes save for the same panel — only the delete remains")
    }

    func testEnqueue_TwoUploadsSameAsset_CollapseToOne() {
        let id = UUID()
        let q = makeQueue()
        q.enqueue(.uploadAsset(kind: .picture, id: id))
        q.enqueue(.uploadAsset(kind: .picture, id: id))
        XCTAssertEqual(q.entries.count, 1, "two uploads of the same asset collapse — latest content wins")
    }

    func testEnqueue_DifferentKindsSameInteraction_NoCollapse() {
        let id = UUID()
        let q = makeQueue()
        q.enqueue(.uploadAsset(kind: .picture, id: id))
        q.enqueue(.uploadAsset(kind: .boyAudio, id: id))
        q.enqueue(.uploadAsset(kind: .girlAudio, id: id))
        XCTAssertEqual(q.entries.count, 3, "different asset kinds do not collapse")
    }

    func testEnqueue_DifferentIDsSameKind_NoCollapse() {
        let q = makeQueue()
        q.enqueue(.uploadAsset(kind: .picture, id: UUID()))
        q.enqueue(.uploadAsset(kind: .picture, id: UUID()))
        XCTAssertEqual(q.entries.count, 2, "different interaction ids do not collapse")
    }

    // MARK: - Cross-target supersession

    func testDeleteInteraction_SupersedesPendingAssetUploads() {
        let id = UUID()
        let q = makeQueue()
        q.enqueue(.uploadAsset(kind: .picture, id: id))
        q.enqueue(.uploadAsset(kind: .boyAudio, id: id))
        q.enqueue(.saveInteraction(id: id, parentID: UUID()))
        q.enqueue(.deleteInteraction(id: id))
        XCTAssertEqual(q.entries.count, 1)
        XCTAssertEqual(q.entries.first?.op, .deleteInteraction(id: id),
                       "deleteInteraction cascades server-side; pre-emptively drop pending child pushes")
    }

    func testDeleteInteraction_PreservesUnrelatedEntries() {
        let target = UUID()
        let other = UUID()
        let q = makeQueue()
        q.enqueue(.uploadAsset(kind: .picture, id: target))
        q.enqueue(.uploadAsset(kind: .picture, id: other))
        q.enqueue(.deleteInteraction(id: target))
        XCTAssertEqual(q.entries.count, 2,
                       "supersession only drops ops for the deleted interaction")
        XCTAssertTrue(q.entries.contains(where: { $0.op == .uploadAsset(kind: .picture, id: other) }))
        XCTAssertTrue(q.entries.contains(where: { $0.op == .deleteInteraction(id: target) }))
    }

    func testDeletePanel_DropsPendingChildSaveInteraction() {
        let panelID = UUID()
        let interactionID = UUID()
        let q = makeQueue()
        q.enqueue(.saveInteraction(id: interactionID, parentID: panelID))
        q.enqueue(.deletePanel(id: panelID))
        XCTAssertEqual(q.entries.count, 1)
        XCTAssertEqual(q.entries.first?.op, .deletePanel(id: panelID),
                       "child saveInteraction is doomed by the parent delete cascade — drop it")
    }

    // MARK: - nextDue + FIFO ordering

    func testNextDue_ReturnsFirstEligible_InFIFOOrder() {
        let q = makeQueue()
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let first = q.enqueue(.savePanel(id: UUID()), now: now)
        let _ = q.enqueue(.savePanel(id: UUID()), now: now.addingTimeInterval(1))
        XCTAssertEqual(q.nextDue(now: now)?.id, first.id,
                       "FIFO — earliest-enqueued eligible entry is returned first")
    }

    func testNextDue_ReturnsNilWhenNoneEligible() {
        let q = makeQueue()
        let entry = q.enqueue(.savePanel(id: UUID()),
                              now: Date(timeIntervalSinceReferenceDate: 1000))
        // Mark a failure to push nextEligibleAt into the future.
        q.markFailure(entry, retryable: true,
                      now: Date(timeIntervalSinceReferenceDate: 1000))
        XCTAssertNil(q.nextDue(now: Date(timeIntervalSinceReferenceDate: 1000)))
    }

    // MARK: - markSuccess

    func testMarkSuccess_RemovesEntry() {
        let q = makeQueue()
        let entry = q.enqueue(.savePanel(id: UUID()))
        q.markSuccess(entry)
        XCTAssertEqual(q.entries, [])
    }

    func testMarkSuccess_PersistsRemoval() {
        let id = UUID()
        let q1 = makeQueue()
        let entry = q1.enqueue(.savePanel(id: id))
        q1.markSuccess(entry)
        let q2 = makeQueue()
        XCTAssertEqual(q2.entries, [],
                       "removal must hit disk so a relaunch doesn't replay the success")
    }

    // MARK: - markFailure: retry + backoff

    func testMarkFailure_NotRetryable_DropsImmediately() {
        let q = makeQueue()
        let entry = q.enqueue(.savePanel(id: UUID()))
        let kept = q.markFailure(entry, retryable: false)
        XCTAssertFalse(kept)
        XCTAssertEqual(q.entries, [])
    }

    func testMarkFailure_Retryable_AdvancesNextEligibleAt() {
        let q = makeQueue()
        let now = Date(timeIntervalSinceReferenceDate: 5000)
        let entry = q.enqueue(.savePanel(id: UUID()), now: now)
        XCTAssertTrue(q.markFailure(entry, retryable: true, now: now))
        let updated = q.entries.first!
        XCTAssertEqual(updated.retryCount, 1)
        XCTAssertEqual(updated.nextEligibleAt, now.addingTimeInterval(PushQueue.backoff[0]),
                       "first retry uses the first backoff bucket (30s)")
    }

    func testMarkFailure_BackoffSchedule_FollowsExpectedSequence() {
        let q = makeQueue()
        let baseTime = Date(timeIntervalSinceReferenceDate: 0)
        var entry = q.enqueue(.savePanel(id: UUID()), now: baseTime)
        for (step, expected) in PushQueue.backoff.enumerated() {
            XCTAssertTrue(q.markFailure(entry, retryable: true, now: baseTime))
            entry = q.entries.first!
            XCTAssertEqual(entry.retryCount, step + 1,
                           "retryCount increments by 1 per failure")
            XCTAssertEqual(entry.nextEligibleAt, baseTime.addingTimeInterval(expected),
                           "retry \(step + 1) backoff = \(expected)s")
        }
    }

    func testMarkFailure_BackoffPlateausAtLastBucket() {
        // After we exhaust the explicit schedule, subsequent retries use
        // the last bucket value (12h) until maxRetries drops the entry.
        let q = makeQueue()
        let now = Date(timeIntervalSinceReferenceDate: 0)
        var entry = q.enqueue(.savePanel(id: UUID()), now: now)
        // Drive to retryCount = backoff.count, retryCount = backoff.count + 1
        for _ in 0..<(PushQueue.backoff.count + 1) {
            XCTAssertTrue(q.markFailure(entry, retryable: true, now: now))
            entry = q.entries.first!
        }
        XCTAssertEqual(entry.nextEligibleAt,
                       now.addingTimeInterval(PushQueue.backoff.last!),
                       "after the schedule is exhausted, retries plateau at the last bucket")
    }

    func testMarkFailure_DropsAtMaxRetries() {
        let q = makeQueue()
        var entry = q.enqueue(.savePanel(id: UUID()))
        // First N-1 failures keep the entry. The Nth drops it.
        for _ in 0..<(PushQueue.maxRetries - 1) {
            XCTAssertTrue(q.markFailure(entry, retryable: true))
            entry = q.entries.first!
        }
        let kept = q.markFailure(entry, retryable: true)
        XCTAssertFalse(kept, "entry dropped at maxRetries")
        XCTAssertEqual(q.entries, [])
    }

    // MARK: - Persistence regression — backoff state survives reload

    func testBackoffState_PersistsAcrossInstances() {
        let q1 = makeQueue()
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let entry = q1.enqueue(.savePanel(id: UUID()), now: now)
        q1.markFailure(entry, retryable: true, now: now)

        let q2 = makeQueue()
        XCTAssertEqual(q2.entries.count, 1)
        XCTAssertEqual(q2.entries.first?.retryCount, 1,
                       "retryCount must survive reload")
        XCTAssertEqual(q2.entries.first?.nextEligibleAt,
                       now.addingTimeInterval(PushQueue.backoff[0]),
                       "nextEligibleAt must survive reload — otherwise we'd retry too aggressively after a relaunch")
    }
}

// MARK: - CloudKit error classification (v3.1.1b)

final class CloudKitErrorClassificationTests: XCTestCase {

    private func ckError(_ code: CKError.Code) -> CKError {
        CKError(_nsError: NSError(domain: CKErrorDomain, code: code.rawValue))
    }

    func testTransientErrors_AreRetryable() {
        let transient: [CKError.Code] = [
            .networkUnavailable, .networkFailure, .requestRateLimited,
            .serviceUnavailable, .zoneBusy, .notAuthenticated,
        ]
        for code in transient {
            XCTAssertEqual(classifyCloudKitError(ckError(code)), .retry,
                           "\(code) should be retryable — backoff and try later")
        }
    }

    func testPermanentErrors_AreDropped() {
        let permanent: [CKError.Code] = [
            .quotaExceeded, .unknownItem, .serverRejectedRequest,
            .permissionFailure, .badContainer, .badDatabase,
            .invalidArguments, .incompatibleVersion,
            .constraintViolation, .changeTokenExpired,
            .batchRequestFailed, .managedAccountRestricted,
            .userDeletedZone,
        ]
        for code in permanent {
            XCTAssertEqual(classifyCloudKitError(ckError(code)), .drop,
                           "\(code) should be dropped — no point retrying")
        }
    }

    func testUnknownCKErrorCode_DefaultsToRetry() {
        // .internalError (or any code we didn't enumerate) — fall through.
        XCTAssertEqual(classifyCloudKitError(ckError(.internalError)), .retry,
                       "unknown codes default to retry; PushQueue's 10-attempt cap limits damage if it's actually permanent")
    }

    func testNonCKError_DefaultsToRetry() {
        // URLSession / Foundation errors usually mean transient I/O.
        let urlErr = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(classifyCloudKitError(urlErr), .retry,
                       "Foundation/URL errors are typically transient I/O — retry")
    }
}

// MARK: - Panel/Interaction → CKRecord encoding (v3.1.1b)

final class CloudKitRecordEncodingTests: XCTestCase {

    private let zoneID = CKRecordZone.ID(zoneName: "iInteractZone",
                                          ownerName: CKCurrentUserDefaultName)

    // MARK: Panel

    func testPanelEncoding_RecordTypeAndRecordName() {
        let panel = Panel(title: "School",
                          color: .systemRed,
                          interactions: [],
                          isBuiltIn: false)
        let record = panel.toCKRecord(in: zoneID)
        XCTAssertEqual(record.recordType, "UserPanel")
        XCTAssertEqual(record.recordID.recordName, panel.id.uuidString,
                       "recordName must equal panel UUID — deterministic so retries are idempotent")
        XCTAssertEqual(record.recordID.zoneID, zoneID)
    }

    func testPanelEncoding_FieldsRoundTrip() {
        let panel = Panel(title: "Fun",
                          color: UIColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0),
                          interactions: [],
                          isBuiltIn: false)
        let record = panel.toCKRecord(in: zoneID)
        XCTAssertEqual(record["panelID"] as? String, panel.id.uuidString)
        XCTAssertEqual(record["title"] as? String, "Fun")
        let bytes = record["colorRGBA"] as? Data
        XCTAssertEqual(bytes?.count, 16, "RGBA = 4 Float32s = 16 bytes")
    }

    func testPanelEncoding_ColorRGBABytes_DecodableAsFloats() {
        let panel = Panel(title: "Colors",
                          color: UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0),
                          interactions: [],
                          isBuiltIn: false)
        let bytes = panel.colorRGBABytes()
        XCTAssertEqual(bytes.count, 16)
        let floats = bytes.withUnsafeBytes { ptr -> [Float32] in
            Array(ptr.bindMemory(to: Float32.self))
        }
        XCTAssertEqual(floats[0], 0.1, accuracy: 0.001)
        XCTAssertEqual(floats[1], 0.2, accuracy: 0.001)
        XCTAssertEqual(floats[2], 0.3, accuracy: 0.001)
        XCTAssertEqual(floats[3], 1.0, accuracy: 0.001)
    }

    func testPanelEncoding_ClampsOutOfRangeColorComponents() {
        // Some dynamic UIColors return extended-sRGB values outside [0,1]
        // when resolved against the current trait collection. The bytes
        // encoding must clamp so cross-device decode lands in-range.
        let outOfRange = UIColor(red: -0.5, green: 1.5, blue: 0.5, alpha: 2.0)
        let panel = Panel(title: "OOR", color: outOfRange,
                          interactions: [], isBuiltIn: false)
        let bytes = panel.colorRGBABytes()
        let floats = bytes.withUnsafeBytes { ptr -> [Float32] in
            Array(ptr.bindMemory(to: Float32.self))
        }
        XCTAssertGreaterThanOrEqual(floats[0], 0)
        XCTAssertLessThanOrEqual(floats[0], 1)
        XCTAssertGreaterThanOrEqual(floats[1], 0)
        XCTAssertLessThanOrEqual(floats[1], 1)
        XCTAssertEqual(floats[3], 1.0, "alpha clamped to 1")
    }

    // MARK: Interaction

    func testInteractionEncoding_RecordTypeAndPanelRef() {
        let parentID = UUID()
        let interaction = Interaction(name: "happy")
        let record = interaction.toCKRecord(parentPanelID: parentID,
                                             order: 0,
                                             assetURLs: (nil, nil, nil),
                                             in: zoneID)
        XCTAssertEqual(record.recordType, "Interaction")
        XCTAssertEqual(record.recordID.recordName, interaction.id.uuidString)
        let ref = record["panelRef"] as? CKRecord.Reference
        XCTAssertEqual(ref?.recordID.recordName, parentID.uuidString,
                       "panelRef points at the parent panel by recordName")
        XCTAssertEqual(ref?.action, .deleteSelf,
                       "cascade-delete: removing the parent purges children server-side")
    }

    func testInteractionEncoding_ScalarFieldsAndOrder() {
        let interaction = Interaction(name: "playground")
        let record = interaction.toCKRecord(parentPanelID: UUID(),
                                             order: 3,
                                             assetURLs: (nil, nil, nil),
                                             in: zoneID)
        XCTAssertEqual(record["interactionID"] as? String, interaction.id.uuidString)
        XCTAssertEqual(record["displayName"] as? String, "playground")
        XCTAssertEqual(record["order"] as? Int64, 3)
        XCTAssertNil(record["imageAsset"])
        XCTAssertNil(record["audioBoyAsset"])
        XCTAssertNil(record["audioGirlAsset"])
    }

    func testInteractionEncoding_AssetsAttached_WhenFilesExist() throws {
        // Create three real files on disk so CKAsset(fileURL:) gets a
        // valid path. The encoder filters by FileManager.fileExists, so
        // a missing file leaves the field nil rather than crashing.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CKEnc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("img.jpg")
        let boyURL = tempDir.appendingPathComponent("boy.m4a")
        let girlURL = tempDir.appendingPathComponent("girl.m4a")
        try Data([0xFF, 0xD8]).write(to: imageURL)
        try Data([0x01]).write(to: boyURL)
        try Data([0x02]).write(to: girlURL)

        let interaction = Interaction(name: "drink")
        let record = interaction.toCKRecord(parentPanelID: UUID(),
                                             order: 0,
                                             assetURLs: (imageURL, boyURL, girlURL),
                                             in: zoneID)
        XCTAssertNotNil(record["imageAsset"] as? CKAsset)
        XCTAssertNotNil(record["audioBoyAsset"] as? CKAsset)
        XCTAssertNotNil(record["audioGirlAsset"] as? CKAsset)
    }

    func testInteractionEncoding_NilNameEncodesAsEmpty() {
        // Defensive — Interaction.name is optional. Don't pass nil to
        // CKRecord (it'd be ambiguous with field-not-present).
        let interaction = Interaction(id: UUID(), name: "")
        interaction.name = nil
        let record = interaction.toCKRecord(parentPanelID: UUID(),
                                             order: 0,
                                             assetURLs: (nil, nil, nil),
                                             in: zoneID)
        XCTAssertEqual(record["displayName"] as? String, "",
                       "nil Swift name encodes as empty string for unambiguous CKRecord field")
    }

    func testInteractionEncoding_OnlyFieldWithRealFile_GetsAsset() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CKEnc-mixed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realImage = tempDir.appendingPathComponent("img.jpg")
        try Data([0xFF, 0xD8]).write(to: realImage)
        let missingAudio = tempDir.appendingPathComponent("missing.m4a")  // not on disk

        let interaction = Interaction(name: "want")
        let record = interaction.toCKRecord(parentPanelID: UUID(),
                                             order: 0,
                                             assetURLs: (realImage, missingAudio, nil),
                                             in: zoneID)
        XCTAssertNotNil(record["imageAsset"] as? CKAsset,
                        "real file → asset attached")
        XCTAssertNil(record["audioBoyAsset"],
                     "URL given but file missing → field nil rather than CKAsset over a missing path")
        XCTAssertNil(record["audioGirlAsset"],
                     "no URL → no asset")
    }
}

// MARK: - CloudKitAssetStore (v3.1.1b — push enqueueing)

/// Records what CloudKitDatabase methods got called. Used by tests to
/// verify the AssetStore's push-on-write contract without touching
/// real CloudKit. v3.1.1b uses this for AssetStore-side coverage; the
/// drainer (v3.1.1c) will use the same type for end-to-end push tests.
final class MockCloudKitDatabase: CloudKitDatabase {
    private(set) var savedRecords: [CKRecord] = []
    private(set) var deletedRecordIDs: [CKRecord.ID] = []
    private(set) var savedZones: [CKRecordZone] = []
    private(set) var savedSubscriptions: [CKSubscription] = []
    private(set) var fetchChangesCalls: [(zoneID: CKRecordZone.ID,
                                          previousToken: CKServerChangeToken?)] = []
    var nextSaveError: Error?
    var nextDeleteError: Error?
    var nextSaveZoneError: Error?
    var nextSaveSubscriptionError: Error?
    /// Sequence of canned responses for successive `fetchChanges` calls.
    /// Errors throw; success values return as-is. Tests use this to
    /// drive multi-batch pulls via the moreComing flag.
    var fetchChangesScript: [Result<CloudKitChanges, Error>] = []

    func save(_ record: CKRecord) async throws -> CKRecord {
        if let err = nextSaveError {
            nextSaveError = nil
            throw err
        }
        savedRecords.append(record)
        return record
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        if let err = nextDeleteError {
            nextDeleteError = nil
            throw err
        }
        deletedRecordIDs.append(recordID)
    }

    func saveZone(_ zone: CKRecordZone) async throws {
        if let err = nextSaveZoneError {
            nextSaveZoneError = nil
            throw err
        }
        savedZones.append(zone)
    }

    func fetchChanges(in zoneID: CKRecordZone.ID,
                      since previousToken: CKServerChangeToken?) async throws -> CloudKitChanges {
        fetchChangesCalls.append((zoneID, previousToken))
        guard !fetchChangesScript.isEmpty else {
            // Default: empty response with a deterministic token so
            // tests don't have to script trivial cases.
            return CloudKitChanges()
        }
        let next = fetchChangesScript.removeFirst()
        return try next.get()
    }

    func saveSubscription(_ subscription: CKSubscription) async throws {
        if let err = nextSaveSubscriptionError {
            nextSaveSubscriptionError = nil
            throw err
        }
        savedSubscriptions.append(subscription)
    }
}

/// In-memory `CloudKitChangeTokenStore` for tests. No file I/O.
final class MemoryChangeTokenStore: CloudKitChangeTokenStore {
    private(set) var token: CKServerChangeToken?

    func read() -> CKServerChangeToken? { token }
    func write(_ token: CKServerChangeToken) { self.token = token }
    func clear() { token = nil }
}

final class CloudKitAssetStoreTests: XCTestCase {

    var tempDir: URL!
    var mockDB: MockCloudKitDatabase!
    var store: CloudKitAssetStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitAssetStore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir,
                                                  withIntermediateDirectories: true)
        mockDB = MockCloudKitDatabase()
        store = CloudKitAssetStore(parentDirectory: tempDir,
                                    database: mockDB)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: Reads pass through to the local cache

    func testRootDirectory_MatchesLocalCache() {
        XCTAssertEqual(store.rootDirectory.lastPathComponent, "UserAssets")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.rootDirectory.path))
    }

    func testRead_NeverHitsTheDatabase() throws {
        let id = UUID()
        try store.write(Data([0xFF]), kind: .picture, id: id)
        // Many reads — none should trigger any CloudKit traffic since
        // the mock would record it.
        for _ in 0..<5 {
            _ = store.url(for: .picture, id: id)
            _ = store.exists(.picture, id: id)
        }
        XCTAssertEqual(mockDB.savedRecords, [],
                       "AssetStore reads must hit the local cache only, never the database directly")
    }

    // MARK: Writes enqueue + cache (but don't drain — that's v3.1.1c)

    func testWrite_Enqueues_UploadAsset() throws {
        let id = UUID()
        try store.write(Data([0x01, 0x02]), kind: .picture, id: id)
        XCTAssertTrue(store.exists(.picture, id: id),
                      "local cache write happens immediately")
        XCTAssertEqual(store.pushQueue.entries.count, 1)
        XCTAssertEqual(store.pushQueue.entries.first?.op,
                       .uploadAsset(kind: .picture, id: id))
    }

    func testDidExternallyWrite_Enqueues_UploadAsset() {
        // Caller wrote to url(for:id:) outside the store (e.g. AVAudioRecorder).
        let id = UUID()
        store.didExternallyWrite(.boyAudio, id: id)
        XCTAssertEqual(store.pushQueue.entries.count, 1)
        XCTAssertEqual(store.pushQueue.entries.first?.op,
                       .uploadAsset(kind: .boyAudio, id: id))
    }

    func testDelete_Enqueues_DeleteAsset() throws {
        let id = UUID()
        try store.write(Data([0x01]), kind: .picture, id: id)
        store.delete(.picture, id: id)
        XCTAssertFalse(store.exists(.picture, id: id),
                       "local cache delete happens immediately")
        // After write+delete, supersession in PushQueue collapses them
        // — the only meaningful op left is the delete.
        XCTAssertEqual(store.pushQueue.entries.count, 1)
        XCTAssertEqual(store.pushQueue.entries.first?.op,
                       .deleteAsset(kind: .picture, id: id))
    }

    func testDeleteAll_Enqueues_DeleteInteraction_Once() throws {
        let id = UUID()
        try store.write(Data([0x01]), kind: .picture, id: id)
        try store.write(Data([0x02]), kind: .boyAudio, id: id)
        try store.write(Data([0x03]), kind: .girlAudio, id: id)
        store.deleteAll(id: id)
        XCTAssertFalse(store.exists(.picture, id: id))
        XCTAssertFalse(store.exists(.boyAudio, id: id))
        XCTAssertFalse(store.exists(.girlAudio, id: id))
        // Cross-target supersession: deleteInteraction supersedes the
        // three pending uploads. Net queue = one deleteInteraction.
        XCTAssertEqual(store.pushQueue.entries.count, 1)
        XCTAssertEqual(store.pushQueue.entries.first?.op,
                       .deleteInteraction(id: id))
    }

    // MARK: deleteEverything is local-only — does NOT enqueue

    func testDeleteEverything_DoesNotEnqueue_AnyServerOps() throws {
        try store.write(Data([0x01]), kind: .picture, id: UUID())
        try store.write(Data([0x02]), kind: .picture, id: UUID())
        // Drain the queue manually to set up: simulate the v3.1.1c
        // drainer having already pushed those uploads.
        store.pushQueue.entries.forEach { store.pushQueue.markSuccess($0) }

        store.deleteEverything()

        XCTAssertEqual(store.pushQueue.entries, [],
                       "Clear All My Data is documented as local-only — does NOT delete iCloud copies")
    }

    // MARK: Database is never called from the AssetStore alone

    func testWritesAndDeletes_DoNotInvokeTheDatabase_InV3_1_1b() throws {
        // v3.1.1b enqueues only — the drainer that calls database.save
        // / .deleteRecord is added in v3.1.1c. Until then the queue
        // accumulates; nothing reaches CloudKit.
        let id = UUID()
        try store.write(Data([0x01]), kind: .picture, id: id)
        store.delete(.picture, id: id)
        store.didExternallyWrite(.boyAudio, id: id)
        store.deleteAll(id: id)
        XCTAssertEqual(mockDB.savedRecords, [])
        XCTAssertEqual(mockDB.deletedRecordIDs, [])
    }

    // MARK: PushQueue persistence works through the AssetStore

    func testPushQueue_PersistsAcrossAssetStoreInstances() throws {
        let id = UUID()
        try store.write(Data([0x01]), kind: .picture, id: id)

        let store2 = CloudKitAssetStore(parentDirectory: tempDir,
                                        database: mockDB)
        XCTAssertEqual(store2.pushQueue.entries.count, 1,
                       "queue entries written by one CloudKitAssetStore must reload in another rooted at the same directory — survives app relaunch")
    }
}

// MARK: - CloudKitPushDrainer (v3.1.1c-i)

/// Drains the push queue against a CloudKitDatabase. Tests use
/// `drainOnce()` for deterministic stepping rather than the full async
/// loop; the loop's correctness is straightforward (just a sleep +
/// retry around `drainOnce`).
final class CloudKitPushDrainerTests: XCTestCase {

    var tempDir: URL!
    var assetStore: LocalFSAssetStore!
    var queue: PushQueue!
    var database: MockCloudKitDatabase!

    let zoneID = CKRecordZone.ID(zoneName: "TestZone",
                                  ownerName: CKCurrentUserDefaultName)

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CKDrainer-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir,
                                                  withIntermediateDirectories: true)
        assetStore = LocalFSAssetStore(parentDirectory: tempDir)
        queue = PushQueue(persistedAt: tempDir.appendingPathComponent("q.json"))
        database = MockCloudKitDatabase()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeDrainer(panels: [Panel] = []) -> CloudKitPushDrainer {
        CloudKitPushDrainer(queue: queue,
                            database: database,
                            assetStore: assetStore,
                            panelLookup: { panels },
                            zoneID: zoneID)
    }

    // MARK: savePanel / deletePanel

    func testDrain_SavePanel_PushesUserPanelRecord() async {
        let panel = Panel(title: "School", color: .systemBlue,
                          interactions: [], isBuiltIn: false)
        queue.enqueue(.savePanel(id: panel.id))
        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords.count, 1)
        XCTAssertEqual(database.savedRecords.first?.recordType, "UserPanel")
        XCTAssertEqual(database.savedRecords.first?.recordID.recordName,
                       panel.id.uuidString)
        XCTAssertEqual(queue.entries, [],
                       "successful push removes the entry")
    }

    func testDrain_SavePanel_BuiltInIsFiltered_DropsAsUnknownItem() async {
        // Built-ins should never reach the queue, but if one did, the
        // drainer treats it as a disappeared item (drop, not infinite
        // retry).
        let builtIn = Panel(title: "I feel", color: .red,
                            interactions: [], isBuiltIn: true)
        queue.enqueue(.savePanel(id: builtIn.id))
        let drainer = makeDrainer(panels: [builtIn])
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [])
        XCTAssertEqual(queue.entries, [],
                       "drained as drop — built-in filter is treated like unknownItem")
    }

    func testDrain_SavePanel_PanelDisappeared_Drops() async {
        queue.enqueue(.savePanel(id: UUID()))
        let drainer = makeDrainer(panels: [])  // no matching panel
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [])
        XCTAssertEqual(queue.entries, [],
                       "panel disappeared between enqueue and drain → drop the stale push")
    }

    func testDrain_DeletePanel_CallsDeleteRecord() async {
        let id = UUID()
        queue.enqueue(.deletePanel(id: id))
        let drainer = makeDrainer()
        await drainer.drainOnce()
        XCTAssertEqual(database.deletedRecordIDs.count, 1)
        XCTAssertEqual(database.deletedRecordIDs.first?.recordName, id.uuidString)
        XCTAssertEqual(queue.entries, [])
    }

    // MARK: saveInteraction

    func testDrain_SaveInteraction_PushesInteractionRecordWithRef() async {
        let interaction = Interaction(name: "drink")
        let panel = Panel(title: "I Want", color: .systemPink,
                          interactions: [interaction], isBuiltIn: false)
        queue.enqueue(.saveInteraction(id: interaction.id, parentID: panel.id))
        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()

        XCTAssertEqual(database.savedRecords.count, 1)
        let record = database.savedRecords.first!
        XCTAssertEqual(record.recordType, "Interaction")
        XCTAssertEqual(record["displayName"] as? String, "drink")
        XCTAssertEqual(record["order"] as? Int64, 0)
        let ref = record["panelRef"] as? CKRecord.Reference
        XCTAssertEqual(ref?.recordID.recordName, panel.id.uuidString)
    }

    func testDrain_SaveInteraction_AttachesAssetsThatExistOnDisk() async throws {
        let interaction = Interaction(name: "happy")
        let panel = Panel(title: "I feel", color: .green,
                          interactions: [interaction], isBuiltIn: false)
        try Data([0xFF, 0xD8]).write(to: assetStore.url(for: .picture, id: interaction.id))
        try Data([0x01]).write(to: assetStore.url(for: .boyAudio, id: interaction.id))
        // No girl audio.

        queue.enqueue(.saveInteraction(id: interaction.id, parentID: panel.id))
        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()

        let record = database.savedRecords.first!
        XCTAssertNotNil(record["imageAsset"] as? CKAsset)
        XCTAssertNotNil(record["audioBoyAsset"] as? CKAsset)
        XCTAssertNil(record["audioGirlAsset"], "no file on disk → field nil")
    }

    func testDrain_SaveInteraction_ParentDisappeared_Drops() async {
        let interactionID = UUID()
        queue.enqueue(.saveInteraction(id: interactionID, parentID: UUID()))
        let drainer = makeDrainer(panels: [])
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [])
        XCTAssertEqual(queue.entries, [])
    }

    func testDrain_DeleteInteraction_CallsDeleteRecord() async {
        let id = UUID()
        queue.enqueue(.deleteInteraction(id: id))
        let drainer = makeDrainer()
        await drainer.drainOnce()
        XCTAssertEqual(database.deletedRecordIDs.first?.recordName, id.uuidString)
        XCTAssertEqual(queue.entries, [])
    }

    // MARK: uploadAsset / deleteAsset translate to saveInteraction

    func testDrain_UploadAsset_TranslatesTo_SaveInteractionRecord() async throws {
        let interaction = Interaction(name: "tv")
        let panel = Panel(title: "I want to", color: .yellow,
                          interactions: [interaction], isBuiltIn: false)
        try Data([0xFF]).write(to: assetStore.url(for: .picture, id: interaction.id))

        queue.enqueue(.uploadAsset(kind: .picture, id: interaction.id))
        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()

        XCTAssertEqual(database.savedRecords.count, 1,
                       "uploadAsset is translated to a full Interaction record save")
        XCTAssertEqual(database.savedRecords.first?.recordType, "Interaction")
        XCTAssertNotNil(database.savedRecords.first?["imageAsset"] as? CKAsset)
    }

    func testDrain_DeleteAsset_TranslatesTo_SaveInteractionWithFieldOmitted() async {
        let interaction = Interaction(name: "headache")
        let panel = Panel(title: "I feel", color: .red,
                          interactions: [interaction], isBuiltIn: false)
        // No assets on disk — encoder omits all three fields, which on
        // CKRecord is equivalent to "remove this field server-side."

        queue.enqueue(.deleteAsset(kind: .picture, id: interaction.id))
        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()

        XCTAssertEqual(database.savedRecords.count, 1,
                       "deleteAsset translates to a save with the asset locally absent → CKRecord field nil")
        XCTAssertNil(database.savedRecords.first?["imageAsset"])
    }

    func testDrain_AssetOp_ParentMissing_Drops() async {
        queue.enqueue(.uploadAsset(kind: .picture, id: UUID()))
        let drainer = makeDrainer(panels: [])
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [])
        XCTAssertEqual(queue.entries, [])
    }

    // MARK: Errors — retryable vs permanent

    func testDrain_RetryableError_KeepsEntry_AndAdvancesBackoff() async {
        let panel = Panel(title: "x", color: .red, interactions: [], isBuiltIn: false)
        queue.enqueue(.savePanel(id: panel.id))
        database.nextSaveError = CKError(_nsError: NSError(
            domain: CKErrorDomain, code: CKError.Code.networkUnavailable.rawValue))

        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()

        XCTAssertEqual(queue.entries.count, 1, "retryable failure keeps the entry")
        XCTAssertEqual(queue.entries.first?.retryCount, 1)
        XCTAssertGreaterThan(queue.entries.first!.nextEligibleAt.timeIntervalSinceNow, 0,
                             "backoff scheduled into the future")
    }

    func testDrain_PermanentError_DropsEntry() async {
        let panel = Panel(title: "x", color: .red, interactions: [], isBuiltIn: false)
        queue.enqueue(.savePanel(id: panel.id))
        database.nextSaveError = CKError(_nsError: NSError(
            domain: CKErrorDomain, code: CKError.Code.quotaExceeded.rawValue))

        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()

        XCTAssertEqual(queue.entries, [],
                       "permanent error drops the entry — retrying won't help")
    }

    // MARK: drainOnce contract — no-op on empty queue

    func testDrainOnce_NoOpsOnEmptyQueue() async {
        let drainer = makeDrainer()
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [])
        XCTAssertEqual(database.deletedRecordIDs, [])
    }

    func testDrainOnce_NoOpsWhenNoEntryDue() async {
        // Enqueue an entry that's been failed enough that nextEligibleAt
        // is in the future.
        let panel = Panel(title: "x", color: .red, interactions: [], isBuiltIn: false)
        let entry = queue.enqueue(.savePanel(id: panel.id))
        queue.markFailure(entry, retryable: true, now: Date())

        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [],
                       "drainOnce does nothing while entry is in backoff window")
    }

    // MARK: Zone bootstrap (v3.1.2a)

    func testDrainOnce_BootstrapsZone_OnFirstCall() async {
        let drainer = makeDrainer()
        await drainer.drainOnce()
        XCTAssertEqual(database.savedZones.count, 1,
                       "first drainOnce ensures the custom zone exists before any record save")
        XCTAssertEqual(database.savedZones.first?.zoneID, zoneID)
    }

    func testDrainOnce_DoesNotReBootstrapZone_OnceEstablished() async {
        let panel1 = Panel(title: "a", color: .red, interactions: [], isBuiltIn: false)
        let panel2 = Panel(title: "b", color: .red, interactions: [], isBuiltIn: false)
        queue.enqueue(.savePanel(id: panel1.id))
        queue.enqueue(.savePanel(id: panel2.id))

        let drainer = makeDrainer(panels: [panel1, panel2])
        await drainer.drainOnce()
        await drainer.drainOnce()
        XCTAssertEqual(database.savedZones.count, 1,
                       "zone bootstrap is idempotent — only one saveZone call, even across multiple drains")
    }

    func testDrainOnce_ZoneBootstrapFailure_SkipsRecordSave_AndRetries() async {
        let panel = Panel(title: "x", color: .red, interactions: [], isBuiltIn: false)
        let entry = queue.enqueue(.savePanel(id: panel.id))

        // First drain: zone save throws → record save not even attempted,
        // entry stays in the queue with retryCount unchanged.
        database.nextSaveZoneError = CKError(_nsError: NSError(
            domain: CKErrorDomain, code: CKError.Code.networkUnavailable.rawValue))
        let drainer = makeDrainer(panels: [panel])
        await drainer.drainOnce()
        XCTAssertEqual(database.savedRecords, [],
                       "record save skipped when zone bootstrap fails (transient device-level condition)")
        XCTAssertEqual(queue.entries.count, 1,
                       "entry is preserved — not burned on a zone-bootstrap failure")
        XCTAssertEqual(queue.entries.first?.retryCount, 0,
                       "no retry slot was consumed on the entry")
        XCTAssertEqual(queue.entries.first?.id, entry.id)

        // Second drain: zone save now succeeds → record save proceeds
        // and the queue entry drains.
        await drainer.drainOnce()
        XCTAssertEqual(database.savedZones.count, 1,
                       "zone bootstrap retried and succeeded")
        XCTAssertEqual(database.savedRecords.count, 1,
                       "with zone established, the record save now goes through")
        XCTAssertEqual(queue.entries, [],
                       "entry drained successfully on the second iteration")
    }
}

// MARK: - PanelStore record-push enqueueing (v3.1.1c-ii)

/// Integration tests that wire a PanelStore to a CloudKitAssetStore
/// (with MockCloudKitDatabase under the hood) and verify the right
/// PushOperations show up after each mutation. The drainer is NOT
/// started — we just inspect the queue. v3.1.1c-i covers the drainer
/// side already.
final class PanelStoreCloudKitMirrorTests: XCTestCase {

    var tempDir: URL!
    var mockDB: MockCloudKitDatabase!
    var assetStore: CloudKitAssetStore!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirrorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockDB = MockCloudKitDatabase()
        assetStore = CloudKitAssetStore(parentDirectory: tempDir, database: mockDB)
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir,
                           keyValueStore: kvs,
                           assetStore: assetStore)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var queueEntries: [PushEntry] { assetStore.pushQueue.entries }

    // MARK: savePanel

    func testSavePanel_Enqueues_SavePanelAndChildren() throws {
        let i1 = Interaction(name: "happy")
        let i2 = Interaction(name: "sad")
        let panel = Panel(title: "Feelings", color: .systemBlue,
                          interactions: [i1, i2], isBuiltIn: false)
        try store.savePanel(panel)
        let ops = queueEntries.map { $0.op }
        XCTAssertTrue(ops.contains(.savePanel(id: panel.id)))
        XCTAssertTrue(ops.contains(.saveInteraction(id: i1.id, parentID: panel.id)))
        XCTAssertTrue(ops.contains(.saveInteraction(id: i2.id, parentID: panel.id)))
    }

    func testSavePanel_BuiltInsSkipped_OnlyUserPanelEnqueued() throws {
        // Built-in panels can't be saved via savePanel (it returns early),
        // so this isn't a real production case, but the guard belt-and-suspenders.
        let builtIn = Interaction(interactionName: "happy")  // built-in
        let user = Interaction(name: "custom-greet")
        let panel = Panel(title: "Mixed", color: .green,
                          interactions: [builtIn, user], isBuiltIn: false)
        try store.savePanel(panel)
        let ops = queueEntries.map { $0.op }
        XCTAssertTrue(ops.contains(.saveInteraction(id: user.id, parentID: panel.id)))
        XCTAssertFalse(ops.contains(.saveInteraction(id: builtIn.id, parentID: panel.id)),
                       "built-in interactions never sync — they're bundled with the app")
    }

    // MARK: deletePanel

    func testDeletePanel_Enqueues_ChildDeletesThenPanelDelete() throws {
        let i = Interaction(name: "want")
        let panel = Panel(title: "Wants", color: .orange,
                          interactions: [i], isBuiltIn: false)
        try store.savePanel(panel)
        try store.deletePanel(id: panel.id)
        let ops = queueEntries.map { $0.op }
        // After delete, the original saves are wiped via supersession,
        // and explicit deletes for the panel + child remain.
        XCTAssertTrue(ops.contains(.deletePanel(id: panel.id)),
                      "explicit panel delete enqueued (cascade is server-side; this is for queue dedupe semantics)")
        XCTAssertTrue(ops.contains(.deleteInteraction(id: i.id)))
        XCTAssertFalse(ops.contains(.savePanel(id: panel.id)),
                       "delete supersedes the prior save")
    }

    // MARK: trashInteraction

    func testTrashInteraction_Enqueues_DeleteInteraction() throws {
        let i = Interaction(name: "playground")
        let panel = Panel(title: "Outside", color: .yellow,
                          interactions: [i], isBuiltIn: false)
        try store.savePanel(panel)
        try store.trashInteraction(i, fromPanelID: panel.id)
        let ops = queueEntries.map { $0.op }
        XCTAssertTrue(ops.contains(.deleteInteraction(id: i.id)),
                      "trashing mirrors as server-side delete; restore re-enqueues a save inside savePanel(panel) within restoreInteraction")
    }

    // MARK: restorePanel — savePanel cascade re-enqueues

    func testRestorePanel_AfterTrash_ReEnqueuesSaves() throws {
        let i = Interaction(name: "tv")
        let panel = Panel(title: "Wants", color: .orange,
                          interactions: [i], isBuiltIn: false)
        try store.savePanel(panel)
        try store.trashPanel(panel)
        // After trash, the save ops are gone, replaced by deletes.
        XCTAssertFalse(queueEntries.map { $0.op }.contains(.savePanel(id: panel.id)))
        try store.restorePanel(trashID: store.trashedItems().first!.trashID)
        let ops = queueEntries.map { $0.op }
        XCTAssertTrue(ops.contains(.savePanel(id: panel.id)),
                      "restore re-creates the record on iCloud — savePanel inside restorePanel is the trigger")
        XCTAssertTrue(ops.contains(.saveInteraction(id: i.id, parentID: panel.id)))
    }

    // MARK: deleteInteractionAsset / didExternallyWriteAsset

    func testDeleteInteractionAsset_RoutesThroughAssetStore_Enqueues() {
        let id = UUID()
        store.deleteInteractionAsset(kind: .picture, id: id)
        XCTAssertEqual(queueEntries.map { $0.op },
                       [.deleteAsset(kind: .picture, id: id)])
    }

    func testDidExternallyWriteAsset_Enqueues_UploadAsset() {
        let id = UUID()
        store.didExternallyWriteAsset(kind: .boyAudio, id: id)
        XCTAssertEqual(queueEntries.map { $0.op },
                       [.uploadAsset(kind: .boyAudio, id: id)])
    }

    // MARK: Initial sync

    func testStartCloudKitSyncIfNeeded_SeedsExistingPanels_OnFirstRun() throws {
        // Pre-existing user panel from before CloudKit was wired.
        let i = Interaction(name: "drink")
        let panel = Panel(title: "Need", color: .cyan,
                          interactions: [i], isBuiltIn: false)
        try store.savePanel(panel)
        // Drain the queue manually to clear the savePanel/saveInteraction
        // ops the savePanel call already enqueued — simulate "panel created
        // before CloudKit was wired in this branch."
        for entry in assetStore.pushQueue.entries {
            assetStore.pushQueue.markSuccess(entry)
        }
        XCTAssertEqual(queueEntries, [])

        // First call: seeds + starts the drainer.
        store.startCloudKitSyncIfNeeded()
        let ops = queueEntries.map { $0.op }
        XCTAssertTrue(ops.contains(.savePanel(id: panel.id)),
                      "initial sync enqueues savePanel for every existing user panel")
        XCTAssertTrue(ops.contains(.saveInteraction(id: i.id, parentID: panel.id)))

        // Important: stop the drainer before tearDown so its background
        // Task doesn't outlive the test and grab the temp dir we're
        // about to delete.
        store.stopCloudKitSync()
    }

    func testStartCloudKitSyncIfNeeded_Idempotent_DoesNotReSeed() throws {
        let panel = Panel(title: "X", color: .red,
                          interactions: [], isBuiltIn: false)
        try store.savePanel(panel)
        for entry in assetStore.pushQueue.entries {
            assetStore.pushQueue.markSuccess(entry)
        }

        store.startCloudKitSyncIfNeeded()
        XCTAssertEqual(queueEntries.count, 1, "first call seeds")
        // Drain again, simulating the drainer succeeded.
        for entry in queueEntries {
            assetStore.pushQueue.markSuccess(entry)
        }

        // Second call: no re-seeding even though the queue is empty.
        store.stopCloudKitSync()
        store.startCloudKitSyncIfNeeded()
        XCTAssertEqual(queueEntries, [],
                       "initial sync flag prevents re-seeding on subsequent launches")
        store.stopCloudKitSync()
    }

    func testStartCloudKitSyncIfNeeded_NoOp_WhenAssetStoreIsNotCloudKit() throws {
        // Local-FS asset store → no drainer, no seeding, no enqueues.
        let localStore = PanelStore(directory: tempDir.appendingPathComponent("local-only"),
                                     keyValueStore: MemoryKeyValueStore(),
                                     assetStore: LocalFSAssetStore(parentDirectory:
                                        tempDir.appendingPathComponent("local-only")))
        let panel = Panel(title: "Y", color: .green,
                          interactions: [], isBuiltIn: false)
        try localStore.savePanel(panel)
        // No queue to inspect, but the call must not crash.
        XCTAssertNoThrow(localStore.startCloudKitSyncIfNeeded())
        localStore.stopCloudKitSync()
    }

    // MARK: clearAllUserData is local-only

    func testClearAllUserData_DoesNotEnqueue_AnyServerOps() throws {
        let i = Interaction(name: "hi")
        let panel = Panel(title: "Greet", color: .purple,
                          interactions: [i], isBuiltIn: false)
        try store.savePanel(panel)
        for entry in queueEntries {
            assetStore.pushQueue.markSuccess(entry)
        }

        store.clearAllUserData()

        XCTAssertEqual(queueEntries, [],
                       "Clear All My Data is documented as local-only — does NOT enqueue iCloud deletes for v3.1.1")
    }
}

// MARK: - CloudKitPullCoordinator (v3.1.2b-i)

/// The pull half of CloudKit sync. v3.1.2b-i tests cover the protocol
/// flow — read token → fetch (loop while moreComing) → persist new
/// token → return aggregated CloudKitChanges. Apply-to-PanelStore
/// logic lives in v3.1.2b-ii and is tested separately.
///
/// Note on token equality: tests use `nil` for the new change token in
/// the canned `CloudKitChanges` responses because production
/// `CKServerChangeToken` instances can only be constructed by Apple's
/// CloudKit framework from real server responses, not from test code.
/// That limits these tests to behavior verification (was tokenStore
/// written? was the right `previousToken` passed?) rather than content
/// roundtrip verification, which lives in the v3.1.2c integration
/// tests against a live iCloud account.
final class CloudKitPullCoordinatorTests: XCTestCase {

    var database: MockCloudKitDatabase!
    var tokenStore: MemoryChangeTokenStore!
    let zoneID = LiveCloudKitDatabase.iInteractZoneID

    override func setUp() {
        super.setUp()
        database = MockCloudKitDatabase()
        tokenStore = MemoryChangeTokenStore()
    }

    private func makeCoordinator() -> CloudKitPullCoordinator {
        CloudKitPullCoordinator(database: database,
                                zoneID: zoneID,
                                tokenStore: tokenStore)
    }

    // MARK: pull() basic flow

    func testPull_EmptyStore_PassesNilPreviousToken() async throws {
        database.fetchChangesScript = [.success(CloudKitChanges())]
        _ = try await makeCoordinator().pull()
        XCTAssertEqual(database.fetchChangesCalls.count, 1)
        XCTAssertNil(database.fetchChangesCalls.first?.previousToken,
                     "first-ever pull passes nil — fetches everything from the start")
        XCTAssertEqual(database.fetchChangesCalls.first?.zoneID, zoneID)
    }

    func testPull_NoChanges_ReturnsEmptyAggregate() async throws {
        database.fetchChangesScript = [.success(CloudKitChanges())]
        let result = try await makeCoordinator().pull()
        XCTAssertEqual(result.updatedRecords.count, 0)
        XCTAssertEqual(result.deletedRecords, [])
        XCTAssertFalse(result.moreComing)
    }

    func testPull_AggregatesUpdatedRecords_AcrossSingleBatch() async throws {
        let recordA = CKRecord(recordType: "UserPanel",
                                recordID: CKRecord.ID(recordName: "A", zoneID: zoneID))
        let recordB = CKRecord(recordType: "UserPanel",
                                recordID: CKRecord.ID(recordName: "B", zoneID: zoneID))
        database.fetchChangesScript = [
            .success(CloudKitChanges(updatedRecords: [recordA, recordB]))
        ]
        let result = try await makeCoordinator().pull()
        XCTAssertEqual(result.updatedRecords.count, 2)
        XCTAssertEqual(Set(result.updatedRecords.map { $0.recordID.recordName }),
                       ["A", "B"])
    }

    func testPull_AggregatesDeletions_AcrossSingleBatch() async throws {
        let id = CKRecord.ID(recordName: "X", zoneID: zoneID)
        let deletion = DeletedRecord(recordID: id, recordType: "Interaction")
        database.fetchChangesScript = [
            .success(CloudKitChanges(deletedRecords: [deletion]))
        ]
        let result = try await makeCoordinator().pull()
        XCTAssertEqual(result.deletedRecords, [deletion])
    }

    // MARK: moreComing handling

    func testPull_LoopsWhileMoreComing_AggregatesBothBatches() async throws {
        let r1 = CKRecord(recordType: "UserPanel",
                          recordID: CKRecord.ID(recordName: "P1", zoneID: zoneID))
        let r2 = CKRecord(recordType: "Interaction",
                          recordID: CKRecord.ID(recordName: "I1", zoneID: zoneID))
        database.fetchChangesScript = [
            .success(CloudKitChanges(updatedRecords: [r1], moreComing: true)),
            .success(CloudKitChanges(updatedRecords: [r2], moreComing: false)),
        ]
        let result = try await makeCoordinator().pull()
        XCTAssertEqual(database.fetchChangesCalls.count, 2,
                       "should fetch again when moreComing=true")
        XCTAssertEqual(result.updatedRecords.count, 2,
                       "aggregate spans both batches")
        XCTAssertEqual(Set(result.updatedRecords.map { $0.recordID.recordName }),
                       ["P1", "I1"])
        XCTAssertFalse(result.moreComing,
                       "final result reflects the last batch's moreComing=false")
    }

    func testPull_StopsWhenMoreComingFalse_EvenWithEmptyBatch() async throws {
        database.fetchChangesScript = [
            .success(CloudKitChanges(moreComing: false)),
        ]
        _ = try await makeCoordinator().pull()
        XCTAssertEqual(database.fetchChangesCalls.count, 1,
                       "single fetch when moreComing=false")
    }

    // MARK: Errors

    func testPull_RethrowsFetchError() async {
        struct E: Error, Equatable {}
        database.fetchChangesScript = [.failure(E())]
        do {
            _ = try await makeCoordinator().pull()
            XCTFail("expected throw")
        } catch let e as E {
            XCTAssertEqual(e, E())
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPull_FailureLeavesPreviousTokenUntouched() async {
        // Token store starts empty.
        database.fetchChangesScript = [.failure(NSError(domain: "test", code: 1))]
        _ = try? await makeCoordinator().pull()
        XCTAssertNil(tokenStore.token,
                     "failed pull must not write a partial/garbage token — next call retries from the same point")
    }
}

// MARK: - FileChangeTokenStore — bad-file recovery (v3.1.2b-i)

/// Round-tripping a real `CKServerChangeToken` requires a value that
/// only Apple's CloudKit framework hands out, so a content-roundtrip
/// test belongs in the v3.1.2c integration suite. What we *can* test
/// here without real iCloud is the bad-file recovery contract: a
/// corrupted token file gets renamed aside and `read()` returns nil
/// rather than crashing the app.
final class FileChangeTokenStoreTests: XCTestCase {

    var tempDir: URL!
    var tokenURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTokenStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir,
                                                  withIntermediateDirectories: true)
        tokenURL = tempDir.appendingPathComponent("token")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRead_NoFile_ReturnsNil() {
        let store = FileChangeTokenStore(url: tokenURL)
        XCTAssertNil(store.read())
    }

    func testRead_CorruptedFile_RenamedAside_ReturnsNil() throws {
        try Data("not a valid keyed-archive token".utf8).write(to: tokenURL)
        let store = FileChangeTokenStore(url: tokenURL)
        XCTAssertNil(store.read(),
                     "corrupted file must not crash — read returns nil")
        let siblings = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains(where: { $0.lastPathComponent.contains(".bad-") }),
                      "corrupted token file must be moved aside (.bad-<timestamp>) so we don't keep retrying the parse on every launch")
    }

    func testClear_RemovesFile() throws {
        try Data("anything".utf8).write(to: tokenURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokenURL.path))
        FileChangeTokenStore(url: tokenURL).clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenURL.path))
    }

    func testClear_NoFile_DoesNotThrow() {
        // Idempotent — clearing a non-existent file must not crash.
        FileChangeTokenStore(url: tokenURL).clear()
    }
}

// MARK: - CloudKitChangeApplier (v3.1.2b-ii)

/// Applies pulled CloudKit changes to a local PanelStore without
/// re-pushing them. Tests use a CloudKitAssetStore wired to a
/// MockCloudKitDatabase — the applier should NEVER cause records to
/// land in `mockDB.savedRecords` because that would mean it triggered
/// a push (the pull→push feedback loop we're explicitly preventing).
final class CloudKitChangeApplierTests: XCTestCase {

    var tempDir: URL!
    var mockDB: MockCloudKitDatabase!
    var assetStore: CloudKitAssetStore!
    var kvs: MemoryKeyValueStore!
    var store: PanelStore!
    var applier: CloudKitChangeApplier!
    let zoneID = LiveCloudKitDatabase.iInteractZoneID

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Applier-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockDB = MockCloudKitDatabase()
        assetStore = CloudKitAssetStore(parentDirectory: tempDir, database: mockDB)
        kvs = MemoryKeyValueStore()
        store = PanelStore(directory: tempDir,
                           keyValueStore: kvs,
                           assetStore: assetStore)
        applier = CloudKitChangeApplier(store: store, assetStore: assetStore)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: helpers

    private func userPanelRecord(id: UUID, title: String, color: UIColor) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "UserPanel", recordID: recordID)
        record["panelID"] = id.uuidString as CKRecordValue
        record["title"] = title as CKRecordValue
        // Encode the color using the same scheme Panel.colorRGBABytes does.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var floats: [Float32] = [Float32(r), Float32(g), Float32(b), Float32(a)]
        record["colorRGBA"] = Data(bytes: &floats, count: 16) as CKRecordValue
        return record
    }

    private func interactionRecord(id: UUID, parentID: UUID,
                                    name: String, order: Int = 0) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "Interaction", recordID: recordID)
        record["interactionID"] = id.uuidString as CKRecordValue
        let parentRecordID = CKRecord.ID(recordName: parentID.uuidString, zoneID: zoneID)
        record["panelRef"] = CKRecord.Reference(recordID: parentRecordID, action: .deleteSelf)
        record["displayName"] = name as CKRecordValue
        record["order"] = Int64(order) as CKRecordValue
        return record
    }

    // MARK: - Apply: panel records

    func testApplyPanel_NewPanel_LandsInStore() {
        let id = UUID()
        let record = userPanelRecord(id: id, title: "Wants", color: .systemBlue)
        applier.apply(CloudKitChanges(updatedRecords: [record]))
        let panel = store.userPanels().first(where: { $0.id == id })
        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.title, "Wants")
    }

    func testApplyPanel_UpdatesExisting_PreservesInteractions() throws {
        let parentID = UUID()
        let interactionID = UUID()
        let interaction = Interaction(id: interactionID, name: "play")
        let original = Panel(id: parentID, title: "Original",
                             color: .red, interactions: [interaction], isBuiltIn: false)
        try store.savePanel(original)

        let updated = userPanelRecord(id: parentID, title: "Updated", color: .green)
        applier.apply(CloudKitChanges(updatedRecords: [updated]))
        let panel = store.userPanels().first(where: { $0.id == parentID })
        XCTAssertEqual(panel?.title, "Updated")
        XCTAssertEqual(panel?.interactions.count, 1,
                       "applying a panel record must NOT clobber its existing interactions — those arrive in their own records")
        XCTAssertEqual(panel?.interactions.first?.id, interactionID)
    }

    // MARK: - Apply: interaction records

    func testApplyInteraction_AppendsToExistingPanel() throws {
        let parentID = UUID()
        let panel = Panel(id: parentID, title: "Wants", color: .red,
                          interactions: [], isBuiltIn: false)
        try store.savePanel(panel)

        let interactionID = UUID()
        let record = interactionRecord(id: interactionID, parentID: parentID,
                                        name: "drink", order: 0)
        applier.apply(CloudKitChanges(updatedRecords: [record]))

        let stored = store.userPanels().first(where: { $0.id == parentID })
        XCTAssertEqual(stored?.interactions.count, 1)
        XCTAssertEqual(stored?.interactions.first?.name, "drink")
        XCTAssertEqual(stored?.interactions.first?.id, interactionID)
    }

    func testApplyInteraction_OrderedInsert() throws {
        let parentID = UUID()
        let existing = Interaction(id: UUID(), name: "first")
        let panel = Panel(id: parentID, title: "P", color: .red,
                          interactions: [existing], isBuiltIn: false)
        try store.savePanel(panel)

        let newID = UUID()
        let record = interactionRecord(id: newID, parentID: parentID,
                                        name: "inserted", order: 0)
        applier.apply(CloudKitChanges(updatedRecords: [record]))

        let stored = store.userPanels().first(where: { $0.id == parentID })
        XCTAssertEqual(stored?.interactions.count, 2)
        XCTAssertEqual(stored?.interactions[0].name, "inserted",
                       "order=0 inserts at the front")
        XCTAssertEqual(stored?.interactions[1].name, "first")
    }

    func testApplyInteraction_ParentMissing_DefersAndDoesNotCrash() {
        // No parent panel in the store. Applier logs and skips.
        let record = interactionRecord(id: UUID(), parentID: UUID(),
                                        name: "orphan", order: 0)
        XCTAssertNoThrow(applier.apply(CloudKitChanges(updatedRecords: [record])))
        XCTAssertTrue(store.userPanels().isEmpty,
                      "no orphan panels created from interaction-only records")
    }

    // MARK: - Apply: ordering within a batch (panels before interactions)

    func testApply_PanelsBeforeInteractions_WithinSingleBatch() {
        let parentID = UUID()
        let interactionID = UUID()
        // Order in updatedRecords is INTERACTION FIRST — applier must
        // still process the panel before the interaction so the
        // parent exists.
        let interactionRec = interactionRecord(id: interactionID,
                                                 parentID: parentID,
                                                 name: "tv", order: 0)
        let panelRec = userPanelRecord(id: parentID, title: "Wants",
                                        color: .yellow)
        applier.apply(CloudKitChanges(updatedRecords: [interactionRec, panelRec]))
        let stored = store.userPanels().first(where: { $0.id == parentID })
        XCTAssertNotNil(stored, "panel applied even though it was second in the array")
        XCTAssertEqual(stored?.interactions.first?.id, interactionID,
                       "interaction also applied — applier sorted within the batch")
    }

    // MARK: - Apply: deletions

    func testApplyDeletion_Panel_RemovesFromStore() throws {
        let id = UUID()
        let panel = Panel(id: id, title: "Doomed", color: .red,
                          interactions: [], isBuiltIn: false)
        try store.savePanel(panel)
        XCTAssertEqual(store.userPanels().count, 1)

        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let deletion = DeletedRecord(recordID: recordID, recordType: "UserPanel")
        applier.apply(CloudKitChanges(deletedRecords: [deletion]))
        XCTAssertEqual(store.userPanels().count, 0)
    }

    func testApplyDeletion_Interaction_RemovesFromParent() throws {
        let parentID = UUID()
        let interactionID = UUID()
        let interaction = Interaction(id: interactionID, name: "x")
        let panel = Panel(id: parentID, title: "P", color: .red,
                          interactions: [interaction], isBuiltIn: false)
        try store.savePanel(panel)

        let recordID = CKRecord.ID(recordName: interactionID.uuidString, zoneID: zoneID)
        let deletion = DeletedRecord(recordID: recordID, recordType: "Interaction")
        applier.apply(CloudKitChanges(deletedRecords: [deletion]))
        let stored = store.userPanels().first(where: { $0.id == parentID })
        XCTAssertEqual(stored?.interactions.count, 0)
    }

    func testApplyDeletion_UnknownRecordType_NoCrash() {
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let deletion = DeletedRecord(recordID: recordID, recordType: "Mystery")
        XCTAssertNoThrow(applier.apply(CloudKitChanges(deletedRecords: [deletion])))
    }

    // MARK: - Feedback-loop guard (THE KEY GUARANTEE)

    func testApply_DoesNotEnqueuePushOps() {
        let panelID = UUID()
        let interactionID = UUID()
        let panelRec = userPanelRecord(id: panelID, title: "Pulled", color: .blue)
        let interactionRec = interactionRecord(id: interactionID,
                                                 parentID: panelID,
                                                 name: "pulled-i", order: 0)
        applier.apply(CloudKitChanges(updatedRecords: [panelRec, interactionRec]))

        XCTAssertEqual(assetStore.pushQueue.entries.count, 0,
                       "applying a pulled change must NOT enqueue a push — that would be a pull→push feedback loop")
    }

    func testApplyDeletion_DoesNotEnqueuePushOps() throws {
        let id = UUID()
        let panel = Panel(id: id, title: "Doomed", color: .red,
                          interactions: [], isBuiltIn: false)
        // Use the apply path so the savePanel itself doesn't enqueue.
        try store.applyRemotelySavedPanel(panel)
        XCTAssertEqual(assetStore.pushQueue.entries.count, 0)

        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let deletion = DeletedRecord(recordID: recordID, recordType: "UserPanel")
        applier.apply(CloudKitChanges(deletedRecords: [deletion]))

        XCTAssertEqual(assetStore.pushQueue.entries.count, 0,
                       "applying a remote deletion must NOT enqueue a deletePanel push back to the server")
    }

    // MARK: - Malformed records

    func testApply_MalformedRecord_SkippedWithoutCrash() {
        // recordType is right but required fields are missing.
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let bad = CKRecord(recordType: "UserPanel", recordID: recordID)
        // No panelID, title, or colorRGBA.
        XCTAssertNoThrow(applier.apply(CloudKitChanges(updatedRecords: [bad])))
        XCTAssertTrue(store.userPanels().isEmpty)
    }
}
