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

/// In-app editor for the master panel list. Reached from Settings → Edit
/// Panels in Custom mode. Lets the user toggle visibility of any panel
/// (built-in or user), drag to reorder, delete user panels (with confirm),
/// and add new user panels via the + button.
///
/// PIN management used to live in a Security section here; in the v3.0 UX
/// pass it moved to SettingsViewController so all admin lives in one place.
final class PanelListEditorViewController: UITableViewController {

    private let store: PanelStore
    private var panels: [Panel] = []

    private static let panelCell = "PanelListEditorPanelCell"

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.panelCell)
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelStoreChangedRemotely),
            name: PanelStore.didChangeNotification,
            object: nil
        )
        loadPanels()
    }

    @objc private func panelStoreChangedRemotely() {
        loadPanels()
    }

    private func loadPanels() {
        let userPanels = store.userPanels()
        userPanels.forEach { store.hydrate($0) }
        panels = store.applyOrder(to: Panel.readFromPlist() + userPanels)
        tableView.reloadData()
    }

    @objc private func addPanelTapped() {
        let editor = PanelEditorViewController(panel: nil, store: store)
        editor.onSave = { [weak self] _ in self?.loadPanels() }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        panels.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Toggle to hide a panel from the main list. Drag to reorder. Swipe to delete (custom only)."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.panelCell, for: indexPath)
        let panel = panels[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = panel.title
        content.secondaryText = panel.isBuiltIn ? "Built-in" : "Custom"
        cell.contentConfiguration = content
        cell.backgroundColor = panel.color.withAlphaComponent(0.18)

        // Table is always in editing mode here (so reorder handles show), so
        // accessoryView is replaced by editingAccessoryView at runtime — set
        // the editing variant or the switch never appears or accepts taps.
        let toggle = UISwitch()
        toggle.isOn = !store.layout().hiddenIDs.contains(panel.id)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(visibilityToggled(_:)), for: .valueChanged)
        cell.editingAccessoryView = toggle
        cell.accessoryView = nil
        return cell
    }

    @objc private func visibilityToggled(_ sender: UISwitch) {
        guard sender.tag < panels.count else { return }
        let panel = panels[sender.tag]
        try? store.setHidden(!sender.isOn, for: panel.id)
    }

    // MARK: - Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let panel = panels[indexPath.row]
        guard !panel.isBuiltIn else { return }
        let editor = PanelEditorViewController(panel: panel, store: store)
        editor.onSave = { [weak self] _ in self?.loadPanels() }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - Reorder

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let panel = panels.remove(at: source.row)
        panels.insert(panel, at: destination.row)
        try? store.setOrder(panels.map { $0.id })
        // Tags on the visibility switches are stale after a move; refresh them.
        for visible in tableView.indexPathsForVisibleRows ?? [] {
            if let cell = tableView.cellForRow(at: visible),
               let toggle = cell.editingAccessoryView as? UISwitch {
                toggle.tag = visible.row
            }
        }
    }

    // MARK: - Delete (user panels only, with confirmation)

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

        let alert = UIAlertController(
            title: "Delete \"\(panel.title)\"?",
            message: "The panel and any pictures or recordings you saved on its interactions will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            // Re-show the row (swipe-to-delete left it in the "exposed" state).
            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            for interaction in panel.interactions where !interaction.isBuiltIn {
                self.store.deleteInteractionAssets(id: interaction.id)
            }
            try? self.store.deletePanel(id: panel.id)
            self.panels.remove(at: indexPath.row)
            self.tableView.deleteRows(at: [indexPath], with: .automatic)
        })
        present(alert, animated: true)
    }
}
