//
//  PanelEditorViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

/// Edits a single user-authored panel: title, color, and the list of
/// interactions it shows. Used both to create new panels (init with nil) and
/// to edit existing ones. Built-ins are not editable here — `PanelListEditor`
/// only routes user panels into this screen.
final class PanelEditorViewController: UITableViewController,
                                       UIColorPickerViewControllerDelegate {

    // MARK: Sections / rows

    private enum Section: Int, CaseIterable {
        case title, color, interactions
    }

    private static let titleCell        = "title"
    private static let colorCell        = "color"
    private static let interactionCell  = "interaction"
    private static let addCell          = "add"

    // MARK: State

    private let store: PanelStore
    private var workingPanel: Panel
    private let isNewPanel: Bool

    private var saveButton: UIBarButtonItem!
    private weak var titleField: UITextField?
    private var titleErrorMessage: String?

    /// Called after a successful save so the presenting screen can refresh.
    var onSave: ((Panel) -> Void)?

    // MARK: Init

    init(panel: Panel? = nil, store: PanelStore = .shared) {
        self.store = store
        if let panel = panel, !panel.isBuiltIn {
            // Clone so cancel doesn't leak in-memory mutations to the caller.
            self.workingPanel = Panel(id: panel.id,
                                      title: panel.title,
                                      color: panel.color,
                                      interactions: panel.interactions,
                                      isBuiltIn: false)
            self.isNewPanel = false
        } else {
            self.workingPanel = Panel(id: UUID(),
                                      title: "",
                                      color: .systemBlue,
                                      interactions: [],
                                      isBuiltIn: false)
            self.isNewPanel = true
        }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("PanelEditorViewController is programmatic")
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNewPanel ? "New Panel" : "Edit Panel"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        saveButton = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem = saveButton

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.titleCell)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.colorCell)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.interactionCell)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.addCell)
        tableView.allowsSelectionDuringEditing = true
        tableView.isEditing = true

        revalidate()
    }

    // MARK: Actions

    @objc private func cancelTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        do {
            try store.savePanel(workingPanel)
            onSave?(workingPanel)
            navigationController?.popViewController(animated: true)
        } catch PanelStore.StoreError.nameNotUnique {
            titleErrorMessage = "That name is already in use."
            tableView.reloadSections([Section.title.rawValue], with: .none)
        } catch {
            presentError("Could not save: \(error)")
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Save Failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func titleChanged(_ field: UITextField) {
        workingPanel.title = field.text ?? ""
        // Clear any prior error as soon as the user changes the field; revalidate.
        titleErrorMessage = nil
        revalidate()
    }

    private func revalidate() {
        let trimmed = workingPanel.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameOK = !trimmed.isEmpty && store.isNameAvailable(trimmed, excluding: workingPanel.id)
        if !trimmed.isEmpty && !nameOK {
            titleErrorMessage = "That name is already in use."
        }
        saveButton.isEnabled = nameOK
        // Refresh the title section's footer label visibility.
        if isViewLoaded {
            tableView.reloadSections([Section.title.rawValue], with: .none)
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .title:        return "Title"
        case .color:        return "Color"
        case .interactions: return "Interactions"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .title:
            return titleErrorMessage
        case .color:
            return nil
        case .interactions:
            if workingPanel.interactions.count >= PanelStore.maxInteractionsPerUserPanel {
                return "You've reached the 6-item maximum."
            }
            return "Up to 6 items per page."
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .title:        return 1
        case .color:        return 1
        case .interactions:
            let canAdd = workingPanel.interactions.count < PanelStore.maxInteractionsPerUserPanel
            return workingPanel.interactions.count + (canAdd ? 1 : 0)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .title:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.titleCell, for: indexPath)
            // Build the text field once per cell creation.
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            let field = UITextField()
            field.placeholder = "Panel name"
            field.text = workingPanel.title
            field.autocorrectionType = .no
            field.returnKeyType = .done
            field.addTarget(self, action: #selector(titleChanged(_:)), for: .editingChanged)
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
            ])
            self.titleField = field
            return cell

        case .color:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.colorCell, for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Color"
            cell.contentConfiguration = content
            // Color swatch on the right.
            let swatch = UIView()
            swatch.backgroundColor = workingPanel.color
            swatch.layer.cornerRadius = 14
            swatch.layer.borderColor = UIColor.systemGray4.cgColor
            swatch.layer.borderWidth = 1
            swatch.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
            cell.accessoryView = swatch
            return cell

        case .interactions:
            if indexPath.row < workingPanel.interactions.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: Self.interactionCell, for: indexPath)
                let interaction = workingPanel.interactions[indexPath.row]
                var content = cell.defaultContentConfiguration()
                content.text = interaction.name
                if let img = interaction.picture {
                    content.image = img
                    content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
                    content.imageProperties.cornerRadius = 6
                }
                cell.contentConfiguration = content
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: Self.addCell, for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "Add Interaction"
                content.image = UIImage(systemName: "plus.circle.fill")
                content.imageProperties.tintColor = .systemBlue
                cell.contentConfiguration = content
                return cell
            }
        }
    }

    // MARK: - Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .color:
            presentColorPicker()
        case .interactions:
            if indexPath.row >= workingPanel.interactions.count {
                presentInteractionEditorPlaceholder()
            }
        case .title:
            break
        }
    }

    private func presentColorPicker() {
        let picker = UIColorPickerViewController()
        picker.selectedColor = workingPanel.color
        picker.supportsAlpha = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentInteractionEditorPlaceholder() {
        let alert = UIAlertController(
            title: "Add Interaction",
            message: "The interaction editor (picture + audio) arrives in the next v2.0 step.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: UIColorPickerViewControllerDelegate

    func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                   didSelect color: UIColor,
                                   continuously: Bool) {
        workingPanel.color = color
        if isViewLoaded {
            tableView.reloadSections([Section.color.rawValue], with: .none)
        }
    }

    // MARK: - Editing (reorder + delete) only on interaction rows

    override func tableView(_ tableView: UITableView,
                            editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard Section(rawValue: indexPath.section) == .interactions else { return .none }
        return indexPath.row < workingPanel.interactions.count ? .delete : .none
    }

    override func tableView(_ tableView: UITableView,
                            shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .interactions
            && indexPath.row < workingPanel.interactions.count
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .interactions
            && indexPath.row < workingPanel.interactions.count
    }

    override func tableView(_ tableView: UITableView,
                            targetIndexPathForMoveFromRowAt source: IndexPath,
                            toProposedIndexPath proposed: IndexPath) -> IndexPath {
        // Don't allow reorder out of the interactions section, and don't drag
        // past the trailing "+ Add" row.
        guard proposed.section == Section.interactions.rawValue else { return source }
        let lastInteractionIndex = workingPanel.interactions.count - 1
        return IndexPath(row: min(proposed.row, lastInteractionIndex),
                         section: Section.interactions.rawValue)
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let moved = workingPanel.interactions.remove(at: source.row)
        workingPanel.interactions.insert(moved, at: destination.row)
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              Section(rawValue: indexPath.section) == .interactions,
              indexPath.row < workingPanel.interactions.count else { return }
        let removed = workingPanel.interactions.remove(at: indexPath.row)
        // Best-effort cleanup of the user's recorded blobs.
        store.deleteInteractionAssets(id: removed.id)
        tableView.reloadSections([Section.interactions.rawValue], with: .automatic)
    }
}
