//
//  ExtensionDelegate.swift
//  iInteractWatch Extension
//
//  Created by Jim Zucker on 12/4/15.
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. 
//

import WatchKit
import WatchConnectivity

@main
class ExtensionDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate {

    static let payloadKey = "builtInPanelOrder"
    static let storageKey = "watchBuiltInPanelOrder"
    static let didChangeNotification = Notification.Name("WatchPanelOrderDidChange")

    func applicationDidFinishLaunching() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // If the iPhone has already pushed a context before our delegate was
        // attached, applicationContext is non-empty — apply it now.
        if !session.receivedApplicationContext.isEmpty {
            apply(context: session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String : Any]) {
        apply(context: applicationContext)
    }

    private func apply(context: [String: Any]) {
        guard let titles = context[Self.payloadKey] as? [String] else { return }
        UserDefaults.standard.set(titles, forKey: Self.storageKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    func applicationDidBecomeActive() {}
    func applicationWillResignActive() {}
}
