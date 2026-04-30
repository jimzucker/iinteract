//
//  PanelDetailView.swift
//  iInteractWatch Extension
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Detail screen for a single panel — replaces the storyboard-based
/// `PanelController`. Shows up to 4 interaction tiles. Each tile is
/// a large tappable image; tapping pushes `InteractionView`.
struct PanelDetailView: View {
    let panel: Panel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(panel.interactions, id: \.id) { interaction in
                    NavigationLink(destination: InteractionView(interaction: interaction,
                                                                 backgroundColor: panel.color)) {
                        interactionTile(interaction)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(panel.title)
    }

    @ViewBuilder
    private func interactionTile(_ interaction: Interaction) -> some View {
        if let pic = interaction.picture {
            Image(uiImage: pic)
                .resizable()
                .scaledToFit()
                .background(Color(panel.color))
                .cornerRadius(6)
        } else {
            // Bundled built-ins ship images via Asset Catalog by name;
            // if the lookup didn't return a UIImage (rare on the watch
            // bundle), fall back to a colored placeholder so the cell
            // still has a tap target.
            Color(panel.color)
                .frame(height: 80)
                .cornerRadius(6)
        }
    }
}
