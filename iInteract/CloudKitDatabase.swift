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

/// Injection seam for `CloudKitAssetStore` and the v3.1.1c drainer.
/// Production wraps a real `CKDatabase`; tests inject a mock that
/// records what was called and returns canned responses.
///
/// Only the operations needed for v3.1.1 push-only sync are here:
/// single-record save + delete. v3.1.2 will add fetch + change-token
/// + subscription methods when pull lands.
protocol CloudKitDatabase {
    func save(_ record: CKRecord) async throws -> CKRecord
    func deleteRecord(withID recordID: CKRecord.ID) async throws
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
