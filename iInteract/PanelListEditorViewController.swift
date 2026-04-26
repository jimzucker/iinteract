//
//  PanelListEditorViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

/// In-app editor for the master panel list. Shown in Custom mode when the user
/// taps the + bar button on FeelingTableViewController. Lets the user toggle
/// visibility of any panel (built-in or user), drag to reorder, and delete or
/// add user panels. Built-ins cannot be deleted or have their content edited —
/// only their visibility and position.
final class PanelListEditorViewController: UITableViewController {

    private let store: PanelStore
    private var panels: [Panel] = []

    private static let cellIdentifier = "PanelListEditorCell"

    init(store: PanelStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        self.store = .shared
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Panels"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPanelTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        loadPanels()
    }

    private func loadPanels() {
        let userPanels = store.userPanels()
        userPanels.forEach { store.hydrate($0) }
        panels = store.applyOrder(to: Panel.readFromPlist() + userPanels)
        tableView.reloadData()
    }

    @objc private func addPanelTapped() {
        // The new-panel editor lands in step 6. Stub for now.
        let alert = UIAlertController(
            title: "New Panel",
            message: "The new-panel editor arrives in the next v2.0 step.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        panels.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let panel = panels[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = panel.title
        content.secondaryText = panel.isBuiltIn ? "Built-in" : "Custom"
        cell.contentConfiguration = content
        cell.backgroundColor = panel.color.withAlphaComponent(0.18)

        let toggle = UISwitch()
        toggle.isOn = !store.layout().hiddenIDs.contains(panel.id)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(visibilityToggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle

        return cell
    }

    @objc private func visibilityToggled(_ sender: UISwitch) {
        guard sender.tag < panels.count else { return }
        let panel = panels[sender.tag]
        try? store.setHidden(!sender.isOn, for: panel.id)
    }

    // MARK: - Reorder

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let panel = panels.remove(at: source.row)
        panels.insert(panel, at: destination.row)
        try? store.setOrder(panels.map { $0.id })
        // Tags on the visibility switches are now stale; refresh visible cells.
        for case let visible as IndexPath in tableView.indexPathsForVisibleRows ?? [] {
            if let cell = tableView.cellForRow(at: visible),
               let toggle = cell.accessoryView as? UISwitch {
                toggle.tag = visible.row
            }
        }
    }

    // MARK: - Delete (user panels only)

    override func tableView(_ tableView: UITableView,
                            editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        panels[indexPath.row].isBuiltIn ? .none : .delete
    }

    override func tableView(_ tableView: UITableView,
                            shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        !panels[indexPath.row].isBuiltIn
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let panel = panels[indexPath.row]
        guard !panel.isBuiltIn else { return }
        try? store.deletePanel(id: panel.id)
        panels.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}
