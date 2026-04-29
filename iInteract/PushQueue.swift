//
//  PushQueue.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation

/// A single mutation that needs to be pushed to CloudKit. Persisted as
/// JSON in the push queue so it survives app relaunch.
///
/// Asset operations are emitted by `CloudKitAssetStore` (v3.1.1b);
/// panel/interaction record operations are emitted by a sibling
/// observer of `PanelStore.didChangeNotification` (v3.1.1c). v3.1.1a
/// defines the full enum so later sub-commits don't churn the
/// persistence shape.
enum PushOperation: Codable, Equatable {
    case savePanel(id: UUID)
    case deletePanel(id: UUID)
    case saveInteraction(id: UUID, parentID: UUID)
    case deleteInteraction(id: UUID)
    case uploadAsset(kind: AssetKind, id: UUID)
    case deleteAsset(kind: AssetKind, id: UUID)
}

extension AssetKind: Codable, Equatable {
    // The default-synthesized Codable for Codable enums-with-no-payloads
    // stores them as e.g. {"picture": {}} — verbose. Encode/decode as a
    // plain string instead so the on-disk push queue stays tidy.
    private enum Wire: String, Codable {
        case picture, boyAudio, girlAudio
    }

    public init(from decoder: Decoder) throws {
        switch try Wire(from: decoder) {
        case .picture:   self = .picture
        case .boyAudio:  self = .boyAudio
        case .girlAudio: self = .girlAudio
        }
    }

    public func encode(to encoder: Encoder) throws {
        let wire: Wire
        switch self {
        case .picture:   wire = .picture
        case .boyAudio:  wire = .boyAudio
        case .girlAudio: wire = .girlAudio
        }
        try wire.encode(to: encoder)
    }
}

extension PushOperation {
    /// A stable identity for "what this operation targets." Dedupe and
    /// cross-type supersession use this to collapse redundant pending
    /// work into a single entry — e.g. two `uploadAsset(.picture, X)`
    /// in a row only need to fire once with the latest data.
    enum Target: Hashable {
        case panel(UUID)
        case interaction(UUID)
        case asset(AssetKind, UUID)
    }

    var target: Target {
        switch self {
        case .savePanel(let id), .deletePanel(let id):
            return .panel(id)
        case .saveInteraction(let id, _), .deleteInteraction(let id):
            return .interaction(id)
        case .uploadAsset(let kind, let id), .deleteAsset(let kind, let id):
            return .asset(kind, id)
        }
    }

    var isDelete: Bool {
        switch self {
        case .deletePanel, .deleteInteraction, .deleteAsset: return true
        case .savePanel, .saveInteraction, .uploadAsset:     return false
        }
    }
}

/// One scheduled push attempt. Created by `PushQueue.enqueue`, persisted
/// to disk, retired on success or after the retry cap is reached.
struct PushEntry: Codable, Equatable {
    let id: UUID
    let op: PushOperation
    let createdAt: Date
    var retryCount: Int
    var nextEligibleAt: Date
}

/// Persistent FIFO of pending CloudKit pushes with retry/backoff state.
///
/// Design rules:
/// - **Persistence**: every mutation writes the queue to disk atomically
///   so a crash mid-push doesn't lose pending work.
/// - **Dedupe**: a new operation targeting the same `Target` removes any
///   pending operation against that target — only the latest matters
///   (latest content for uploads, latest decision for save vs. delete).
/// - **Cross-target supersession**: `deleteInteraction(id: I)` also
///   removes pending `uploadAsset(_, id: I)` / `deleteAsset(_, id: I)` /
///   `saveInteraction(id: I, _)` for that interaction — the parent
///   delete cascades server-side via `panelRef.deleteSelf`, so
///   pre-emptively dropping its child pushes saves work and avoids
///   futile uploads of files about to be cleaned up.
/// - **Backoff**: failed entries advance `nextEligibleAt` per the
///   schedule in `Self.backoff`. After `Self.maxRetries` attempts
///   the entry is dropped and the caller can surface a one-time alert.
/// - **Bad-file recovery**: if the persisted JSON fails to parse, the
///   bad file is renamed to `*.bad-<timestamp>.json` and the queue
///   starts empty rather than crashing the app.
final class PushQueue {

