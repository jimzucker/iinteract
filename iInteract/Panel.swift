//
//  Panel.swift
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
import Foundation

class Panel: Codable {
    // MARK: Properties

    let id: UUID
    var title: String
    var color: UIColor
    var interactions: [Interaction]
    let isBuiltIn: Bool

    // MARK: Initialization

    init(id: UUID = UUID(),
         title: String,
         color: UIColor,
         interactions: [Interaction],
         isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.color = color
        self.interactions = interactions
        self.isBuiltIn = isBuiltIn
    }

    convenience init(dataDictionary: Dictionary<String, NSObject>) {
        let title = dataDictionary["title"] as! String

        let RGB   = dataDictionary["color"] as! [String: NSNumber]
        let red   = CGFloat(RGB["red"]!.floatValue)   / 255.0
        let green = CGFloat(RGB["green"]!.floatValue) / 255.0
        let blue  = CGFloat(RGB["blue"]!.floatValue)  / 255.0
        let color = UIColor(red: red, green: green, blue: blue, alpha: 1.0)

        let names = dataDictionary["interactions"] as! [String]
        let interactions = names.map { Interaction(interactionName: $0) }

        self.init(id: Interaction.stableID(for: title),
                  title: title,
                  color: color,
                  interactions: interactions,
                  isBuiltIn: true)
    }

    // MARK: Loading

    /// v1.x-compatible plist loader. Public so existing tests keep working.
    /// Configuration-mode-aware loading lives in `PanelLoader.swift` (iOS-only).
    class func readFromPlist() -> [Panel] {
        guard let dataPath = Bundle.main.path(forResource: "panels", ofType: "plist"),
              let plist = NSArray(contentsOfFile: dataPath) as? [Dictionary<String, NSObject>] else {
            return []
        }
        return plist.map { Panel(dataDictionary: $0) }
    }

    // MARK: Codable
    // User-authored panels round-trip through JSON. Color is encoded as RGBA
    // components since UIColor isn't directly Codable.

    private enum CodingKeys: String, CodingKey {
        case id, title, color, interactions, isBuiltIn
    }

    private struct ColorRGBA: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        let rgba = try c.decode(ColorRGBA.self, forKey: .color)
        // Clamp to [0,1] on decode too — older saves may have stored
        // out-of-range extended-sRGB values from dynamic system colors.
        self.color = UIColor(red:   CGFloat(min(max(rgba.red,   0), 1)),
                             green: CGFloat(min(max(rgba.green, 0), 1)),
                             blue:  CGFloat(min(max(rgba.blue,  0), 1)),
                             alpha: CGFloat(min(max(rgba.alpha, 0), 1)))
        self.interactions = try c.decode([Interaction].self, forKey: .interactions)
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // Resolve dynamic colors against the current trait collection
        // before extracting RGBA — `.systemBlue` etc. otherwise return
        // extended-sRGB values that can fall outside [0,1] and trip
        // "UIColor created with component values far outside the
        // expected range" on round-trip. UITraitCollection is iOS-only
        // (panel.color round-trip on watchOS uses plain getRed plus
        // the clamp below).
        #if !os(watchOS)
        color.resolvedColor(with: UITraitCollection.current)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        try c.encode(ColorRGBA(red:   Double(min(max(r, 0), 1)),
                               green: Double(min(max(g, 0), 1)),
                               blue:  Double(min(max(b, 0), 1)),
                               alpha: Double(min(max(a, 0), 1))),
                     forKey: .color)
        try c.encode(interactions, forKey: .interactions)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
    }
}
