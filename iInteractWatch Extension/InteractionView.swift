//
//  InteractionView.swift
//  iInteractWatch Extension
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Final screen — full-bleed picture for the chosen interaction,
/// tinted to match the parent panel's color. Replaces the storyboard
/// `InteractionInterfaceController`. Tap anywhere to dismiss back to
/// the panel detail.
///
/// Audio playback was commented out in the original (Apple Watch
/// without bluetooth headset doesn't pipe app audio out), and we
/// preserve that — the watch is a glanceable child-friendly visual
/// supplement, not a speaker.
struct InteractionView: View {
    let interaction: Interaction
    let backgroundColor: UIColor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(backgroundColor).ignoresSafeArea()
            if let pic = interaction.picture {
                Image(uiImage: pic)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .navigationBarTitleDisplayMode(.inline)
    }
}
