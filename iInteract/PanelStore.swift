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

// MARK: - KeyValueStorage

/// The slice of NSUbiquitousKeyValueStore that PanelStore needs. Tests inject
/// an in-memory implementation; production uses iCloud KVS.
protocol KeyValueStorage: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
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
}

// MARK: - PanelStore

final class PanelStore {

    static let maxInteractionsPerUserPanel = 6

    /// Production singleton — Application Support + iCloud KVS.
    static let shared = PanelStore(directory: PanelStore.defaultDirectory(),
                                   keyValueStore: NSUbiquitousKeyValueStore.default,
                                   iCloudAvailability: { FileManager.default.ubiquityIdentityToken != nil })

    enum StoreError: Error {
        case nameNotUnique
        case capacityExceeded
        case panelNotFound
        case iCloudUnavailable
        case noSecurityQuestionSet
        case incorrectAnswer
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

    // MARK: - User panels

    func userPanels() -> [Panel] {
        guard let data = try? Data(contentsOf: panelsURL) else { return [] }
        return (try? JSONDecoder().decode([Panel].self, from: data)) ?? []
    }

    private func saveUserPanels(_ panels: [Panel]) throws {
        let data = try JSONEncoder().encode(panels)
        try data.write(to: panelsURL, options: .atomic)
    }

    func addPanel(_ panel: Panel) throws {
        guard !panel.isBuiltIn else { return }
        guard isNameAvailable(panel.title, excluding: panel.id) else {
            throw StoreError.nameNotUnique
        }
        guard panel.interactions.count <= Self.maxInteractionsPerUserPanel else {
            throw StoreError.capacityExceeded
        }
        var panels = userPanels()
        panels.append(panel)
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
        guard let data = try? Data(contentsOf: layoutURL),
              let layout = try? JSONDecoder().decode(Layout.self, from: data) else {
            return Layout()
        }
        return layout
    }

    private func saveLayout(_ layout: Layout) throws {
        let data = try JSONEncoder().encode(layout)
        try data.write(to: layoutURL, options: .atomic)
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

    /// Filters hidden panels and orders the rest by `layout().orderedIDs`.
    /// Panels with no entry in orderedIDs (e.g. a freshly added user panel)
    /// keep their original relative position at the end.
    func applyLayout(to panels: [Panel]) -> [Panel] {
        let l = layout()
        let visible = panels.filter { !l.hiddenIDs.contains($0.id) }
        guard !l.orderedIDs.isEmpty else { return visible }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let ordered = l.orderedIDs.compactMap { byID[$0] }
        let unordered = visible.filter { !l.orderedIDs.contains($0.id) }
        return ordered + unordered
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
}
