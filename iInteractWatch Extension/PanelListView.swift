//
//  PanelListView.swift
//  iInteractWatch Extension
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Root list of panels on the watch. Reads the bundled built-ins,
/// then applies the iPhone's most recent visibility/order push (if
/// any) — same logic the original `InterfaceController` had, just
/// rendered with SwiftUI instead of `WKInterfaceTable`.
struct PanelListView: View {
    @State private var panels: [Panel] = []

    var body: some View {
        NavigationStack {
            List(panels, id: \.id) { panel in
                NavigationLink(destination: PanelDetailView(panel: panel)) {
                    PanelRowView(panel: panel)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .listStyle(.carousel)
            .navigationTitle("iInteract")
        }
        .onAppear(perform: reloadPanels)
        .onReceive(NotificationCenter.default.publisher(
            for: ExtensionDelegate.didChangeNotification)) { _ in
                reloadPanels()
            }
    }

    private func reloadPanels() {
        panels = Self.computePanels(
            bundled: Panel.readFromPlist(),
            iPhoneTitles: UserDefaults.standard.array(
                forKey: ExtensionDelegate.storageKey) as? [String])
    }

    /// Pure function for testability: given the bundled built-ins and
    /// the iPhone's most recent visibility/order push (or nil if the
    /// iPhone hasn't synced yet), return the ordered list to display.
    /// Extracted so the iPhone-driven ordering logic can be unit-tested
    /// without instantiating the SwiftUI view or UserDefaults.
    static func computePanels(bundled: [Panel],
                              iPhoneTitles: [String]?) -> [Panel] {
        guard let titles = iPhoneTitles else {
            return bundled
        }
        let byTitle = Dictionary(uniqueKeysWithValues: bundled.map { ($0.title, $0) })
        return titles.compactMap { byTitle[$0] }
    }
}

/// Single row in the panel list. Big, tappable, color-tinted to match
/// the iPhone-side panel color so a child can tell at a glance which
/// panel is which.
struct PanelRowView: View {
    let panel: Panel

    var body: some View {
        Text(panel.title)
            .font(.headline)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(panel.color))
            .cornerRadius(8)
    }
}
