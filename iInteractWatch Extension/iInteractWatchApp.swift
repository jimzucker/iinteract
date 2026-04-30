//
//  iInteractWatchApp.swift
//  iInteractWatch Extension
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Modern watchOS app entry point — replaces the storyboard +
/// `WKApplicationDelegate` pair the v3.0 watch app shipped with.
/// `WKApplicationDelegateAdaptor` keeps `ExtensionDelegate` alive so
/// the existing WatchConnectivity plumbing (which receives panel-order
/// updates from the iPhone) continues to function unchanged.
@main
struct iInteractWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            PanelListView()
        }
    }
}
