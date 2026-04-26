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

/// In-app editor for the master panel list — pushed by the gear icon (after
/// the PIN gate when set). Houses the panel list and the Trash entry.
/// PIN management and Clear All My Data live in iOS Settings → iInteract;
/// voice and mode also live there.
final class PanelListEditorViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case panels, trash
    }

    private let store: PanelStore
    private var panels: [Panel] = []
    private var trashCount: Int = 0

    private static let panelCell = "PanelListEditorPanelCell"
    private static let trashCell = "PanelListEditorTrashCell"

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.trashCell)
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Trash count may have changed if the user just visited the Trash
        // screen and restored / purged something.
        trashCount = store.trashedItems().count
        tableView.reloadSections([Section.trash.rawValue], with: .none)
    }

    @objc private func panelStoreChangedRemotely() {
        loadPanels()
    }

    private func loadPanels() {
        let userPanels = store.userPanels()
        userPanels.forEach { store.hydrate($0) }
        panels = store.applyOrder(to: Panel.readFromPlist() + userPanels)
        trashCount = store.trashedItems().count
        tableView.reloadData()
    }

    @objc private func addPanelTapped() {
        let editor = PanelEditorViewController(panel: nil, store: store)
        editor.onSave = { [weak self] _ in self?.loadPanels() }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - Sections

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .panels: return "Panels"
        case .trash:  return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .panels:
            return "Toggle to hide a panel from the main list. Drag to reorder. Swipe to delete custom panels. PIN and Clear All My Data live in iOS Settings → iInteract."
        case .trash:
            return "Deleted panels and interactions stay here for 30 days before they're permanently removed."
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .panels: return panels.count
        case .trash:  return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .panels: return panelCell(at: indexPath)
        case .trash:  return trashRowCell(at: indexPath)
        }
    }

    private func panelCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.panelCell, for: indexPath)
        cell.editingAccessoryView = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.imageView?.image = nil
        cell.textLabel?.textColor = .label

        let panel = panels[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = panel.title
        content.secondaryText = panel.isBuiltIn ? "Built-in" : "Custom"
        cell.contentConfiguration = content
        cell.backgroundColor = panel.color.withAlphaComponent(0.18)

        // Table is in editing mode, so accessoryView is hidden in favor of
        // editingAccessoryView — set the editing variant or the switch
        // never appears or accepts taps.
        let toggle = UISwitch()
        toggle.isOn = !store.layout().hiddenIDs.contains(panel.id)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(visibilityToggled(_:)), for: .valueChanged)
        cell.editingAccessoryView = toggle
        return cell
    }

    private func trashRowCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.trashCell, for: indexPath)
        cell.editingAccessoryView = nil
        cell.accessoryView = nil
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .systemBackground
        cell.imageView?.image = nil
        cell.textLabel?.textColor = .label
        var content = cell.defaultContentConfiguration()
        content.text = trashCount > 0 ? "Trash (\(trashCount))" : "Trash"
        content.image = UIImage(systemName: "trash.circle")
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
        case .trash:
            navigationController?.pushViewController(TrashViewController(store: store), animated: true)
        }
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
        for visible in tableView.indexPathsForVisibleRows ?? [] {
            guard visible.section == Section.panels.rawValue else { continue }
            if let cell = tableView.cellForRow(at: visible),
               let toggle = cell.editingAccessoryView as? UISwitch {
                toggle.tag = visible.row
            }
        }
    }

    // MARK: - Delete (user panels only, with confirm; trash-not-purge)

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

        // Reset the swipe-exposed row immediately. The PIN gate may take
        // multiple taps to clear, and we don't want to leave the row stuck
        // half-swiped during that time.
        tableView.reloadRows(at: [indexPath], with: .automatic)

        // PIN gate first (when set) — destructive action.
        gatePINIfSet(store: store) { [weak self] in
            guard let self = self else { return }
            let alert = UIAlertController(
                title: "Delete \"\(panel.title)\"?",
                message: "The panel, every interaction on it, and all of its pictures and voice recordings (sound) will move to Trash and be permanently removed after 30 days.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                guard let self = self,
                      let row = self.panels.firstIndex(where: { $0.id == panel.id }) else { return }
                do {
                    try self.store.trashPanel(panel)
                    self.panels.remove(at: row)
                    self.tableView.deleteRows(at: [IndexPath(row: row, section: Section.panels.rawValue)],
                                              with: .automatic)
                    self.trashCount = self.store.trashedItems().count
                    self.tableView.reloadSections([Section.trash.rawValue], with: .none)
                } catch {
                    let a = UIAlertController(title: "Couldn't Delete", message: "\(error)",
                                              preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(a, animated: true)
                }
            })
            self.present(alert, animated: true)
        }
    }
}
