//
//  WatchSync.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation
import WatchConnectivity

/// One-way push from iPhone to the watch of the visible **built-in** panel
/// titles in display order. Custom user panels stay iPhone-only in v2.0
/// because their pictures and audio aren't part of the watch bundle.
final class WatchSync: NSObject, WCSessionDelegate {

    static let shared = WatchSync()
    static let payloadKey = "builtInPanelOrder"

    /// Activates the WCSession (idempotent). Call from app launch.
    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Pushes the current visible built-in panel titles (in their saved order
    /// from PanelStore.layout()) to the watch via updateApplicationContext —
    /// only the latest is delivered, perfect for "current state."
    func pushVisiblePanels() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let mode = ConfigurationMode.current()
        // Apply the same layout (visibility + order) that the iPhone shows,
        // restricted to built-ins.
        let titles = Panel.load(mode: mode, store: .shared)
            .filter { $0.isBuiltIn }
            .map { $0.title }

        do {
            try session.updateApplicationContext([Self.payloadKey: titles])
        } catch {
            print("WatchSync: updateApplicationContext failed: \(error)")
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if activationState == .activated {
            pushVisiblePanels()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // iOS expects us to reactivate so future pairings still get our payloads.
        session.activate()
    }
}
