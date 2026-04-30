//
//  CloudKitAssetStore.swift
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

/// Local-first AssetStore that mirrors writes to CloudKit via
/// `PushQueue`. Reads always hit the local cache (a `LocalFSAssetStore`
/// rooted at the same `UserAssets/` directory as before), so playback,
/// hydration, and existence checks are instant and offline-safe.
///
/// **v3.1.1b scope**: this class enqueues operations into `PushQueue`
/// but doesn't actively drain. The drainer is a separate `Task`
/// kicked off in v3.1.1c at app launch. Until that lands, queued
/// operations accumulate on disk — local writes still work, they
/// just don't reach iCloud until the drainer arrives.
///
/// `deleteEverything()` is intentionally local-only: the
/// "Clear All My Data on Resume" toggle is documented as wiping the
/// device, not deleting iCloud copies, so the user can re-sync from
/// another device. A separate "Also clear iCloud copy" affordance can
/// land in v3.1.3 if users ask for it.
final class CloudKitAssetStore: AssetStore {

    private let cache: LocalFSAssetStore
    let database: CloudKitDatabase
    let pushQueue: PushQueue

    var rootDirectory: URL { cache.rootDirectory }

    /// `parentDirectory` is typically the same directory `PanelStore`
    /// itself was constructed with. The local cache lives under
    /// `parentDirectory/UserAssets` (matching `LocalFSAssetStore`),
    /// and the push queue persists at
    /// `parentDirectory/CloudKitPushQueue.json`.
    init(parentDirectory: URL,
         database: CloudKitDatabase = LiveCloudKitDatabase(),
         pushQueueURL: URL? = nil) {
        self.cache = LocalFSAssetStore(parentDirectory: parentDirectory)
        self.database = database
        self.pushQueue = PushQueue(persistedAt:
            pushQueueURL ?? parentDirectory.appendingPathComponent("CloudKitPushQueue.json"))
    }

    // MARK: - Reads (pure passthrough to local cache)

    func url(for kind: AssetKind, id: UUID) -> URL {
        cache.url(for: kind, id: id)
    }

    func exists(_ kind: AssetKind, id: UUID) -> Bool {
        cache.exists(kind, id: id)
    }

    // MARK: - Writes (cache + enqueue)

    func write(_ data: Data, kind: AssetKind, id: UUID) throws {
        try cache.write(data, kind: kind, id: id)
        pushQueue.enqueue(.uploadAsset(kind: kind, id: id))
    }

    /// v3.1.2b apply path — write to the local cache, do NOT enqueue.
    /// `CloudKitChangeApplier` calls this when downloading bytes from
    /// a pulled `CKAsset`; pushing them back up would create a
    /// pull→push feedback loop.
    func applyRemoteWrite(_ data: Data, kind: AssetKind, id: UUID) throws {
        try cache.write(data, kind: kind, id: id)
    }

    func didExternallyWrite(_ kind: AssetKind, id: UUID) {
        // Caller (typically AVAudioRecorder finish handler) wrote
        // directly to `url(for:id:)` — file is already in the local
        // cache, just enqueue the upload.
        pushQueue.enqueue(.uploadAsset(kind: kind, id: id))
    }

    func delete(_ kind: AssetKind, id: UUID) {
        cache.delete(kind, id: id)
        pushQueue.enqueue(.deleteAsset(kind: kind, id: id))
    }

    func deleteAll(id: UUID) {
        cache.deleteAll(id: id)
        // `deleteInteraction` cascades on the server-side via the
        // panelRef.deleteSelf action when its parent panel is deleted,
        // but here we're only deleting one interaction — explicitly
        // enqueue its server-side deletion. PushQueue's supersession
        // also drops any pending uploads/deletes for this interaction.
        pushQueue.enqueue(.deleteInteraction(id: id))
    }

    func deleteEverything() {
        cache.deleteEverything()
        // Local-only wipe — see class doc comment for rationale.
    }
}
