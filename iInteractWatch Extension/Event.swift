//
//  Event.swift
//  iInteractWatch Extension
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation

struct Event {
    let title: String
    let time: String
    let imageName: String?

    init?(from dictionary: [String: String]) {
        guard let title = dictionary["eventTitle"],
              let time = dictionary["eventTime"] else {
            return nil
        }
        self.title = title
        self.time = time
        self.imageName = dictionary["eventImageName"]
    }

    static func loadAll() -> [Event] {
        guard let path = Bundle.main.path(forResource: "events", ofType: "plist"),
              let entries = NSArray(contentsOfFile: path) as? [[String: String]] else {
            return []
        }
        return entries.compactMap(Event.init(from:))
    }
}
