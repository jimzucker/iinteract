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
    static let shared: PanelStore = {
        let s = PanelStore(directory: PanelStore.defaultDirectory(),
                           keyValueStore: NSUbiquitousKeyValueStore.default,
                           iCloudAvailability: { FileManager.default.ubiquityIdentityToken != nil })
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

    enum AssetKind {
        case picture
        case boyAudio
        case girlAudio

        var fileSuffix: String {
            switch self {
            case .picture:   return ".jpg"
            case .boyAudio:  return ".boy.m4a"
            case .girlAudio: return ".girl.m4a"
            }
        }
    }

    enum Voice {
        case boy, girl
        var assetKind: AssetKind { self == .boy ? .boyAudio : .girlAudio }
    }

    private let directory: URL
    private let kvs: KeyValueStorage
    private let iCloudAvailability: () -> Bool

    init(directory: URL,
         keyValueStore: KeyValueStorage,
         iCloudAvailability: @escaping () -> Bool = { false }) {
        self.directory = directory
        self.kvs = keyValueStore
        self.iCloudAvailability = iCloudAvailability
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

    /// Folder for user-recorded audio + chosen pictures, keyed by interaction id.
    var assetsDirectory: URL {
        let url = directory.appendingPathComponent("UserAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// File URL for a user interaction's asset, used both for reading on
    /// hydrate and for AVAudioRecorder/JPEG writes during editing.
    func assetURL(for interactionID: UUID, kind: AssetKind) -> URL {
        assetsDirectory.appendingPathComponent("\(interactionID.uuidString)\(kind.fileSuffix)")
    }

    /// Reattaches picture and audio URLs to a freshly-decoded user interaction
    /// based on what's on disk. No-op for built-ins (their bundle URLs are
    /// already set by Interaction.init(interactionName:)).
    func hydrate(_ interaction: Interaction) {
        guard !interaction.isBuiltIn else { return }
        let picURL = assetURL(for: interaction.id, kind: .picture)
        if FileManager.default.fileExists(atPath: picURL.path) {
            interaction.picture = UIImage(contentsOfFile: picURL.path)
        }
        let boyURL = assetURL(for: interaction.id, kind: .boyAudio)
        if FileManager.default.fileExists(atPath: boyURL.path) {
            interaction.boySound = boyURL
        }
        let girlURL = assetURL(for: interaction.id, kind: .girlAudio)
        if FileManager.default.fileExists(atPath: girlURL.path) {
            interaction.girlSound = girlURL
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
        try data.write(to: assetURL(for: id, kind: .picture), options: .atomic)
    }

    /// Removes all asset files for an interaction. Safe if files don't exist.
    func deleteInteractionAssets(id: UUID) {
        for kind in [AssetKind.picture, .boyAudio, .girlAudio] {
            try? FileManager.default.removeItem(at: assetURL(for: id, kind: kind))
        }
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
    }

    func deletePanel(id: UUID) throws {
        var panels = userPanels()
        panels.removeAll { $0.id == id }
        try saveUserPanels(panels)
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
        kvs.set(Self.hash(pin), forKey: Self.pinHashKey)
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
        return Self.hash(pin) == stored
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
        if let entries = try? FileManager.default.contentsOfDirectory(at: assetsDirectory,
                                                                       includingPropertiesForKeys: nil) {
            for url in entries {
                try? FileManager.default.removeItem(at: url)
            }
        }
        emptyTrash()
        clearPIN()
        kvs.removeObject(forKey: Self.kvsPanelsKey)
        kvs.removeObject(forKey: Self.kvsLayoutKey)
        kvs.removeObject(forKey: Self.kvsModeKey)
        kvs.synchronize()
    }

    // MARK: - Helpers

    private static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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

// MARK: - TrashRestoreCoordinator (UIKit-free, unit-testable)

/// Why an interaction can't go back to its original parent.
enum TrashAlternateReason: Equatable {
    case parentGone        // parent was permanently deleted
    case parentInTrash     // parent is itself in the recycle bin
    case parentFull        // parent exists but already at 6-interaction cap
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
