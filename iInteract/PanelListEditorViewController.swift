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
/// visibility of any panel (built-in or user), drag to reorder, delete or add
/// user panels, and set/clear the PIN that gates entry to this screen.
/// Built-ins cannot be deleted or have their content edited — only their
/// visibility and position.
final class PanelListEditorViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case panels, security
    }

    private let store: PanelStore
    private var panels: [Panel] = []

    private static let panelCell    = "PanelListEditorPanelCell"
    private static let securityCell = "PanelListEditorSecurityCell"

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.securityCell)
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh the Security section in case PIN state changed in PINSetup.
        tableView.reloadSections([Section.security.rawValue], with: .none)
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

    // MARK: - Sections / rows

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .panels:   return "Panels"
        case .security: return "Security"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .panels:
            return "Toggle to hide a panel from the main list. Drag to reorder. Swipe to delete (custom only)."
        case .security:
            return store.hasPIN
                ? "PIN protects entry to this editor. Syncs across your iCloud devices."
                : "Optional. Set a PIN to require entry before opening this editor."
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .panels:   return panels.count
        case .security: return store.hasPIN ? 2 : 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .panels:   return panelCell(at: indexPath)
        case .security: return securityCell(at: indexPath)
        }
    }

    private func panelCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.panelCell, for: indexPath)
        let panel = panels[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = panel.title
        content.secondaryText = panel.isBuiltIn ? "Built-in" : "Custom"
        cell.contentConfiguration = content
        cell.backgroundColor = panel.color.withAlphaComponent(0.18)

        // Table is always in editing mode here so reorder handles show, which
        // means accessoryView is replaced by editingAccessoryView. Set the
        // editing variant or the switch never appears (and never receives taps).
        let toggle = UISwitch()
        toggle.isOn = !store.layout().hiddenIDs.contains(panel.id)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(visibilityToggled(_:)), for: .valueChanged)
        cell.editingAccessoryView = toggle
        cell.accessoryView = nil
        return cell
    }

    private func securityCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.securityCell, for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .systemBackground
        var content = cell.defaultContentConfiguration()
        if indexPath.row == 0 {
            content.text = store.hasPIN ? "Change PIN" : "Set PIN"
            content.image = UIImage(systemName: "lock.fill")
        } else {
            content.text = "Clear PIN"
            content.image = UIImage(systemName: "lock.open")
            content.textProperties.color = .systemRed
            cell.accessoryType = .none
        }
        cell.contentConfiguration = content
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
        switch Section(rawValue: indexPath.section)! {
        case .panels:
            let panel = panels[indexPath.row]
            guard !panel.isBuiltIn else { return }
            let editor = PanelEditorViewController(panel: panel, store: store)
            editor.onSave = { [weak self] _ in self?.loadPanels() }
            navigationController?.pushViewController(editor, animated: true)
        case .security:
            if indexPath.row == 0 {
                let setup = PINSetupViewController(store: store)
                navigationController?.pushViewController(setup, animated: true)
            } else {
                confirmClearPIN()
            }
        }
    }

    private func confirmClearPIN() {
        let alert = UIAlertController(title: "Clear PIN?",
                                      message: "Anyone using this device will be able to open the editor without entering a PIN.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear PIN", style: .destructive) { [weak self] _ in
            self?.store.clearPIN()
            self?.tableView.reloadSections([Section.security.rawValue], with: .automatic)
        })
        present(alert, animated: true)
    }

    // MARK: - Reorder (panels section only)

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .panels
    }

    override func tableView(_ tableView: UITableView,
                            targetIndexPathForMoveFromRowAt source: IndexPath,
                            toProposedIndexPath proposed: IndexPath) -> IndexPath {
        // Don't allow drags out of the panels section.
        guard proposed.section == Section.panels.rawValue else { return source }
        return proposed
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let panel = panels.remove(at: source.row)
        panels.insert(panel, at: destination.row)
        try? store.setOrder(panels.map { $0.id })
        // Tags on the visibility switches are stale after a move; refresh them.
        for visible in tableView.indexPathsForVisibleRows ?? [] {
            guard visible.section == Section.panels.rawValue else { continue }
            if let cell = tableView.cellForRow(at: visible),
               let toggle = cell.accessoryView as? UISwitch {
                toggle.tag = visible.row
            }
        }
    }

    // MARK: - Delete (user panels only)

    override func tableView(_ tableView: UITableView,
                            editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard Section(rawValue: indexPath.section) == .panels else { return .none }
        return panels[indexPath.row].isBuiltIn ? .none : .delete
    }

    override func tableView(_ tableView: UITableView,
                            shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        guard Section(rawValue: indexPath.section) == .panels else { return false }
        return !panels[indexPath.row].isBuiltIn
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              Section(rawValue: indexPath.section) == .panels else { return }
        let panel = panels[indexPath.row]
        guard !panel.isBuiltIn else { return }
        try? store.deletePanel(id: panel.id)
        panels.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}
