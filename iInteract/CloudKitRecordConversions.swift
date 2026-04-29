//
//  CloudKitRecordConversions.swift
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

// MARK: - Record types

/// Stable string constants for record types — referenced by both the
/// encode side here and the future fetch/decode side in v3.1.2. Keep
/// in sync with the schema in CloudKit Dashboard (see
/// docs/CLOUDKIT_V3.1.1_PLAN.md, "Schema").
enum CloudKitRecordType {
    static let userPanel   = "UserPanel"
    static let interaction = "Interaction"
}

// MARK: - Panel → CKRecord

extension Panel {
    /// Encodes a user panel as a `UserPanel` CKRecord. Built-in panels
    /// are bundled with the app and never sync — callers must filter
    /// before calling.
    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.userPanel, recordID: recordID)
        record["panelID"]   = id.uuidString as CKRecordValue
        record["title"]     = title as CKRecordValue
        record["colorRGBA"] = colorRGBABytes() as CKRecordValue
        return record
    }

    /// 16-byte payload: 4 little-endian Float32s (R, G, B, A) clamped
    /// to [0,1]. Same encoding the JSON Codable produces, so a future
    /// reader doesn't have to know which format wrote it.
    func colorRGBABytes() -> Data {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // Resolve dynamic colors against the current trait collection
        // so .systemBlue etc. don't return out-of-[0,1] extended-sRGB
        // values that would round-trip differently on another device.
        color.resolvedColor(with: UITraitCollection.current)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp: (CGFloat) -> Float32 = { Float32(min(max($0, 0), 1)) }
        var floats: [Float32] = [clamp(r), clamp(g), clamp(b), clamp(a)]
        return Data(bytes: &floats, count: MemoryLayout<Float32>.size * 4)
    }
}

// MARK: - Interaction → CKRecord

extension Interaction {
    /// Encodes a user interaction as an `Interaction` CKRecord with a
    /// reference to its parent panel and (when present on disk)
    /// CKAssets for the picture, boy audio, and girl audio. Built-ins
    /// never sync; callers must filter before calling.
    func toCKRecord(parentPanelID: UUID,
                    order: Int,
                    assetURLs: (image: URL?, boy: URL?, girl: URL?),
                    in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.interaction, recordID: recordID)
        record["interactionID"] = id.uuidString as CKRecordValue

        let parentRecordID = CKRecord.ID(recordName: parentPanelID.uuidString, zoneID: zoneID)
        record["panelRef"] = CKRecord.Reference(recordID: parentRecordID, action: .deleteSelf)

        record["displayName"] = (name ?? "") as CKRecordValue
        record["order"]       = Int64(order) as CKRecordValue

        if let url = assetURLs.image, FileManager.default.fileExists(atPath: url.path) {
            record["imageAsset"] = CKAsset(fileURL: url)
        }
        if let url = assetURLs.boy, FileManager.default.fileExists(atPath: url.path) {
            record["audioBoyAsset"] = CKAsset(fileURL: url)
        }
        if let url = assetURLs.girl, FileManager.default.fileExists(atPath: url.path) {
            record["audioGirlAsset"] = CKAsset(fileURL: url)
        }
        return record
    }
}
