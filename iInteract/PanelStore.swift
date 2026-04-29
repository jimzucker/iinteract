//
//  PanelStore.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation
import CryptoKit
import UIKit

// MARK: - KeyValueStorage

/// The slice of NSUbiquitousKeyValueStore that PanelStore needs. Tests inject
/// an in-memory implementation; production uses iCloud KVS.
protocol KeyValueStorage: AnyObject {
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func set(_ value: String?, forKey key: String)
    func set(_ value: Data?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStorage {
    func set(_ value: String?, forKey key: String) {
        if let value = value {
            self.set(value as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
    func set(_ value: Data?, forKey key: String) {
        if let value = value {
            self.set(value as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

// MARK: - PanelStore

final class PanelStore {

    static let maxInteractionsPerUserPanel = 6

    /// Posted on the main queue when KVS delivers a change from another device,
    /// after the local cache has been refreshed. UI reloads in response.
    static let didChangeNotification = Notification.Name("PanelStore.didChange")

    /// Production singleton — Application Support + iCloud KVS.
    /// Picks `CloudKitAssetStore` when iCloud is signed in so user
    /// recordings + pictures sync to the user's private CloudKit
    /// database; otherwise falls back to the local-only
    /// `LocalFSAssetStore`. Choice is sticky for this launch — if the
    /// user signs into iCloud after launch, restart picks it up.
    static let shared: PanelStore = {
        let dir = PanelStore.defaultDirectory()
        let useCloudKit = FileManager.default.ubiquityIdentityToken != nil
        let assetStore: AssetStore = useCloudKit
            ? CloudKitAssetStore(parentDirectory: dir)
            : LocalFSAssetStore(parentDirectory: dir)
        let s = PanelStore(directory: dir,
                           keyValueStore: NSUbiquitousKeyValueStore.default,
                           iCloudAvailability: { FileManager.default.ubiquityIdentityToken != nil },
                           assetStore: assetStore)
        s.startObservingICloudChanges()
        NSUbiquitousKeyValueStore.default.synchronize()
        return s
    }()

    enum StoreError: Error {
        case nameNotUnique
        case capacityExceeded
        case panelNotFound
        case iCloudUnavailable
        case noSecurityQuestionSet
        case incorrectAnswer
        case assetWriteFailed
    }

    enum Voice {
        case boy, girl
        var assetKind: AssetKind { self == .boy ? .boyAudio : .girlAudio }
    }

    private let directory: URL
    private let kvs: KeyValueStorage
    private let iCloudAvailability: () -> Bool
    private let assetStore: AssetStore

    init(directory: URL,
         keyValueStore: KeyValueStorage,
         iCloudAvailability: @escaping () -> Bool = { false },
         assetStore: AssetStore? = nil) {
        self.directory = directory
        self.kvs = keyValueStore
        self.iCloudAvailability = iCloudAvailability
        self.assetStore = assetStore ?? LocalFSAssetStore(parentDirectory: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PanelStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var panelsURL: URL { directory.appendingPathComponent("panels.json") }
    private var layoutURL: URL { directory.appendingPathComponent("layout.json") }

    /// Folder for user-recorded audio + chosen pictures. Exposed
    /// because the trash/restore flow operates on raw URLs (move file
    /// out of the active dir into a per-trash-item folder, and back on
    /// restore). Delegates to the injected AssetStore so production
    /// uses local FS today and a CloudKit-backed cache directory in
    /// a future release.
    var assetsDirectory: URL { assetStore.rootDirectory }

    /// File URL for a user interaction's asset, used both for reading on
    /// hydrate and for AVAudioRecorder/JPEG writes during editing.
    func assetURL(for interactionID: UUID, kind: AssetKind) -> URL {
        assetStore.url(for: kind, id: interactionID)
    }

    /// Reattaches picture and audio URLs to a freshly-decoded user interaction
    /// based on what's on disk. No-op for built-ins (their bundle URLs are
    /// already set by Interaction.init(interactionName:)).
    func hydrate(_ interaction: Interaction) {
        guard !interaction.isBuiltIn else { return }
        if assetStore.exists(.picture, id: interaction.id) {
            interaction.picture = UIImage(contentsOfFile: assetStore.url(for: .picture,
                                                                          id: interaction.id).path)
        }
        if assetStore.exists(.boyAudio, id: interaction.id) {
            interaction.boySound = assetStore.url(for: .boyAudio, id: interaction.id)
        }
        if assetStore.exists(.girlAudio, id: interaction.id) {
            interaction.girlSound = assetStore.url(for: .girlAudio, id: interaction.id)
        }
    }

    /// Convenience: hydrates all interactions on a user panel.
    func hydrate(_ panel: Panel) {
        guard !panel.isBuiltIn else { return }
        panel.interactions.forEach { hydrate($0) }
    }

    /// Writes a chosen photo as JPEG to the asset path for the given id.
    func saveInteractionPicture(_ image: UIImage, id: UUID) throws {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw StoreError.assetWriteFailed
        }
        try assetStore.write(data, kind: .picture, id: id)
    }

    /// Removes all asset files for an interaction. Safe if files don't exist.
    func deleteInteractionAssets(id: UUID) {
        assetStore.deleteAll(id: id)
    }

    /// Removes a single asset (picture, boy audio, or girl audio) for
    /// an interaction. Used by the editor when the user clears one
    /// voice without affecting the other. Routes through the asset
    /// store so CloudKit-backed deployments enqueue the corresponding
    /// push.
    func deleteInteractionAsset(kind: AssetKind, id: UUID) {
        assetStore.delete(kind, id: id)
    }

    /// Notifies the asset store that the caller wrote (or copied) a
    /// file directly to the URL returned by `assetURL(for:kind:)`,
    /// bypassing `saveInteractionPicture`. Typically called by
    /// `InteractionEditorViewController` after copying a recorded
    /// audio file from the temp directory into the final asset path.
    /// Local-FS asset stores no-op; CloudKit-backed stores enqueue
    /// an upload.
    func didExternallyWriteAsset(kind: AssetKind, id: UUID) {
        assetStore.didExternallyWrite(kind, id: id)
    }

    // MARK: - KVS keys for synced metadata

    private static let kvsPanelsKey = "panelstore.panels"
    private static let kvsLayoutKey = "panelstore.layout"
    private static let kvsModeKey = "panelstore.configuration_mode"
    /// Local-only flag tracking whether we've already done the one-time
    /// "adopt iCloud value at first launch" step. After that, UserDefaults
    /// is the source of intent on this device.
    private static let modeAdoptedKey = "panelstore.configuration_mode_adopted"

    // MARK: - Configuration mode (UserDefaults is canonical, KVS is the mirror)
    //
    // Settings.bundle binds the picker to UserDefaults["configuration_mode"],
    // and that's what represents the user's intent on this device. We mirror
    // out to iCloud KVS so the choice survives reinstalls and follows the
    // user across iCloud-signed devices.
    //
    // Direction of writes:
    // * App launch → adoptCloudConfigurationModeIfFirstLaunch():
    //   if we've never run on this install before AND iCloud has a value,
    //   copy cloud → local. Otherwise leave local alone.
    // * User changes Mode in iOS Settings → app resume → reconcile() pushes
    //   local → cloud whenever they differ. (Local wins at runtime.)
    // * Another device changes mode → iCloudKeysDidChange observer mirrors
    //   the new value down to UserDefaults and posts didChangeNotification.

    /// Reads the live mode from UserDefaults (which iCloud may have already
    /// written into via the KVS observer or the first-launch adoption).
    func configurationMode(_ defaults: UserDefaults = .standard) -> ConfigurationMode {
        return ConfigurationMode.current(defaults)
    }

    /// Writes the new mode to both UserDefaults and KVS. Returns true when
    /// the effective mode actually changed, so callers can refresh UI.
    @discardableResult
    func setConfigurationMode(_ mode: ConfigurationMode,
                              defaults: UserDefaults = .standard) -> Bool {
        let previous = configurationMode(defaults)
        defaults.set(mode.rawValue, forKey: ConfigurationMode.userDefaultsKey)
        kvs.set(mode.rawValue, forKey: Self.kvsModeKey)
        kvs.synchronize()
        return previous != mode
    }

    /// Call once at app launch (before the UI reads the mode). On a fresh
    /// install where iCloud already has a mode set by another device, copies
    /// it down so this device starts in the same mode. After the first
    /// launch, this is a no-op — UserDefaults is the source of intent.
    func adoptCloudConfigurationModeIfFirstLaunch(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: Self.modeAdoptedKey) { return }
        defaults.set(true, forKey: Self.modeAdoptedKey)
        if let raw = kvs.string(forKey: Self.kvsModeKey),
           ConfigurationMode(rawValue: raw) != nil {
            defaults.set(raw, forKey: ConfigurationMode.userDefaultsKey)
        }
    }

    /// Pushes the user's local Mode choice up to iCloud whenever the two
    /// disagree. Call on every resume/foreground so changes made in iOS
    /// Settings propagate. Returns the live mode for convenience.
    @discardableResult
    func reconcileConfigurationMode(defaults: UserDefaults = .standard) -> ConfigurationMode {
        let local = ConfigurationMode.current(defaults)
        let cloud = kvs.string(forKey: Self.kvsModeKey)
            .flatMap(ConfigurationMode.init(rawValue:))
        if cloud != local {
            kvs.set(local.rawValue, forKey: Self.kvsModeKey)
            kvs.synchronize()
        }
        return local
    }

    // MARK: - User panels

    func userPanels() -> [Panel] {
        // Local file is the read cache; KVS is the sync mechanism. On first
        // launch on a new device, the KVS observer copies KVS data here before
        // the UI gets a chance to read it. Migrate the other direction the
        // first time after upgrading to step 8 by promoting any local-only
        // data into KVS so the user's other devices can pick it up.
        if let data = try? Data(contentsOf: panelsURL),
           let panels = try? JSONDecoder().decode([Panel].self, from: data) {
            promoteLocalIfMissingFromKVS(data: data, key: Self.kvsPanelsKey)
            return panels
        }
        // No local file but KVS might have data (fresh install, signed-in user).
        if let data = kvs.data(forKey: Self.kvsPanelsKey),
           let panels = try? JSONDecoder().decode([Panel].self, from: data) {
            try? data.write(to: panelsURL, options: .atomic)
            return panels
        }
        return []
    }

    private func saveUserPanels(_ panels: [Panel]) throws {
        let data = try JSONEncoder().encode(panels)
        try data.write(to: panelsURL, options: .atomic)
        kvs.set(data, forKey: Self.kvsPanelsKey)
        kvs.synchronize()
    }

    private func promoteLocalIfMissingFromKVS(data: Data, key: String) {
        guard kvs.data(forKey: key) == nil else { return }
        kvs.set(data, forKey: key)
        kvs.synchronize()
    }

    func addPanel(_ panel: Panel) throws {
        try savePanel(panel)
    }

    /// Upserts a user panel. New panels (id not present) are appended; existing
    /// panels are replaced in place so reorder/visibility maps still match.
    /// Validates uniqueness (excluding self) and the 6-interaction cap.
    func savePanel(_ panel: Panel) throws {
        guard !panel.isBuiltIn else { return }
        guard isNameAvailable(panel.title, excluding: panel.id) else {
            throw StoreError.nameNotUnique
        }
        guard panel.interactions.count <= Self.maxInteractionsPerUserPanel else {
            throw StoreError.capacityExceeded
        }
        var panels = userPanels()
        if let i = panels.firstIndex(where: { $0.id == panel.id }) {
            panels[i] = panel
        } else {
            panels.append(panel)
        }
        try saveUserPanels(panels)
        enqueueRecordPushForPanelSave(panel)
    }

    func deletePanel(id: UUID) throws {
        let childIDs = userPanels().first(where: { $0.id == id })?.interactions
            .filter { !$0.isBuiltIn }
            .map { $0.id } ?? []
        var panels = userPanels()
        panels.removeAll { $0.id == id }
        try saveUserPanels(panels)
        enqueueRecordPushForPanelDelete(panelID: id, childIDs: childIDs)
    }

    // MARK: - Layout (visibility + order, applies to built-ins AND user panels)

    struct Layout: Codable {
        var hiddenIDs: Set<UUID>
        var orderedIDs: [UUID]

        init(hiddenIDs: Set<UUID> = [], orderedIDs: [UUID] = []) {
            self.hiddenIDs = hiddenIDs
            self.orderedIDs = orderedIDs
        }
    }

    func layout() -> Layout {
        if let data = try? Data(contentsOf: layoutURL),
           let layout = try? JSONDecoder().decode(Layout.self, from: data) {
            promoteLocalIfMissingFromKVS(data: data, key: Self.kvsLayoutKey)
            return layout
        }
        if let data = kvs.data(forKey: Self.kvsLayoutKey),
           let layout = try? JSONDecoder().decode(Layout.self, from: data) {
            try? data.write(to: layoutURL, options: .atomic)
            return layout
        }
        return Layout()
    }

    private func saveLayout(_ layout: Layout) throws {
        let data = try JSONEncoder().encode(layout)
        try data.write(to: layoutURL, options: .atomic)
        kvs.set(data, forKey: Self.kvsLayoutKey)
        kvs.synchronize()
    }

    func setHidden(_ hidden: Bool, for panelID: UUID) throws {
        var l = layout()
        if hidden { l.hiddenIDs.insert(panelID) } else { l.hiddenIDs.remove(panelID) }
        try saveLayout(l)
    }

    func setOrder(_ ids: [UUID]) throws {
        var l = layout()
        l.orderedIDs = ids
        try saveLayout(l)
    }

    /// Returns `panels` with the user's saved order applied. Panels not in
    /// `layout().orderedIDs` (e.g. a freshly added user panel) keep their
    /// original relative position at the end.
    func applyOrder(to panels: [Panel]) -> [Panel] {
        let l = layout()
        guard !l.orderedIDs.isEmpty else { return panels }
        let byID = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
        let ordered = l.orderedIDs.compactMap { byID[$0] }
        let unordered = panels.filter { !l.orderedIDs.contains($0.id) }
        return ordered + unordered
    }

    /// Returns `panels` with hidden ones filtered out.
    func applyHiddenFilter(to panels: [Panel]) -> [Panel] {
        let hidden = layout().hiddenIDs
        return panels.filter { !hidden.contains($0.id) }
    }

    /// Filters hidden panels and orders the rest by `layout().orderedIDs`.
    /// Used by the main list. The editor uses `applyOrder(to:)` directly so it
    /// can show hidden panels alongside visible ones.
    func applyLayout(to panels: [Panel]) -> [Panel] {
        applyOrder(to: applyHiddenFilter(to: panels))
    }

    // MARK: - Validators

    /// True when `name` (case-insensitive, trimmed) doesn't collide with any
    /// built-in title or any other user panel's title. Pass the editing panel's
    /// id as `excluding` so the panel can keep its own name.
    func isNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let needle = trimmed.lowercased()
        let builtInTitles = Panel.readFromPlist().map { $0.title.lowercased() }
        if builtInTitles.contains(needle) { return false }
        for p in userPanels() where p.id != id {
            if p.title.lowercased() == needle { return false }
        }
        return true
    }

    func canAddInteraction(to panelID: UUID) -> Bool {
        guard let panel = userPanels().first(where: { $0.id == panelID }) else { return false }
        return panel.interactions.count < Self.maxInteractionsPerUserPanel
    }

    // MARK: - PIN + security question (mirrored to iCloud KVS so it syncs across devices)

    private static let pinHashKey = "panelstore.pin_hash"
    private static let questionKey = "panelstore.pin_question"
    private static let answerHashKey = "panelstore.pin_answer_hash"

    var hasPIN: Bool { kvs.string(forKey: Self.pinHashKey) != nil }
    var securityQuestion: String? { kvs.string(forKey: Self.questionKey) }
    var hasSecurityQuestion: Bool {
        kvs.string(forKey: Self.questionKey) != nil && kvs.string(forKey: Self.answerHashKey) != nil
    }

    func setPIN(_ pin: String, securityQuestion: String? = nil, securityAnswer: String? = nil) {
        // Case-insensitive: store the lowercased hash so "Abc1" and "abc1"
        // are equivalent on verify. Eliminates a class of "I can't unlock,
        // I swear it's the right PIN" lockouts caused by Caps Lock or
        // accidental shift on a single character.
        kvs.set(Self.hash(pin.lowercased()), forKey: Self.pinHashKey)
        if let q = securityQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
           let a = securityAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !q.isEmpty, !a.isEmpty {
            kvs.set(q, forKey: Self.questionKey)
            kvs.set(Self.hash(a.lowercased()), forKey: Self.answerHashKey)
        } else {
            kvs.removeObject(forKey: Self.questionKey)
            kvs.removeObject(forKey: Self.answerHashKey)
        }
        kvs.synchronize()
    }

    /// Sets or clears the optional security question + answer without
    /// touching the existing PIN hash. Use after `setPIN` to add or
    /// update the recovery question, or pass nil/empty to clear.
    /// Both must be non-empty to save; if either is empty, both are
    /// cleared (matching the both-or-neither semantics of `setPIN`).
    func setSecurityQuestion(_ question: String?, answer: String?) {
        let q = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let a = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !q.isEmpty, !a.isEmpty {
            kvs.set(q, forKey: Self.questionKey)
            kvs.set(Self.hash(a.lowercased()), forKey: Self.answerHashKey)
        } else {
            kvs.removeObject(forKey: Self.questionKey)
            kvs.removeObject(forKey: Self.answerHashKey)
        }
        kvs.synchronize()
    }

    func clearPIN() {
        kvs.removeObject(forKey: Self.pinHashKey)
        kvs.removeObject(forKey: Self.questionKey)
        kvs.removeObject(forKey: Self.answerHashKey)
        kvs.synchronize()
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = kvs.string(forKey: Self.pinHashKey) else { return false }
        // Primary path: PINs set under the case-insensitive policy.
        if Self.hash(pin.lowercased()) == stored { return true }
        // Migration: PIN was set under a prior build that hashed the
        // original case. Match against the original; if it matches,
        // re-store as the lowercased hash so subsequent verifies hit
        // the primary path. One-shot, no user interaction required.
        if Self.hash(pin) == stored {
            kvs.set(Self.hash(pin.lowercased()), forKey: Self.pinHashKey)
            kvs.synchronize()
            return true
        }
        return false
    }

    /// Reset path 1: user is signed into iCloud (proof of account ownership).
    func resetPINViaICloudAccount() throws {
        guard iCloudAvailability() else { throw StoreError.iCloudUnavailable }
        clearPIN()
    }

    /// Reset path 2: user answers the security question they set when configuring the PIN.
    func resetPIN(securityAnswer answer: String) throws {
        guard let storedHash = kvs.string(forKey: Self.answerHashKey) else {
            throw StoreError.noSecurityQuestionSet
        }
        let candidate = Self.hash(answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard candidate == storedHash else { throw StoreError.incorrectAnswer }
        clearPIN()
    }

    // MARK: - Recycle bin (30-day trash)
    //
    // Deleted user panels and interactions move to a Trash directory and
    // hang around for 30 days, mirroring the iOS Photos "Recently Deleted"
    // pattern. Restoring puts the JSON snapshot back and moves the asset
    // files back into UserAssets/. Auto-purge happens lazily on each call
    // to trashedItems() and on store init.

    static let trashLifetime: TimeInterval = 30 * 24 * 60 * 60  // 30 days

    enum TrashKind: String, Codable { case panel, interaction }

    /// One trashed item (panel or interaction) with its restore metadata.
    struct TrashedItem: Codable {
        let trashID: UUID                    // unique to this trash entry
        let kind: TrashKind
        let trashedAt: Date
        /// For interactions: the panel they were inside.
        let parentPanelID: UUID?
        /// JSON snapshot — Panel for kind=.panel, Interaction for .interaction.
        let snapshot: Data
    }

    private var trashIndexURL: URL { directory.appendingPathComponent("trash-index.json") }
    private var trashAssetsRoot: URL {
        let url = directory.appendingPathComponent("Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func trashAssetsDirectory(for trashID: UUID) -> URL {
        let url = trashAssetsRoot.appendingPathComponent(trashID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadTrashIndex() -> [TrashedItem] {
        guard let data = try? Data(contentsOf: trashIndexURL),
              let items = try? JSONDecoder().decode([TrashedItem].self, from: data) else {
            return []
        }
        return items
    }

    private func saveTrashIndex(_ items: [TrashedItem]) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: trashIndexURL, options: .atomic)
    }

    /// Public read API — also auto-purges anything past its 30-day window.
    func trashedItems() -> [TrashedItem] {
        let now = Date()
        let items = loadTrashIndex()
        let kept = items.filter { now.timeIntervalSince($0.trashedAt) < Self.trashLifetime }
        let expired = items.filter { now.timeIntervalSince($0.trashedAt) >= Self.trashLifetime }
        if !expired.isEmpty {
            for item in expired {
                try? FileManager.default.removeItem(at: trashAssetsDirectory(for: item.trashID))
            }
            try? saveTrashIndex(kept)
        }
        return kept.sorted { $0.trashedAt > $1.trashedAt }
    }

    /// How many days remain before this item is permanently purged.
    func daysRemainingInTrash(_ item: TrashedItem, from now: Date = Date()) -> Int {
        let elapsed = now.timeIntervalSince(item.trashedAt)
        let remaining = Self.trashLifetime - elapsed
        return max(0, Int(ceil(remaining / 86_400)))
    }

    /// Moves a user panel into the trash. Asset files for any user
    /// interactions on the panel move to Trash/<trashID>/. Panel JSON is
    /// snapshotted in the trash index. The panel is removed from active
    /// userPanels.
    func trashPanel(_ panel: Panel) throws {
        guard !panel.isBuiltIn else { return }
        let trashID = UUID()
        // Move blob files first; if any throw, leave the active state alone.
        let bin = trashAssetsDirectory(for: trashID)
        for interaction in panel.interactions where !interaction.isBuiltIn {
            for kind in [AssetKind.picture, .boyAudio, .girlAudio] {
                let src = assetURL(for: interaction.id, kind: kind)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                let dst = bin.appendingPathComponent(src.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        }
        let snapshot = try JSONEncoder().encode(panel)
        var items = loadTrashIndex()
        items.append(TrashedItem(trashID: trashID,
                                 kind: .panel,
                                 trashedAt: Date(),
                                 parentPanelID: nil,
                                 snapshot: snapshot))
        try saveTrashIndex(items)
        try deletePanel(id: panel.id)
    }

    /// Moves a single interaction (and its blob files) into the trash. Caller
    /// is responsible for removing it from the panel's `interactions` array
    /// and saving the panel.
    func trashInteraction(_ interaction: Interaction, fromPanelID panelID: UUID) throws {
        guard !interaction.isBuiltIn else { return }
        let trashID = UUID()
        let bin = trashAssetsDirectory(for: trashID)
        for kind in [AssetKind.picture, .boyAudio, .girlAudio] {
            let src = assetURL(for: interaction.id, kind: kind)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = bin.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: src, to: dst)
        }
        let snapshot = try JSONEncoder().encode(interaction)
        var items = loadTrashIndex()
        items.append(TrashedItem(trashID: trashID,
                                 kind: .interaction,
                                 trashedAt: Date(),
                                 parentPanelID: panelID,
                                 snapshot: snapshot))
        try saveTrashIndex(items)
        // Trash is local-only state; mirror to CloudKit as a delete.
        // If the user restores within 30 days, the savePanel inside
        // restoreInteraction re-enqueues the save and the record
        // reappears on other devices.
        cloudKitPushQueue?.enqueue(.deleteInteraction(id: interaction.id))
    }

    /// Moves a trashed panel back into active panels (and its blobs back
    /// into UserAssets/). If the panel's title now collides with an active
    /// one, throws nameNotUnique — the user can rename the trashed item via
    /// `restorePanel(trashID:newTitle:)`.
    @discardableResult
    func restorePanel(trashID: UUID, newTitle: String? = nil) throws -> Panel {
        var items = loadTrashIndex()
        guard let i = items.firstIndex(where: { $0.trashID == trashID && $0.kind == .panel }) else {
            throw StoreError.panelNotFound
        }
        let entry = items[i]
        let panel = try JSONDecoder().decode(Panel.self, from: entry.snapshot)
        if let newTitle = newTitle { panel.title = newTitle }
        guard isNameAvailable(panel.title, excluding: panel.id) else {
            throw StoreError.nameNotUnique
        }
        let bin = trashAssetsDirectory(for: trashID)
        // Move blob files back into UserAssets/.
        if let entries = try? FileManager.default.contentsOfDirectory(at: bin,
                                                                       includingPropertiesForKeys: nil) {
            for src in entries {
                let dst = assetsDirectory.appendingPathComponent(src.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        }
        try? FileManager.default.removeItem(at: bin)
        items.remove(at: i)
        try saveTrashIndex(items)
        try savePanel(panel)
        return panel
    }

    /// Moves a trashed interaction back into a user panel. By default it
    /// goes to its original parent; pass `to:` to redirect into a different
    /// active panel (used when the original was deleted or full). Throws
    /// `panelNotFound` when the destination doesn't exist in active user
    /// panels and `capacityExceeded` when it's at the 6-cap.
    @discardableResult
    func restoreInteraction(trashID: UUID, to targetPanelID: UUID? = nil) throws -> Interaction {
        var items = loadTrashIndex()
        guard let i = items.firstIndex(where: { $0.trashID == trashID && $0.kind == .interaction }) else {
            throw StoreError.panelNotFound
        }
        let entry = items[i]
        let interaction = try JSONDecoder().decode(Interaction.self, from: entry.snapshot)
        let destinationID = targetPanelID ?? entry.parentPanelID
        let panels = userPanels()
        guard let parentID = destinationID,
              let panel = panels.first(where: { $0.id == parentID }) else {
            throw StoreError.panelNotFound
        }
        guard panel.interactions.count < Self.maxInteractionsPerUserPanel else {
            throw StoreError.capacityExceeded
        }
        let bin = trashAssetsDirectory(for: trashID)
        if let entries = try? FileManager.default.contentsOfDirectory(at: bin,
                                                                       includingPropertiesForKeys: nil) {
            for src in entries {
                let dst = assetsDirectory.appendingPathComponent(src.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        }
        try? FileManager.default.removeItem(at: bin)
        panel.interactions.append(interaction)
        try savePanel(panel)
        items.remove(at: i)
        try saveTrashIndex(items)
        return interaction
    }

    /// True iff this trashed interaction's *original* parent still exists in
    /// active user panels and has room.
    func canRestoreInteractionToOriginalParent(trashID: UUID) -> Bool {
        let items = loadTrashIndex()
        guard let entry = items.first(where: { $0.trashID == trashID && $0.kind == .interaction }),
              let parentID = entry.parentPanelID else { return false }
        guard let panel = userPanels().first(where: { $0.id == parentID }) else { return false }
        return panel.interactions.count < Self.maxInteractionsPerUserPanel
    }

    /// If the trashed interaction's parent panel is itself in the trash,
    /// returns the parent's `trashID` so the UI can offer "restore the
    /// panel first." Returns nil otherwise.
    func parentPanelTrashID(forInteractionTrashID trashID: UUID) -> UUID? {
        let items = loadTrashIndex()
        guard let entry = items.first(where: { $0.trashID == trashID && $0.kind == .interaction }),
              let parentID = entry.parentPanelID else { return nil }
        for trashed in items where trashed.kind == .panel {
            if let panel = try? JSONDecoder().decode(Panel.self, from: trashed.snapshot),
               panel.id == parentID {
                return trashed.trashID
            }
        }
        return nil
    }

    /// User panels currently with room (< 6) — destinations to offer when
    /// restoring an interaction whose original parent is gone or full.
    func panelsAvailableToReceiveInteraction() -> [Panel] {
        userPanels().filter { $0.interactions.count < Self.maxInteractionsPerUserPanel }
    }

    /// Permanently removes one trashed item (deletes its blob folder).
    func purgeTrash(trashID: UUID) {
        var items = loadTrashIndex()
        guard items.firstIndex(where: { $0.trashID == trashID }) != nil else { return }
        try? FileManager.default.removeItem(at: trashAssetsDirectory(for: trashID))
        items.removeAll { $0.trashID == trashID }
        try? saveTrashIndex(items)
    }

    /// Empties the entire trash (used by Settings → Clear All My Data and as
    /// a manual "Empty Trash" action in the future Trash screen).
    func emptyTrash() {
        try? FileManager.default.removeItem(at: trashAssetsRoot)
        try? FileManager.default.removeItem(at: trashIndexURL)
    }

    // MARK: - Privacy: wipe everything

    /// Removes every piece of user-authored data: panels.json, layout.json,
    /// every picture/audio blob under UserAssets/, the entire Trash folder,
    /// the PIN hash, and the security question/answer hash (locally and from
    /// iCloud KVS). Bundled built-ins are not touched. Used by the Settings
    /// "Clear All My Data" action.
    func clearAllUserData() {
        try? FileManager.default.removeItem(at: panelsURL)
        try? FileManager.default.removeItem(at: layoutURL)
        assetStore.deleteEverything()
        emptyTrash()
        clearPIN()
        kvs.removeObject(forKey: Self.kvsPanelsKey)
        kvs.removeObject(forKey: Self.kvsLayoutKey)
        kvs.removeObject(forKey: Self.kvsModeKey)
        kvs.synchronize()
    }

    // MARK: - CloudKit sync (v3.1.1c)

    /// Lifetime-pinned drainer for the CloudKit push queue. nil when
    /// `assetStore` isn't `CloudKitAssetStore` (i.e. iCloud signed
    /// out at launch).
    private var cloudKitDrainer: CloudKitPushDrainer?

    /// Convenience accessor — nil for `LocalFSAssetStore`. Used by
    /// the mutation methods (savePanel, deletePanel, trashInteraction)
    /// to enqueue record-level pushes only when CloudKit is wired.
    private var cloudKitPushQueue: PushQueue? {
        (assetStore as? CloudKitAssetStore)?.pushQueue
    }

    /// Enqueues savePanel + saveInteraction(child) for each non-builtin
    /// child. Drainer pushes the latest panel/interaction state at
    /// execute time, so it doesn't matter that the snapshot here is
    /// stale by the time the network call happens.
    private func enqueueRecordPushForPanelSave(_ panel: Panel) {
        guard let q = cloudKitPushQueue else { return }
        q.enqueue(.savePanel(id: panel.id))
        for interaction in panel.interactions where !interaction.isBuiltIn {
            q.enqueue(.saveInteraction(id: interaction.id, parentID: panel.id))
        }
    }

    /// Enqueues deleteInteraction for each child first (their
    /// supersession drops pending uploadAsset/deleteAsset for that
    /// interaction), then deletePanel. CKRecord cascade delete via
    /// `panelRef.deleteSelf` makes the per-child deletes redundant
    /// server-side, but enqueuing them explicitly keeps the queue
    /// dedupe semantics clean.
    private func enqueueRecordPushForPanelDelete(panelID: UUID, childIDs: [UUID]) {
        guard let q = cloudKitPushQueue else { return }
        for childID in childIDs {
            q.enqueue(.deleteInteraction(id: childID))
        }
        q.enqueue(.deletePanel(id: panelID))
    }

    /// Call once at app launch (after `PanelStore.shared` is
    /// materialized) to start the CloudKit push drainer. No-op when
    /// the asset store isn't CloudKit-backed (iCloud signed out).
    /// Idempotent — safe to call multiple times. Also runs the
    /// one-shot initial sync that seeds the push queue with all
    /// existing user panels + interactions on first CloudKit launch.
    func startCloudKitSyncIfNeeded() {
        guard let cloudStore = assetStore as? CloudKitAssetStore else { return }
        runInitialSyncIfNeeded(queue: cloudStore.pushQueue)
        if cloudKitDrainer == nil {
            let drainer = CloudKitPushDrainer(queue: cloudStore.pushQueue,
                                               database: cloudStore.database,
                                               assetStore: cloudStore,
                                               panelLookup: { [weak self] in
                                                   self?.userPanels() ?? []
                                               })
            drainer.start()
            cloudKitDrainer = drainer
        }
    }

    /// Stops the drainer. Used by tests; production usually lets it
    /// run for the app lifetime.
    func stopCloudKitSync() {
        cloudKitDrainer?.stop()
        cloudKitDrainer = nil
    }

    /// Path to the local sentinel that marks the initial-sync done.
    /// Idempotent file existence check — no parsing, no migration.
    private var cloudKitInitialSyncFlag: URL {
        directory.appendingPathComponent("cloudkit_initial_sync_v1.done")
    }

    /// Seeds the push queue with `savePanel` + `saveInteraction` ops
    /// for every existing user panel on first CloudKit launch. Without
    /// this, a user with custom panels created under a pre-CloudKit
    /// build wouldn't see anything sync until their next edit.
    /// PushQueue's dedupe handles the case where the user makes an
    /// edit before the initial sync runs.
    private func runInitialSyncIfNeeded(queue: PushQueue) {
        guard !FileManager.default.fileExists(atPath: cloudKitInitialSyncFlag.path) else {
            return
        }
        for panel in userPanels() {
            queue.enqueue(.savePanel(id: panel.id))
            for interaction in panel.interactions where !interaction.isBuiltIn {
                queue.enqueue(.saveInteraction(id: interaction.id, parentID: panel.id))
            }
        }
        try? Data().write(to: cloudKitInitialSyncFlag)
    }

    // MARK: - Helpers

    private static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Test-only: writes a PIN hash computed from `rawPIN` *without*
    /// the lowercase normalization `setPIN` applies, to simulate the
    /// on-disk state of an app installed before case-insensitive PINs
    /// shipped. Lets tests exercise the migration branch in `verifyPIN`.
    /// Underscore prefix + suffix mark this as not-for-production-use;
    /// it's `internal` rather than `private` so `@testable import` can
    /// reach it.
    func _setLegacyPINHash_forTesting(_ rawPIN: String) {
        kvs.set(Self.hash(rawPIN), forKey: Self.pinHashKey)
        kvs.synchronize()
    }

    // MARK: - iCloud KVS change observation

    /// Subscribes to `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
    /// and refreshes the local cache files when remote changes for our keys
    /// arrive, then posts `didChangeNotification` so the UI can reload.
    func startObservingICloudChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudKeysDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil
        )
    }

    @objc private func iCloudKeysDidChange(_ note: Notification) {
        guard let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }
        var didChange = false
        if changedKeys.contains(Self.kvsPanelsKey),
           let data = kvs.data(forKey: Self.kvsPanelsKey) {
            try? data.write(to: panelsURL, options: .atomic)
            didChange = true
        }
        if changedKeys.contains(Self.kvsLayoutKey),
           let data = kvs.data(forKey: Self.kvsLayoutKey) {
            try? data.write(to: layoutURL, options: .atomic)
            didChange = true
        }
        if changedKeys.contains(Self.kvsModeKey),
           let raw = kvs.string(forKey: Self.kvsModeKey) {
            // Mirror the remote choice down to UserDefaults so Settings.bundle
            // reflects it and ConfigurationMode.current() returns the right value.
            UserDefaults.standard.set(raw, forKey: ConfigurationMode.userDefaultsKey)
            didChange = true
        }
        if changedKeys.contains(Self.pinHashKey) {
            // A5: another device set or cleared the PIN. Mirror the
            // resulting hasPIN state to the local pin_enabled toggle so
            // iOS Settings reflects reality on this device too.
            let remoteHasPIN = kvs.string(forKey: Self.pinHashKey) != nil
            UserDefaults.standard.set(remoteHasPIN, forKey: "pin_enabled")
            didChange = true
        }
        if didChange {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }
}

// MARK: - UIColor component comparison (used by editor unsaved-changes detection)

/// Compares two UIColor instances by their RGBA components rather than
/// by reference. UIColor doesn't conform to Equatable, and identity
/// comparison ('===') doesn't work because system colors like
/// UIColor.systemBlue may return different instances on each access.
enum UIColorComponents {
    static func areEqual(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) < 0.001
            && abs(ag - bg) < 0.001
            && abs(ab - bb) < 0.001
            && abs(aa - ba) < 0.001
    }
}

// MARK: - PanelListEditor mode-aware affordances (UIKit-free)

/// Section identity for `PanelListEditorViewController` — at file scope
/// so the affordance helpers below can return them as data without the
/// VC having to hold them privately.
enum PanelListEditorSection: Equatable {
    case panels
    case trash
}

/// Pure decisions about which UI affordances to show in
/// `PanelListEditorViewController` given the current `ConfigurationMode`.
/// Extracted so the per-mode logic is unit-testable without
/// instantiating a UITableViewController.
enum PanelListEditorAffordances {

    /// Sections to display for `mode`. Configurable hides Trash because
    /// user panels (and therefore trash entries) can't exist outside
    /// Customize.
    static func sections(for mode: ConfigurationMode) -> [PanelListEditorSection] {
        mode == .custom ? [.panels, .trash] : [.panels]
    }

    /// True when the "+" add-panel button should be shown in the
    /// navigation bar. Configurable can hide / reorder built-ins but
    /// can't author new panels.
    static func addButtonVisible(for mode: ConfigurationMode) -> Bool {
        mode == .custom
    }

    /// True when tapping the row should push into `PanelEditor`.
    /// Built-in panels are never editable; user panels are only
    /// editable in Customize.
    static func panelRowSelectable(panel: Panel,
                                   mode: ConfigurationMode) -> Bool {
        mode == .custom && !panel.isBuiltIn
    }

    /// True when swipe-to-delete should be available on the row.
    static func panelRowDeletable(panel: Panel,
                                  mode: ConfigurationMode) -> Bool {
        mode == .custom && !panel.isBuiltIn
    }

    /// Footer text under the Panels section. Default mode has no
    /// editor → no footer; Configurable explains the limited edits;
    /// Customize explains full edits.
    static func panelsFooter(for mode: ConfigurationMode) -> String? {
        switch mode {
        case .custom:
            return "Toggle to hide a panel from the main list. Drag to reorder. Swipe to delete custom panels. PIN and Clear All My Data live in iOS Settings → iInteract."
        case .configurable:
            return "Toggle to hide a panel from the main list. Drag to reorder. To add or modify panels with your own pictures and recordings, switch to Customize in Settings → iInteract."
        case .default:
            return nil
        }
    }

    /// Footer text under the Trash section. Same in every mode (only
    /// shown in Customize per the `sections(for:)` decision).
    static let trashFooter = "Deleted panels and interactions stay here for 30 days before they're permanently removed."
}

/// Copy for the move-to-Trash confirmation alert shown when the user
/// swipes to delete a custom panel. Extracted as data so tests can
/// snapshot the strings without driving a real `UIAlertController`.
struct DeletePanelConfirmSpec: Equatable {
    let title: String
    let message: String

    static func make(panelTitle: String) -> Self {
        Self(
            title: "Delete \"\(panelTitle)\"?",
            message: "The panel, every interaction on it, and all of its pictures and voice recordings (sound) will move to Trash and be permanently removed after 30 days."
        )
    }
}

// MARK: - TrashRestoreCoordinator (UIKit-free, unit-testable)

/// Why an interaction can't go back to its original parent.
enum TrashAlternateReason: Equatable {
    case parentGone        // parent was permanently deleted
    case parentInTrash     // parent is itself in the recycle bin
    case parentFull        // parent exists but already at 6-interaction cap

    /// Human-readable lead-in used in the alternate-destination action
    /// sheet and the no-candidates error alert.
    var blurb: String {
        switch self {
        case .parentGone:    return "The original panel has been deleted."
        case .parentInTrash: return "The original panel is in Trash."
        case .parentFull:    return "The original panel already has 6 interactions."
        }
    }
}

/// Decision for what to do when the user asks to restore an item from
/// Trash. Computed by inspecting current store state without doing the
/// restore — the caller dispatches the right UI based on the case.
enum TrashRestoreDecision: Equatable {
    /// Store can restore the panel cleanly. Caller should call
    /// `store.restorePanel(trashID:)` and reload.
    case restorePanelDirectly(trashID: UUID)

    /// Panel restore would collide with an active panel. Caller should
    /// prompt for a new title (suggestion provided) and then call
    /// `store.restorePanel(trashID:newTitle:)`.
    case needsRenameForPanel(trashID: UUID, suggestedTitle: String)

    /// Interaction's original parent is active and has room. Caller
    /// should call `store.restoreInteraction(trashID:)` and reload.
    case restoreInteractionDirectly(trashID: UUID)

    /// Interaction's parent panel is itself in the trash. Caller
    /// should ask: "Restore the panel first?" If yes, restore parent
    /// then interaction. If no, fall back to alternate-destination.
    case needsParentDecision(interactionTrashID: UUID,
                             parentTrashID: UUID,
                             parentName: String)

    /// Interaction's parent is gone or full. Caller should show a
    /// picker of alternative active panels with room.
    case needsAlternateDestination(trashID: UUID,
                                   reason: TrashAlternateReason,
                                   candidatePanelIDs: [UUID])

    /// Interaction has nowhere to go and no active panels with room.
    /// Caller should show an explanation; no restore is possible
    /// without making room first.
    case noCandidatesAvailable(reason: TrashAlternateReason)
}

/// Computes a `TrashRestoreDecision` by inspecting the store. Pure
/// logic — no UIKit dependency — so every branch is unit-testable.
enum TrashRestoreCoordinator {

    /// Compute the right next step for restoring `item` given current
    /// store state. Caller dispatches UI based on the returned case.
    static func plan(for item: PanelStore.TrashedItem,
                     in store: PanelStore) -> TrashRestoreDecision {
        switch item.kind {
        case .panel:
            // Decode the snapshot so we can pre-check the title for
            // a collision rather than letting savePanel throw.
            guard let panel = try? JSONDecoder().decode(Panel.self, from: item.snapshot) else {
                // Snapshot is corrupt — best we can do is try the
                // store path and let it surface the error.
                return .restorePanelDirectly(trashID: item.trashID)
            }
            if store.isNameAvailable(panel.title, excluding: panel.id) {
                return .restorePanelDirectly(trashID: item.trashID)
            }
            return .needsRenameForPanel(trashID: item.trashID,
                                        suggestedTitle: panel.title + " (restored)")

        case .interaction:
            if store.canRestoreInteractionToOriginalParent(trashID: item.trashID) {
                return .restoreInteractionDirectly(trashID: item.trashID)
            }
            if let parentTrashID = store.parentPanelTrashID(forInteractionTrashID: item.trashID),
               let parentName = parentNameInTrash(trashID: parentTrashID, store: store) {
                return .needsParentDecision(interactionTrashID: item.trashID,
                                            parentTrashID: parentTrashID,
                                            parentName: parentName)
            }
            // Parent gone OR full. Distinguish via store lookups.
            let candidates = store.panelsAvailableToReceiveInteraction()
            let reason = inferAlternateReason(for: item, store: store)
            if candidates.isEmpty {
                return .noCandidatesAvailable(reason: reason)
            }
            return .needsAlternateDestination(trashID: item.trashID,
                                              reason: reason,
                                              candidatePanelIDs: candidates.map { $0.id })
        }
    }

    private static func parentNameInTrash(trashID: UUID, store: PanelStore) -> String? {
        guard let parentItem = store.trashedItems().first(where: { $0.trashID == trashID }),
              parentItem.kind == .panel,
              let panel = try? JSONDecoder().decode(Panel.self, from: parentItem.snapshot) else {
            return nil
        }
        return panel.title
    }

    /// Best-effort: parent exists in active panels but is full → .parentFull;
    /// parent exists in trash → .parentInTrash; otherwise .parentGone.
    /// Called only when canRestoreInteractionToOriginalParent already
    /// returned false, so "parent active and has room" isn't a branch.
    private static func inferAlternateReason(for item: PanelStore.TrashedItem,
                                              store: PanelStore) -> TrashAlternateReason {
        guard let parentID = item.parentPanelID else {
            return .parentGone
        }
        if store.userPanels().contains(where: { $0.id == parentID }) {
            return .parentFull
        }
        if store.parentPanelTrashID(forInteractionTrashID: item.trashID) != nil {
            return .parentInTrash
        }
        return .parentGone
    }
}
