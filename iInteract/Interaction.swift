//
//  Interaction.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//


import UIKit
import CryptoKit

class Interaction: Codable {

    // MARK: Properties
    let id: UUID
    var name: String?
    var picture: UIImage?
    var boySound: URL?
    var girlSound: URL?
    let isBuiltIn: Bool

    // MARK: Init — built-in (loads from Bundle, stable id from name)
    init(interactionName: String) {
        self.id = Interaction.stableID(for: interactionName)
        self.name = interactionName
        self.isBuiltIn = true

        self.picture = UIImage(named: interactionName)

        if let path = Bundle.main.path(forResource: "boy_" + interactionName, ofType: "mp3", inDirectory: "sounds") {
            self.boySound = URL(fileURLWithPath: path)
        }
        if let path = Bundle.main.path(forResource: "girl_" + interactionName, ofType: "mp3", inDirectory: "sounds") {
            self.girlSound = URL(fileURLWithPath: path)
        }
    }

    // Test/legacy convenience init
    init(interactionName: String, picture: UIImage, boySound: URL?, girlSound: URL?) {
        self.id = UUID()
        self.name = interactionName
        self.picture = picture
        self.boySound = boySound
        self.girlSound = girlSound
        self.isBuiltIn = false
    }

    // MARK: Init — user-authored (assets resolved from id by PanelStore)
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.isBuiltIn = false
    }

    // MARK: Codable
    // Only id, name, isBuiltIn round-trip through JSON. Picture and audio are
    // resolved from the bundle (built-ins) or Application Support (user
    // interactions) by PanelStore.hydrate(_:) after decoding.
    private enum CodingKeys: String, CodingKey {
        case id, name, isBuiltIn
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
    }

    // MARK: Stable IDs for built-ins
    // SHA-256 of the bundled name, formatted as a v5-shaped UUID, so the same
    // built-in always has the same id across launches and devices.
    static func stableID(for string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
