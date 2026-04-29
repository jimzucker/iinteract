//
//  CloudKitPullCoordinator.swift
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

/// Drives the pull half of CloudKit sync — the inverse of
/// `CloudKitPushDrainer`. v3.1.2b-i (this file) provides the protocol-
/// agnostic pull loop: ask the database for changes since the last
/// stored change token, accumulate the result, persist the new token
/// so the next call only fetches what's new.
///
/// **v3.1.2b-i scope**: this class returns `CloudKitChanges` to
/// callers; it does NOT apply records to `PanelStore`. v3.1.2b-ii
/// adds a separate apply step that decodes records into the local
/// store. Splitting the two keeps this layer testable independently
/// of the model logic.
///
/// Triggers (added in v3.1.2c):
/// - App launch (called from `startCloudKitSyncIfNeeded`).
/// - `CKDatabaseSubscription` push notification arrival.
/// - User-initiated "refresh" (if such an affordance lands).
final class CloudKitPullCoordinator {

    private let database: CloudKitDatabase
    private let zoneID: CKRecordZone.ID
    private let tokenStore: CloudKitChangeTokenStore

    init(database: CloudKitDatabase,
         zoneID: CKRecordZone.ID = LiveCloudKitDatabase.iInteractZoneID,
         tokenStore: CloudKitChangeTokenStore) {
        self.database = database
        self.zoneID = zoneID
        self.tokenStore = tokenStore
    }

    /// Fetches changes from CloudKit, looping while `moreComing` is
    /// true so a single call returns the complete delta since the
    /// previous server change token. On success, persists the new
    /// token before returning. On failure, throws and leaves the
    /// previously-stored token untouched (next call retries from the
    /// same point).
    func pull() async throws -> CloudKitChanges {
        var aggregate = CloudKitChanges()
        var token = tokenStore.read()
        repeat {
            let batch = try await database.fetchChanges(in: zoneID, since: token)
            aggregate.updatedRecords.append(contentsOf: batch.updatedRecords)
            aggregate.deletedRecords.append(contentsOf: batch.deletedRecords)
            aggregate.newChangeToken = batch.newChangeToken
            aggregate.moreComing = batch.moreComing
            token = batch.newChangeToken
        } while aggregate.moreComing

        if let newToken = aggregate.newChangeToken {
            tokenStore.write(newToken)
        }
        return aggregate
    }
}

/// Persists a `CKServerChangeToken` between launches so successive
/// `CloudKitPullCoordinator.pull()` calls only fetch what's new.
/// Production uses `FileChangeTokenStore`; tests inject
/// `MemoryChangeTokenStore` so they don't pollute disk.
protocol CloudKitChangeTokenStore: AnyObject {
    func read() -> CKServerChangeToken?
    func write(_ token: CKServerChangeToken)
    /// Wipe — used by Clear All My Data flows so a re-pull starts from
    /// scratch.
    func clear()
}

/// File-backed token store. The token is archived via `NSKeyedArchiver`
/// and written atomically to disk. Bad-file recovery: a parse failure
/// renames the file aside (so we don't keep retrying it on every
/// launch) and starts as if no token was stored.
final class FileChangeTokenStore: CloudKitChangeTokenStore {

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func read() -> CKServerChangeToken? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            )
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let bad = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).bad-\(stamp)")
            try? FileManager.default.moveItem(at: url, to: bad)
            NSLog("CloudKit change token file corrupted, moved to \(bad.path): \(error)")
            return nil
        }
    }

    func write(_ token: CKServerChangeToken) {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to persist CloudKit change token: \(error)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
