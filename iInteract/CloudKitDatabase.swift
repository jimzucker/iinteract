//
//  CloudKitDatabase.swift
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

/// One round of changes returned from a fetch — record updates, the
/// IDs and types of deletions, the new server change token to persist
/// for the next fetch, and a flag indicating whether more changes are
/// available (caller should fetch again with the new token).
struct CloudKitChanges: Equatable {
    var updatedRecords: [CKRecord] = []
    var deletedRecords: [DeletedRecord] = []
    var newChangeToken: CKServerChangeToken? = nil
    var moreComing: Bool = false
}

/// Tombstone returned from `fetchChanges`. We need both the recordID
/// (to find the local row) and the record type (to know whether it
/// was a UserPanel or Interaction) since `CKRecord.ID` alone doesn't
/// carry that distinction.
struct DeletedRecord: Equatable {
    let recordID: CKRecord.ID
    let recordType: String
}

/// Injection seam for `CloudKitAssetStore`, the v3.1.1c drainer, and
/// the v3.1.2b pull coordinator. Production wraps a real `CKDatabase`;
/// tests inject a mock that records what was called and returns
/// canned responses.
protocol CloudKitDatabase {
    func save(_ record: CKRecord) async throws -> CKRecord
    func deleteRecord(withID recordID: CKRecord.ID) async throws
    /// Idempotent — succeeds whether the zone existed or not.
    /// Required before any record save in a custom zone, and required
    /// for `CKFetchRecordZoneChangesOperation` to work.
    func saveZone(_ zone: CKRecordZone) async throws
    /// Fetches changes in `zoneID` since the previous server change
    /// token (`nil` for the first ever fetch from this device — pulls
    /// everything from scratch). Returns a `CloudKitChanges` carrying
    /// the new token to persist for the next call. v3.1.2b coordinator
    /// loops while `moreComing == true` to pick up large change sets.
    func fetchChanges(in zoneID: CKRecordZone.ID,
                      since previousToken: CKServerChangeToken?) async throws -> CloudKitChanges
    /// Subscribes the device to silent-push notifications when any
    /// record changes in the subscription's zone. v3.1.2c bootstrap.
    /// Apple's `database.save(_ subscription:)` is idempotent when
    /// given the same subscription ID, so calling this on every
    /// launch is safe (just a no-op network call after the first).
    func saveSubscription(_ subscription: CKSubscription) async throws
}

/// Production implementation. Constructed against the iInteract
/// CloudKit container declared in the entitlements file. Operates on
/// the *default* zone for v3.1.1 — custom zones are needed only when
/// `CKFetchRecordZoneChangesOperation` is added in v3.1.2; switching
/// then is a tractable one-shot migration.
struct LiveCloudKitDatabase: CloudKitDatabase {
    /// Matches `iInteract.entitlements`. Note the lowercase
    /// "iinteract" — the bundle ID is mixed-case but the container
    /// was registered lowercase in the Apple Developer portal and
    /// the entitlement matches. CloudKit IDs are case-sensitive.
    static let defaultContainerID = "iCloud.com.ijaz.iinteract"

    /// Custom zone for iInteract records. Custom zones are required
    /// for `CKFetchRecordZoneChangesOperation` + change-token-based
    /// pulls (v3.1.2b) — the default zone doesn't support them. We
    /// move all UserPanel/Interaction records here from the start so
    /// future pull work doesn't need a migration.
    static let iInteractZoneID = CKRecordZone.ID(zoneName: "iInteractZone",
                                                 ownerName: CKCurrentUserDefaultName)

    /// Stable identifier for the iInteract zone subscription. Apple's
    /// `database.save(_ subscription:)` is idempotent when given the
    /// same ID, so re-saving a subscription with this ID on every
    /// launch is safe.
    static let iInteractSubscriptionID = "iInteractZoneChangesSubscription"

    let database: CKDatabase

    init(containerID: String = Self.defaultContainerID) {
        self.database = CKContainer(identifier: containerID).privateCloudDatabase
    }

    func save(_ record: CKRecord) async throws -> CKRecord {
        try await database.save(record)
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
    }

    func saveZone(_ zone: CKRecordZone) async throws {
        // CKDatabase.save(_:) on a CKRecordZone is idempotent — succeeds
        // whether the zone exists or not. Bootstrapping logic in the
        // drainer relies on this.
        _ = try await database.save(zone)
    }

    func fetchChanges(in zoneID: CKRecordZone.ID,
                      since previousToken: CKServerChangeToken?) async throws -> CloudKitChanges {
        // Apple's modern async API returns a multi-part tuple. We
        // unpack into our own simpler `CloudKitChanges` so callers
        // don't have to know the CKDatabase result shape.
        let result = try await database.recordZoneChanges(
            inZoneWith: zoneID,
            since: previousToken
        )
        var updated: [CKRecord] = []
        for (_, modificationResult) in result.modificationResultsByID {
            // Per-record failures inside a successful fetch are rare
            // (typically network mid-flight). Skip them; they'll come
            // back in the next fetch.
            if case .success(let modResult) = modificationResult {
                updated.append(modResult.record)
            }
        }
        let deletions = result.deletions.map { deletion in
            DeletedRecord(recordID: deletion.recordID,
                          recordType: deletion.recordType)
        }
        return CloudKitChanges(updatedRecords: updated,
                               deletedRecords: deletions,
                               newChangeToken: result.changeToken,
                               moreComing: result.moreComing)
    }

    func saveSubscription(_ subscription: CKSubscription) async throws {
        _ = try await database.save(subscription)
    }
}

// MARK: - Error classification

/// Decision the drainer makes about how to handle a failed CloudKit
/// operation. Maps `CKError.Code` (and Foundation errors) into a
/// retryable-vs-permanent split that `PushQueue.markFailure` understands.
enum RetryDecision: Equatable {
    case retry  ///  Transient — apply backoff, re-enqueue.
    case drop   ///  Permanent — surface to user, give up.
}

/// Classifies a CloudKit error for retry handling. Conservative on
/// unknowns: anything we don't recognize is treated as retryable, and
/// the push queue's `maxRetries` cap (10) guarantees the entry
/// eventually drops if it never succeeds.
func classifyCloudKitError(_ error: Error) -> RetryDecision {
    guard let ckError = error as? CKError else {
        // Non-CKError (Foundation, URLSession, etc.). Almost always a
        // transient I/O issue. Retry conservatively.
        return .retry
    }
    switch ckError.code {

    // Transient — wait and try again
    case .networkUnavailable,
         .networkFailure,
         .requestRateLimited,
         .serviceUnavailable,
         .zoneBusy,
         .notAuthenticated:
        return .retry

    // Permanent — no point retrying
    case .quotaExceeded,
         .unknownItem,
         .serverRejectedRequest,
         .permissionFailure,
         .badContainer,
         .badDatabase,
         .invalidArguments,
         .incompatibleVersion,
         .constraintViolation,
         .changeTokenExpired,
         .batchRequestFailed,
         .managedAccountRestricted,
         .userDeletedZone:
        return .drop

    default:
        // Unknown code: retry. Push queue's 10-attempt cap limits the
        // damage if the error is actually permanent.
        return .retry
    }
}
