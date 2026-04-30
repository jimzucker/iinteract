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

    /// Snapshot of the panel state at init time. Used to detect
    /// unsaved changes when the user taps Cancel.
    private let originalTitle: String
    private let originalColor: UIColor
    private let originalInteractionIDs: [UUID]

    private var saveButton: UIBarButtonItem!
    private weak var titleField: UITextField?
    private weak var titleFooterLabel: UILabel?
    private weak var interactionsFooterLabel: UILabel?
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
            self.originalTitle = panel.title
            self.originalColor = panel.color
            self.originalInteractionIDs = panel.interactions.map { $0.id }
        } else {
            self.workingPanel = Panel(id: UUID(),
                                      title: "",
                                      color: .systemBlue,
                                      interactions: [],
                                      isBuiltIn: false)
            self.isNewPanel = true
            self.originalTitle = ""
            self.originalColor = .systemBlue
            self.originalInteractionIDs = []
        }
        super.init(style: .insetGrouped)
    }

    /// True when the user has made any changes the Cancel/X button
    /// would discard. Used to gate the discard-confirmation alert.
    private var hasUnsavedChanges: Bool {
        let trimmedTitle = workingPanel.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle != originalTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
            return true
        }
        if !UIColorComponents.areEqual(workingPanel.color, originalColor) {
            return true
        }
        if workingPanel.interactions.map({ $0.id }) != originalInteractionIDs {
            return true
        }
        return false
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
        guard hasUnsavedChanges else {
            navigationController?.popViewController(animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Discard Changes?",
            message: "Your edits to this panel haven't been saved. Are you sure you want to discard them?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        do {
            try store.savePanel(workingPanel)
            onSave?(workingPanel)
            navigationController?.popViewController(animated: true)
        } catch PanelStore.StoreError.nameNotUnique {
            titleErrorMessage = "That name is already in use."
            titleFooterLabel?.text = titleErrorMessage
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
        // Update the footer label directly — reloading the section would
        // destroy the active text field and dismiss the keyboard.
        titleFooterLabel?.text = titleErrorMessage
        interactionsFooterLabel?.text = interactionsFooterText()
    }

    private func interactionsFooterText() -> String {
        workingPanel.interactions.count >= PanelStore.maxInteractionsPerUserPanel
            ? "You've reached the 6-item maximum."
            : "Up to 6 items per page."
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
        // Footers come from viewForFooterInSection so we can update them
        // without reloading the section (which would dismiss the keyboard).
        nil
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .title:
            let (view, label) = makeFooterLabelView(text: titleErrorMessage, color: .systemRed)
            self.titleFooterLabel = label
            return view
        case .color:
            return nil
        case .interactions:
            let (view, label) = makeFooterLabelView(text: interactionsFooterText(), color: .secondaryLabel)
            self.interactionsFooterLabel = label
            return view
        }
    }

    private func makeFooterLabelView(text: String?, color: UIColor) -> (UIView, UILabel) {
        let view = UIView()
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = color
        label.numberOfLines = 0
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
        return (view, label)
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
            if indexPath.row < workingPanel.interactions.count {
                pushInteractionEditor(.edit(workingPanel.interactions[indexPath.row]),
                                      replacingAt: indexPath.row)
            } else {
                pushInteractionEditor(.new, replacingAt: nil)
            }
        case .title:
            break
        }
    }

    private func pushInteractionEditor(_ intent: InteractionEditorViewController.Intent,
                                       replacingAt index: Int?) {
        let editor = InteractionEditorViewController(intent: intent, store: store)
        editor.onSave = { [weak self] interaction in
            guard let self = self else { return }
            if let index = index, index < self.workingPanel.interactions.count {
                self.workingPanel.interactions[index] = interaction
            } else {
                self.workingPanel.interactions.append(interaction)
            }
            // onSave may fire just as InteractionEditor pops back —
            // defer through safeReloadSections so we don't trigger
            // the off-screen-layout warning during the transition.
            self.safeReloadSections([Section.interactions.rawValue])
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func presentColorPicker() {
        let picker = UIColorPickerViewController()
        picker.selectedColor = workingPanel.color
        picker.supportsAlpha = false
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: UIColorPickerViewControllerDelegate

    func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                   didSelect color: UIColor,
                                   continuously: Bool) {
        // Update the model on every change. The visible swatch refresh
        // is deferred to `colorPickerViewControllerDidFinish` (after
        // dismiss) — reloading the table section while the picker is
        // still presented modally produces inconsistent results on
        // iOS 18+ (the section reload runs but the cell behind the
        // modal doesn't re-render visibly until the picker goes away).
        workingPanel.color = color
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        // Picker is about to dismiss — refresh the swatch + any
        // dependent affordances so the new color is visible the
        // moment the editor reappears.
        guard isViewLoaded else { return }
        tableView.reloadSections([Section.color.rawValue], with: .none)
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
        let target = workingPanel.interactions[indexPath.row]
        let label = (target.name?.isEmpty == false) ? "\"\(target.name!)\"" : "this interaction"

        // Reset the swipe-exposed row immediately so it doesn't stay
        // half-swiped while the confirm alert is up.
        tableView.reloadRows(at: [indexPath], with: .automatic)

        // Reversible (move to Trash for 30 days), so no PIN gate.
        let alert = UIAlertController(
            title: "Delete \(label)?",
            message: "Its picture and both voice recordings (sound) will move to Trash and be permanently removed after 30 days.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self,
                  let row = self.workingPanel.interactions.firstIndex(where: { $0.id == target.id })
            else { return }
            let removed = self.workingPanel.interactions.remove(at: row)
            try? self.store.trashInteraction(removed, fromPanelID: self.workingPanel.id)
            // Alert dismiss animation overlaps this handler — use the
            // safe variant so we don't reload mid-transition.
            self.safeReloadSections([Section.interactions.rawValue])
        })
        present(alert, animated: true)
    }
}
