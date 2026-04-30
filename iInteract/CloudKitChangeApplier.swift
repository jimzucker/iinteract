//
//  CloudKitChangeApplier.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit
import CloudKit

/// Applies a `CloudKitChanges` payload (the result of a pull) to the
/// local `PanelStore` and `AssetStore`. v3.1.2b-ii landing.
///
/// **Avoiding the pull→push feedback loop**: every write here goes
/// through the `applyRemote*` variants on PanelStore and AssetStore,
/// which match the regular write semantics but skip the CloudKit
/// push enqueue. Without these variants, applying a pulled record
/// would re-push the same record, the next pull would receive it
/// back again, etc.
///
/// **Application order matters within a batch**:
/// 1. UserPanel records first (creates the parent rows).
/// 2. Interaction records second (need parents to exist).
/// 3. Deletions last (deleting a parent before its children avoids
///    a window where children are orphaned in the cloud — local
///    state stays consistent).
final class CloudKitChangeApplier {

    private let store: PanelStore
    private let assetStore: AssetStore

    init(store: PanelStore, assetStore: AssetStore) {
        self.store = store
        self.assetStore = assetStore
    }

    /// Applies the changes. Errors are logged and skipped per-record;
    /// the caller's pull token still advances so we don't re-fetch
    /// the same problematic record on every call.
    func apply(_ changes: CloudKitChanges) {
        // Sort updates: panels before interactions so children find
        // their parents.
        let panelUpdates = changes.updatedRecords.filter {
            $0.recordType == CloudKitRecordType.userPanel
        }
        let interactionUpdates = changes.updatedRecords.filter {
            $0.recordType == CloudKitRecordType.interaction
        }
        for record in panelUpdates {
            applyPanel(record)
        }
        for record in interactionUpdates {
            applyInteraction(record)
        }
        for deletion in changes.deletedRecords {
            applyDeletion(deletion)
        }
    }

    // MARK: - UserPanel record → local Panel

    private func applyPanel(_ record: CKRecord) {
        guard let panelIDString = record["panelID"] as? String,
              let panelID = UUID(uuidString: panelIDString),
              let title = record["title"] as? String,
              let colorBytes = record["colorRGBA"] as? Data else {
            NSLog("CloudKitChangeApplier: malformed UserPanel record \(record.recordID); skipping")
            return
        }
        let color = decodeColor(from: colorBytes)
        let existing = store.userPanels().first(where: { $0.id == panelID })
        // Preserve existing interactions — their records arrive
        // separately and may already be applied.
        let interactions = existing?.interactions ?? []
        let panel = Panel(id: panelID,
                          title: title,
                          color: color,
                          interactions: interactions,
                          isBuiltIn: false)
        do {
            try store.applyRemotelySavedPanel(panel)
        } catch {
            NSLog("CloudKitChangeApplier: panel save failed for \(panelID): \(error)")
        }
    }

    /// 4 little-endian Float32s = 16 bytes. Mirrors the encoding in
    /// `Panel.colorRGBABytes()`.
    private func decodeColor(from data: Data) -> UIColor {
        guard data.count >= 16 else { return .systemGray }
        var floats = [Float32](repeating: 0, count: 4)
        _ = floats.withUnsafeMutableBytes { buffer in
            data.copyBytes(to: buffer, count: 16)
        }
        let clamp: (Float32) -> CGFloat = { CGFloat(min(max($0, 0), 1)) }
        return UIColor(red: clamp(floats[0]),
                       green: clamp(floats[1]),
                       blue: clamp(floats[2]),
                       alpha: clamp(floats[3]))
    }

    // MARK: - Interaction record → local Interaction

    private func applyInteraction(_ record: CKRecord) {
        guard let interactionIDString = record["interactionID"] as? String,
              let interactionID = UUID(uuidString: interactionIDString),
              let parentRef = record["panelRef"] as? CKRecord.Reference,
              let parentID = UUID(uuidString: parentRef.recordID.recordName),
              let displayName = record["displayName"] as? String else {
            NSLog("CloudKitChangeApplier: malformed Interaction record \(record.recordID); skipping")
            return
        }
        let order = (record["order"] as? Int64).flatMap { Int($0) } ?? 0

        // Download CKAssets to the local cache via the apply-path
        // (no enqueue) so the next read is instant and offline-safe.
        downloadAsset(record["imageAsset"]    as? CKAsset, kind: .picture,   id: interactionID)
        downloadAsset(record["audioBoyAsset"] as? CKAsset, kind: .boyAudio,  id: interactionID)
        downloadAsset(record["audioGirlAsset"] as? CKAsset, kind: .girlAudio, id: interactionID)

        // Find or create parent panel. If the parent doesn't exist
        // locally, skip — the next pull (or this one's panel-records
        // pass) should bring it. We don't auto-create parents from
        // child records to avoid drift.
        guard let panel = store.userPanels().first(where: { $0.id == parentID }) else {
            NSLog("CloudKitChangeApplier: parent panel \(parentID) not found for interaction \(interactionID); deferring")
            return
        }

        let interaction = Interaction(id: interactionID, name: displayName)
        store.hydrate(interaction)  // attach picture/audio URLs from the cache we just populated

        // Upsert into the panel's interactions array.
        if let existingIdx = panel.interactions.firstIndex(where: { $0.id == interactionID }) {
            panel.interactions[existingIdx] = interaction
        } else {
            // Order is the server's opinion of where this interaction
            // sits. Insert at that position if it's in range,
            // otherwise append (defensive).
            if order >= 0 && order <= panel.interactions.count {
                panel.interactions.insert(interaction, at: order)
            } else {
                panel.interactions.append(interaction)
            }
        }
        do {
            try store.applyRemotelySavedPanel(panel)
        } catch {
            NSLog("CloudKitChangeApplier: panel update for interaction \(interactionID) failed: \(error)")
        }
    }

    private func downloadAsset(_ asset: CKAsset?, kind: AssetKind, id: UUID) {
        guard let asset = asset, let fileURL = asset.fileURL else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            NSLog("CloudKitChangeApplier: couldn't read CKAsset bytes at \(fileURL.path)")
            return
        }
        do {
            try assetStore.applyRemoteWrite(data, kind: kind, id: id)
        } catch {
            NSLog("CloudKitChangeApplier: cache write failed for \(kind)/\(id): \(error)")
        }
    }

    // MARK: - Deletions

    private func applyDeletion(_ deletion: DeletedRecord) {
        guard let id = UUID(uuidString: deletion.recordID.recordName) else {
            NSLog("CloudKitChangeApplier: deletion with non-UUID recordName \(deletion.recordID.recordName); skipping")
            return
        }
        switch deletion.recordType {
        case CloudKitRecordType.userPanel:
            do {
                try store.applyRemotelyDeletedPanel(id: id)
            } catch {
                NSLog("CloudKitChangeApplier: panel delete failed for \(id): \(error)")
            }

        case CloudKitRecordType.interaction:
            // Scan panels to find which one owns this interaction,
            // remove it, save back. Cheaper than a separate index for
            // the volumes this app sees.
            for panel in store.userPanels() {
                if let idx = panel.interactions.firstIndex(where: { $0.id == id }) {
                    panel.interactions.remove(at: idx)
                    do {
                        try store.applyRemotelySavedPanel(panel)
                    } catch {
                        NSLog("CloudKitChangeApplier: panel update after interaction delete failed: \(error)")
                    }
                    return
                }
            }

        default:
            NSLog("CloudKitChangeApplier: unknown deleted record type \(deletion.recordType); skipping")
        }
    }
}
