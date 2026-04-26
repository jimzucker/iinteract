//
//  TrashViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

/// Lists everything currently in the 30-day trash. Tap a row → action sheet
/// with Restore / Delete Forever / Cancel. Restore is smart:
/// * For panels: tries the original title; on collision, prompts for rename.
/// * For interactions: tries the original parent panel; if the parent is
///   itself in the trash, prompts the user to restore the parent first; if
///   the parent has been permanently deleted, offers a picker of available
///   panels (with room) to restore into.
final class TrashViewController: UITableViewController {

    private let store: PanelStore
    private var items: [PanelStore.TrashedItem] = []

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
        title = "Trash"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Empty",
            style: .plain,
            target: self,
            action: #selector(confirmEmpty)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        items = store.trashedItems()
        navigationItem.rightBarButtonItem?.isEnabled = !items.isEmpty
        tableView.reloadData()
    }

    private func displayName(for item: PanelStore.TrashedItem) -> String {
        switch item.kind {
        case .panel:
            if let panel = try? JSONDecoder().decode(Panel.self, from: item.snapshot) {
                return panel.title
            }
            return "Panel"
        case .interaction:
            if let interaction = try? JSONDecoder().decode(Interaction.self, from: item.snapshot) {
                return interaction.name ?? "Interaction"
            }
            return "Interaction"
        }
    }

    // MARK: Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.isEmpty ? 1 : items.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        items.isEmpty
            ? nil
            : "Tap an item to restore or delete it. Items are permanently removed after 30 days. Restoring a panel also brings back all of its interactions, pictures, and recordings."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.imageView?.image = nil
        cell.accessoryType = .none

        if items.isEmpty {
            var content = cell.defaultContentConfiguration()
            content.text = "Trash is empty."
            content.textProperties.color = .secondaryLabel
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        }

        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = displayName(for: item)
        let days = store.daysRemainingInTrash(item)
        let kind = item.kind == .panel ? "Panel" : "Interaction"
        content.secondaryText = "\(kind) · \(days) day\(days == 1 ? "" : "s") left"
        content.image = UIImage(systemName: item.kind == .panel ? "rectangle.stack" : "photo")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    // MARK: Selection — tap shows the action sheet

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !items.isEmpty else { return }
        let item = items[indexPath.row]
        showActionSheet(for: item, sourceCell: tableView.cellForRow(at: indexPath))
    }

    private func showActionSheet(for item: PanelStore.TrashedItem, sourceCell: UITableViewCell?) {
        let sheet = UIAlertController(
            title: displayName(for: item),
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
            self?.attemptRestore(item)
        })
        sheet.addAction(UIAlertAction(title: "Delete Forever", style: .destructive) { [weak self] _ in
            self?.confirmPurge(item)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController, let cell = sourceCell {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    // MARK: Swipe — same actions, faster path

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
                            -> UISwipeActionsConfiguration? {
        guard !items.isEmpty else { return nil }
        let item = items[indexPath.row]

        let purge = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirmPurge(item) { done($0) }
        }
        purge.image = UIImage(systemName: "trash")

        let restore = UIContextualAction(style: .normal, title: "Restore") { [weak self] _, _, done in
            self?.attemptRestore(item) { done($0) }
        }
        restore.backgroundColor = .systemBlue
        restore.image = UIImage(systemName: "arrow.uturn.backward")

        return UISwipeActionsConfiguration(actions: [restore, purge])
    }

    // MARK: - Restore flow

    private func attemptRestore(_ item: PanelStore.TrashedItem,
                                done: ((Bool) -> Void)? = nil) {
        switch item.kind {
        case .panel:
            do {
                _ = try store.restorePanel(trashID: item.trashID)
                reload(); done?(true)
            } catch PanelStore.StoreError.nameNotUnique {
                promptRenameOnRestore(item, done: done)
            } catch {
                presentError("Couldn't restore: \(error)"); done?(false)
            }
        case .interaction:
            // 1) Original parent still active and has room → restore.
            if store.canRestoreInteractionToOriginalParent(trashID: item.trashID) {
                do {
                    _ = try store.restoreInteraction(trashID: item.trashID)
                    reload(); done?(true)
                } catch {
                    presentError("Couldn't restore: \(error)"); done?(false)
                }
                return
            }
            // 2) Parent is in the trash → ask to restore parent first.
            if let parentTrashID = store.parentPanelTrashID(forInteractionTrashID: item.trashID),
               let parentItem = items.first(where: { $0.trashID == parentTrashID }) {
                offerRestoreParentFirst(interaction: item, parent: parentItem, done: done)
                return
            }
            // 3) Parent gone or full → picker of active panels with room.
            offerAlternateDestination(for: item, reason: .parentGone, done: done)
        }
    }

    private func promptRenameOnRestore(_ item: PanelStore.TrashedItem,
                                       done: ((Bool) -> Void)? = nil) {
        let alert = UIAlertController(
            title: "Name Already in Use",
            message: "Another panel has the same title. Pick a new name to restore.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            if let p = try? JSONDecoder().decode(Panel.self, from: item.snapshot) {
                tf.text = p.title + " (restored)"
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done?(false) })
        alert.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self, weak alert] _ in
            let newTitle = alert?.textFields?.first?.text ?? ""
            do {
                _ = try self?.store.restorePanel(trashID: item.trashID, newTitle: newTitle)
                self?.reload(); done?(true)
            } catch {
                self?.presentError("Couldn't restore: \(error)"); done?(false)
            }
        })
        present(alert, animated: true)
    }

    private func offerRestoreParentFirst(interaction: PanelStore.TrashedItem,
                                         parent: PanelStore.TrashedItem,
                                         done: ((Bool) -> Void)? = nil) {
        let parentName = displayName(for: parent)
        let alert = UIAlertController(
            title: "Restore Panel First?",
            message: "The panel \"\(parentName)\" this interaction belongs to is also in Trash. We'll restore the panel and then put this interaction back on it — both in one step.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done?(false) })
        alert.addAction(UIAlertAction(title: "Restore Panel & Interaction", style: .default) { [weak self] _ in
            self?.restorePanelThenInteraction(parent: parent, interaction: interaction, done: done)
        })
        alert.addAction(UIAlertAction(title: "Restore to Different Panel…", style: .default) { [weak self] _ in
            self?.offerAlternateDestination(for: interaction, reason: .parentInTrash, done: done)
        })
        present(alert, animated: true)
    }

    private func restorePanelThenInteraction(parent: PanelStore.TrashedItem,
                                             interaction: PanelStore.TrashedItem,
                                             done: ((Bool) -> Void)?) {
        do {
            _ = try store.restorePanel(trashID: parent.trashID)
        } catch PanelStore.StoreError.nameNotUnique {
            promptRenameThenRestoreInteraction(parent: parent, interaction: interaction, done: done)
            return
        } catch {
            presentError("Couldn't restore panel: \(error)")
            reload(); done?(false); return
        }
        restoreInteractionOntoJustRestoredParent(interaction: interaction, done: done)
    }

    private func promptRenameThenRestoreInteraction(parent: PanelStore.TrashedItem,
                                                    interaction: PanelStore.TrashedItem,
                                                    done: ((Bool) -> Void)?) {
        let alert = UIAlertController(
            title: "Name Already in Use",
            message: "Another panel has the same title. Pick a new name to restore.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            if let p = try? JSONDecoder().decode(Panel.self, from: parent.snapshot) {
                tf.text = p.title + " (restored)"
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done?(false) })
        alert.addAction(UIAlertAction(title: "Restore Both", style: .default) { [weak self, weak alert] _ in
            let newTitle = alert?.textFields?.first?.text ?? ""
            do {
                _ = try self?.store.restorePanel(trashID: parent.trashID, newTitle: newTitle)
                self?.restoreInteractionOntoJustRestoredParent(interaction: interaction, done: done)
            } catch {
                self?.presentError("Couldn't restore panel: \(error)")
                self?.reload(); done?(false)
            }
        })
        present(alert, animated: true)
    }

    private func restoreInteractionOntoJustRestoredParent(interaction: PanelStore.TrashedItem,
                                                          done: ((Bool) -> Void)?) {
        do {
            _ = try store.restoreInteraction(trashID: interaction.trashID)
            reload(); done?(true)
        } catch PanelStore.StoreError.capacityExceeded {
            presentError("The panel was restored, but it already has 6 interactions. Make room and tap the interaction again to restore it.")
            reload(); done?(false)
        } catch {
            presentError("The panel was restored, but the interaction couldn't be: \(error). Tap it again to retry.")
            reload(); done?(false)
        }
    }

    private enum AlternateReason {
        case parentGone, parentInTrash, parentFull
        var blurb: String {
            switch self {
            case .parentGone:    return "The original panel has been deleted."
            case .parentInTrash: return "The original panel is in Trash."
            case .parentFull:    return "The original panel already has 6 interactions."
            }
        }
    }

    private func offerAlternateDestination(for item: PanelStore.TrashedItem,
                                           reason: AlternateReason,
                                           done: ((Bool) -> Void)? = nil) {
        let candidates = store.panelsAvailableToReceiveInteraction()
        guard !candidates.isEmpty else {
            presentError("\(reason.blurb) No active panel has room (each panel maxes out at 6). Make room first and try again.")
            done?(false)
            return
        }
        let sheet = UIAlertController(
            title: "Restore to a different panel?",
            message: "\(reason.blurb) Pick a panel to restore \"\(displayName(for: item))\" into:",
            preferredStyle: .actionSheet
        )
        for panel in candidates {
            let countSuffix = " (\(panel.interactions.count)/\(PanelStore.maxInteractionsPerUserPanel))"
            sheet.addAction(UIAlertAction(title: panel.title + countSuffix, style: .default) { [weak self] _ in
                do {
                    _ = try self?.store.restoreInteraction(trashID: item.trashID, to: panel.id)
                    self?.reload(); done?(true)
                } catch {
                    self?.presentError("Couldn't restore: \(error)"); done?(false)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done?(false) })
        if let popover = sheet.popoverPresentationController,
           let cell = tableView.cellForRow(at: IndexPath(row: items.firstIndex(where: { $0.trashID == item.trashID }) ?? 0,
                                                         section: 0)) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    // MARK: - Purge / empty

    private func confirmPurge(_ item: PanelStore.TrashedItem,
                              done: ((Bool) -> Void)? = nil) {
        gatePINIfSet(store: store) { [weak self] in
            guard let self = self else { done?(false); return }
            let alert = UIAlertController(
                title: "Delete Forever?",
                message: "This permanently removes \"\(self.displayName(for: item))\" and its files. It cannot be undone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done?(false) })
            alert.addAction(UIAlertAction(title: "Delete Forever", style: .destructive) { [weak self] _ in
                self?.store.purgeTrash(trashID: item.trashID)
                self?.reload(); done?(true)
            })
            self.present(alert, animated: true)
        }
    }

    @objc private func confirmEmpty() {
        guard !items.isEmpty else { return }
        gatePINIfSet(store: store) { [weak self] in
            guard let self = self else { return }
            let alert = UIAlertController(
                title: "Empty Trash?",
                message: "This permanently removes \(self.items.count) item\(self.items.count == 1 ? "" : "s") and their files.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Empty Trash", style: .destructive) { [weak self] _ in
                self?.store.emptyTrash()
                self?.reload()
            })
            self.present(alert, animated: true)
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Trash", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
