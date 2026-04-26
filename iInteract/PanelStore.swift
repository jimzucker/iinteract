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
        if didChange {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }
}
