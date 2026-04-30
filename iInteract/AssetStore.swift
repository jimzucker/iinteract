//
//  AssetStore.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation

/// User-recorded audio + chosen pictures for a custom Interaction.
/// Three asset files per interaction, keyed off the interaction UUID.
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

/// Storage for user-recorded audio + selected pictures, keyed by
/// interaction UUID. The local-FS implementation today writes/reads
/// directly under PanelStore's UserAssets directory; the planned
/// CloudKit implementation (v3.1.1+, see docs/CLOUDKIT_MIGRATION.md)
/// will mirror writes to a private database and stage downloads to
/// the same on-disk cache.
///
/// Callers receive file URLs rather than `Data` because:
/// - `AVAudioRecorder` records to a destination URL directly.
/// - `UIImage(contentsOfFile:)` reads from a path.
/// - The Interaction model holds URLs for boy/girl audio for playback.
protocol AssetStore {
    /// Resolved file URL for an interaction's asset, even if the file
    /// doesn't yet exist (callers use this both as a destination for
    /// AVAudioRecorder writes and as a path for subsequent reads).
    func url(for kind: AssetKind, id: UUID) -> URL

    /// True iff the asset file currently exists on disk.
    func exists(_ kind: AssetKind, id: UUID) -> Bool

    /// Atomically writes data to the asset URL. Used for picture saves
    /// from PHPicker (audio is recorded directly via AVAudioRecorder
    /// to the URL returned by `url(for:id:)`).
    func write(_ data: Data, kind: AssetKind, id: UUID) throws

    /// Apply-path variant of `write` for v3.1.2b — writes to the local
    /// cache WITHOUT enqueueing a CloudKit push. Used by
    /// `CloudKitChangeApplier` when downloading assets from a pulled
    /// `CKAsset` to avoid pushing the same bytes back up. Local-FS
    /// implementations forward to `write` since they have no push
    /// queue. Only call from the apply path.
    func applyRemoteWrite(_ data: Data, kind: AssetKind, id: UUID) throws

    /// Called by the editor after a caller wrote to the URL returned by
    /// `url(for:id:)` without going through `write(_:kind:id:)` — most
    /// often AVAudioRecorder finishing a recording. Local-FS
    /// implementations no-op; CloudKit-backed implementations
    /// (v3.1.1+, see docs/CLOUDKIT_V3.1.1_PLAN.md) enqueue the file
    /// for upload. Must be called from the recorder's stop completion
    /// handler, not when the user taps "Stop," so the file is fully
    /// flushed before the upload reads it.
    func didExternallyWrite(_ kind: AssetKind, id: UUID)

    /// Removes a single asset file. No-op if missing.
    func delete(_ kind: AssetKind, id: UUID)

    /// Removes all 3 asset files (picture + boy + girl audio) for an
    /// interaction. No-op for any kind that's missing.
    func deleteAll(id: UUID)

    /// Removes every asset for every interaction. Used by the Settings
    /// "Clear All My Data" wipe. Trash-folder blobs are handled
    /// separately by PanelStore.
    func deleteEverything()

    /// File system root for the active assets — exposed because the
    /// trash/restore flow operates on raw URLs (move file out of the
    /// active dir into a per-trash-item folder, and back on restore).
    /// Kept on the protocol so future stores that fully abstract the
    /// location can decide whether to expose a cache directory or
    /// throw — the local-FS implementation is the only meaningful
    /// case today.
    var rootDirectory: URL { get }
}

/// File-system implementation backed by a fixed directory.
/// Production wiring (`PanelStore.shared`) places this under
/// `Application Support/PanelStore/UserAssets`. Tests inject a
/// temporary directory so they don't pollute the real store.
final class LocalFSAssetStore: AssetStore {

    let rootDirectory: URL

    /// `parentDirectory` is typically the same `directory` PanelStore
    /// itself was initialized with — the asset store creates and owns
    /// the `UserAssets/` subfolder beneath it.
    init(parentDirectory: URL) {
        self.rootDirectory = parentDirectory.appendingPathComponent("UserAssets",
                                                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: rootDirectory,
                                                 withIntermediateDirectories: true)
    }

    func url(for kind: AssetKind, id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString)\(kind.fileSuffix)")
    }

    func exists(_ kind: AssetKind, id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: kind, id: id).path)
    }

    func write(_ data: Data, kind: AssetKind, id: UUID) throws {
        try data.write(to: url(for: kind, id: id), options: .atomic)
    }

    /// Local-FS has no push queue, so the apply-path variant is just
    /// a normal write — same end state as `write(_:kind:id:)`.
    func applyRemoteWrite(_ data: Data, kind: AssetKind, id: UUID) throws {
        try write(data, kind: kind, id: id)
    }

    /// Local-FS no-op: there's nothing to enqueue, the file is already
    /// at its final destination as soon as the caller finishes writing.
    func didExternallyWrite(_ kind: AssetKind, id: UUID) {}

    func delete(_ kind: AssetKind, id: UUID) {
        try? FileManager.default.removeItem(at: url(for: kind, id: id))
    }

    func deleteAll(id: UUID) {
        for kind in [AssetKind.picture, .boyAudio, .girlAudio] {
            delete(kind, id: id)
        }
    }

    func deleteEverything() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil) else { return }
        for url in entries {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
