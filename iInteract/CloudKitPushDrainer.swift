//
//  CloudKitPushDrainer.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation
import CloudKit

/// Background `Task` that drains `PushQueue` into a `CloudKitDatabase`.
/// Runs forever once started; cancelled via `stop()` (typically only
/// in tests — production lets it run for the lifetime of the app).
///
/// **Loop**:
/// 1. Take the next `nextDue` entry. If none, sleep until the
///    earliest pending `nextEligibleAt` (or 60s if the queue is empty).
/// 2. Try to push (via `database.save` / `deleteRecord`).
/// 3. On success → `markSuccess` (entry removed).
/// 4. On failure → classify the error; retryable → `markFailure(retryable: true)`
///    advances the backoff; permanent → `markFailure(retryable: false)` drops
///    the entry. The 10-attempt cap in `PushQueue` makes "stuck retryable"
///    errors eventually drop too.
///
/// **Asset operations are translated to record saves at execution.**
/// `uploadAsset` and `deleteAsset` both find the parent interaction
/// and save its full CKRecord with the current local asset state —
/// the encoder in `Interaction.toCKRecord` decides per-field whether
/// to include or omit each CKAsset based on `FileManager.fileExists`.
/// This is wasteful for the bandwidth case (re-uploads unchanged
/// audio when only the picture changed), but correct, simple, and
/// inside the iCloud free quota for this app's scale. A future
/// optimization (v3.1.x) can switch to `CKModifyRecordsOperation` with
/// `.changedKeys` save policy.
///
/// **Disappeared parents** (`unknownItem` thrown from execute) drop
/// the entry. This is the safe choice — it means the panel/interaction
/// was deleted locally between enqueue and drain, so the push is
/// stale and should be skipped.
final class CloudKitPushDrainer {

    private let queue: PushQueue
    private let database: CloudKitDatabase
    private let assetStore: AssetStore
    private let panelLookup: () -> [Panel]
    private let zoneID: CKRecordZone.ID
    private let idleSleep: TimeInterval

    private var task: Task<Void, Never>?

    /// `panelLookup` returns the current set of user panels (no
    /// built-ins) — typically `{ store.userPanels() }`. The drainer
    /// calls it at execute-time to resolve the latest interaction
    /// state for save ops. Built-ins are filtered defensively.
    init(queue: PushQueue,
         database: CloudKitDatabase,
         assetStore: AssetStore,
         panelLookup: @escaping () -> [Panel],
         zoneID: CKRecordZone.ID = CKRecordZone.default().zoneID,
         idleSleep: TimeInterval = 60) {
        self.queue = queue
        self.database = database
        self.assetStore = assetStore
        self.panelLookup = panelLookup
        self.zoneID = zoneID
        self.idleSleep = idleSleep
    }

    /// Idempotent — safe to call multiple times. Subsequent calls are
    /// no-ops while the existing task is alive.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Drains a single eligible entry if one is due. Used by tests
    /// that want deterministic stepping rather than the full async
    /// loop. Production code calls `start()` instead.
    func drainOnce() async {
        guard let entry = queue.nextDue() else { return }
        await execute(entry)
    }

    private func run() async {
        while !Task.isCancelled {
            if queue.nextDue() != nil {
                await drainOnce()
            } else {
                let nextWake = queue.entries.map { $0.nextEligibleAt }.min()
                let interval: TimeInterval
                if let nextWake = nextWake {
                    interval = max(1, nextWake.timeIntervalSinceNow)
                } else {
                    interval = idleSleep
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func execute(_ entry: PushEntry) async {
        do {
            try await dispatch(entry.op)
            queue.markSuccess(entry)
        } catch {
            let decision = classifyCloudKitError(error)
            queue.markFailure(entry, retryable: decision == .retry, now: Date())
        }
    }

    private func dispatch(_ op: PushOperation) async throws {
        switch op {
        case .savePanel(let id):
            try await pushPanelSave(id: id)
        case .deletePanel(let id):
            try await pushDelete(recordName: id.uuidString)
        case .saveInteraction(let id, let parentID):
            try await pushInteractionSave(id: id, parentID: parentID)
        case .deleteInteraction(let id):
            try await pushDelete(recordName: id.uuidString)
        case .uploadAsset(_, let id), .deleteAsset(_, let id):
            // Asset ops translate to a full Interaction record save
            // with the current local asset state.
            try await pushInteractionSaveByID(id: id)
        }
    }

    private func pushPanelSave(id: UUID) async throws {
        guard let panel = panelLookup().first(where: { $0.id == id && !$0.isBuiltIn }) else {
            // Panel disappeared — treat as a no-op drop, not a server
            // round-trip. .unknownItem maps to `.drop` in the
            // classifier, so the queue entry is removed.
            throw CKError(_nsError: NSError(domain: CKErrorDomain,
                                            code: CKError.Code.unknownItem.rawValue))
        }
        _ = try await database.save(panel.toCKRecord(in: zoneID))
    }

    private func pushInteractionSave(id: UUID, parentID: UUID) async throws {
        guard let panel = panelLookup().first(where: { $0.id == parentID && !$0.isBuiltIn }),
              let order = panel.interactions.firstIndex(where: { $0.id == id }),
              !panel.interactions[order].isBuiltIn else {
            throw CKError(_nsError: NSError(domain: CKErrorDomain,
                                            code: CKError.Code.unknownItem.rawValue))
        }
        let interaction = panel.interactions[order]
        let record = interaction.toCKRecord(parentPanelID: parentID,
                                             order: order,
                                             assetURLs: assetURLs(for: id),
                                             in: zoneID)
        _ = try await database.save(record)
    }

    /// Variant for asset operations — caller doesn't know the parent
    /// panel. Searches the lookup for whichever panel currently owns
    /// the interaction.
    private func pushInteractionSaveByID(id: UUID) async throws {
        let panels = panelLookup()
        guard let panel = panels.first(where: { p in
                  !p.isBuiltIn && p.interactions.contains(where: { $0.id == id })
              }),
              let order = panel.interactions.firstIndex(where: { $0.id == id }) else {
            throw CKError(_nsError: NSError(domain: CKErrorDomain,
                                            code: CKError.Code.unknownItem.rawValue))
        }
        let interaction = panel.interactions[order]
        let record = interaction.toCKRecord(parentPanelID: panel.id,
                                             order: order,
                                             assetURLs: assetURLs(for: id),
                                             in: zoneID)
        _ = try await database.save(record)
    }

    private func pushDelete(recordName: String) async throws {
        try await database.deleteRecord(withID:
            CKRecord.ID(recordName: recordName, zoneID: zoneID))
    }

    private func assetURLs(for id: UUID) -> (image: URL?, boy: URL?, girl: URL?) {
        (
            assetStore.exists(.picture, id: id)
                ? assetStore.url(for: .picture, id: id) : nil,
            assetStore.exists(.boyAudio, id: id)
                ? assetStore.url(for: .boyAudio, id: id) : nil,
            assetStore.exists(.girlAudio, id: id)
                ? assetStore.url(for: .girlAudio, id: id) : nil
        )
    }
}