    static let maxRetries = 10
    /// Backoff schedule in seconds. After exhausting the schedule the
    /// last value (12h) is reused until `maxRetries` is hit.
    static let backoff: [TimeInterval] = [
        30,        //  0  → 30s
        120,       //  1  → 2m
        480,       //  2  → 8m
        1800,      //  3  → 30m
        7200,      //  4  → 2h
        43200,     //  5+ → 12h
    ]

    private let persistedAt: URL
    private(set) var entries: [PushEntry]

    init(persistedAt: URL) {
        self.persistedAt = persistedAt
        self.entries = Self.loadFromDisk(at: persistedAt)
    }

    // MARK: - Public API

    /// Adds an operation, applying dedupe + cross-target supersession.
    /// Returns the resulting `PushEntry` for tests/observers.
    @discardableResult
    func enqueue(_ op: PushOperation, now: Date = Date()) -> PushEntry {
        applySupersession(for: op)
        let entry = PushEntry(id: UUID(), op: op,
                              createdAt: now, retryCount: 0,
                              nextEligibleAt: now)
        entries.append(entry)
        save()
        return entry
    }

    /// First entry whose `nextEligibleAt` is <= now, in FIFO order.
    func nextDue(now: Date = Date()) -> PushEntry? {
        entries.first { $0.nextEligibleAt <= now }
    }

    /// Removes an entry after a successful push.
    func markSuccess(_ entry: PushEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Records a failed attempt. If `retryable`, applies backoff and
    /// keeps the entry (or drops it once `maxRetries` is reached). If
    /// not retryable, drops the entry immediately — caller should log
    /// or surface the error before calling.
    /// Returns true if the entry remains in the queue, false if dropped.
    @discardableResult
    func markFailure(_ entry: PushEntry,
                     retryable: Bool,
                     now: Date = Date()) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else {
            return false
        }
        if !retryable {
            entries.remove(at: idx)
            save()
            return false
        }
        var updated = entries[idx]
        updated.retryCount += 1
        if updated.retryCount >= Self.maxRetries {
            entries.remove(at: idx)
            save()
            return false
        }
        let stepIndex = min(updated.retryCount - 1, Self.backoff.count - 1)
        let delay = Self.backoff[max(0, stepIndex)]
        updated.nextEligibleAt = now.addingTimeInterval(delay)
        entries[idx] = updated
        save()
        return true
    }

    // MARK: - Dedupe + supersession

    private func applySupersession(for incoming: PushOperation) {
        // Same-target dedupe: drop any pending op against the same target.
        // For save→delete, this means the new delete supersedes the old
        // save. For two saves in a row, the new save supersedes the old.
        entries.removeAll { $0.op.target == incoming.target }

        // Cross-target: a deleteInteraction also drops pending
        // child-asset ops and saveInteraction ops for that interaction.
        if case .deleteInteraction(let id) = incoming {
            entries.removeAll { entry in
                switch entry.op {
                case .uploadAsset(_, let assetID),
                     .deleteAsset(_, let assetID):
                    return assetID == id
                case .saveInteraction(let savedID, _):
                    return savedID == id
                default:
                    return false
                }
            }
        }

        // A deletePanel cascades server-side, but pre-emptively drop
        // child saveInteraction ops for that panel so we don't push
        // doomed records before the cascade fires.
        if case .deletePanel(let panelID) = incoming {
            entries.removeAll { entry in
                if case .saveInteraction(_, let parentID) = entry.op {
                    return parentID == panelID
                }
                return false
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(entries)
            try data.write(to: persistedAt, options: .atomic)
        } catch {
            // Persistence failure shouldn't crash the app; the in-memory
            // queue remains correct. Worst case: a crash before the next
            // successful save loses recently-enqueued entries — caller's
            // local change still landed, just won't sync until enqueued
            // again.
            NSLog("PushQueue: failed to persist queue: \(error)")
        }
    }

    private static func loadFromDisk(at url: URL) -> [PushEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([PushEntry].self, from: data)
        } catch {
            // Corrupted file. Move it aside so we don't keep retrying
            // a bad parse on every launch, and start with an empty
            // queue. Pending pushes from the corrupted file are lost
            // — the trade is "lose pending sync work" vs. "fail to
            // launch sync." The first is recoverable (next local edit
            // re-enqueues), the second is not.
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let bad = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).bad-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: bad)
            NSLog("PushQueue: corrupted queue file moved to \(bad.path): \(error)")
            return []
        }
    }
}
