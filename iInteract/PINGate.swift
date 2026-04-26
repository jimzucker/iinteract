//
//  PINGate.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

extension UIViewController {
    /// Runs `action` immediately when no PIN is set, or after the user
    /// successfully unlocks the PIN gate when one is set. Cancel does
    /// nothing. Used to wrap destructive admin actions (delete panel,
    /// delete interaction, empty trash, clear all data) so they can't
    /// be triggered accidentally or by an unattended child.
    func gatePINIfSet(store: PanelStore = .shared,
                      _ action: @escaping () -> Void) {
        guard store.hasPIN else { action(); return }
        let gate = PINGateViewController(store: store)
        let nav = UINavigationController(rootViewController: gate)
        nav.modalPresentationStyle = .fullScreen
        gate.onUnlock = { [weak nav] in
            nav?.dismiss(animated: true) { action() }
        }
        gate.onCancel = { [weak nav] in nav?.dismiss(animated: true) }
        present(nav, animated: true)
    }
}
