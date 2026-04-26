//
//  SettingsViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

/// In-app Settings — the gear icon in the main nav bar pushes this. It
/// mirrors the iOS Settings.bundle (voice, mode) for quick access AND owns
/// the things that don't belong in the system Settings app: PIN management,
/// "Clear All My Data", and the entry to the panel editor.
///
/// Destructive actions (clearing the PIN, clearing all data, opening the
/// editor, changing the PIN) gate behind the PIN when one is set.
final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case voice, mode, editor, security, privacy
    }

    private let store: PanelStore
    private var voiceStyle: String = "girl"
    private var configurationMode: ConfigurationMode = .default
    private var hasPIN: Bool = false

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
        title = "Settings"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        readState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        readState()
        tableView.reloadData()
    }

    private func readState() {
        let defaults = UserDefaults.standard
        voiceStyle = defaults.string(forKey: "voice_style") ?? "girl"
        configurationMode = ConfigurationMode.current(defaults)
        hasPIN = store.hasPIN
    }

    // MARK: - Sections

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .voice:    return "Voice"
        case .mode:     return "Mode"
        case .editor:   return nil
        case .security: return "Security"
        case .privacy:  return "Privacy"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .voice:    return nil
        case .mode:     return "Default keeps the seven built-in panels exactly as they are. Custom lets you hide / reorder them and add your own."
        case .editor:   return configurationMode == .custom ? nil : "Switch to Custom mode to add or hide panels."
        case .security: return hasPIN ? "PIN protects destructive actions in this screen and the panel editor. Syncs across your iCloud devices." : "Optional. Set a PIN to require entry before opening the editor or clearing data."
        case .privacy:  return "Removes every panel, picture, recording, and PIN that this app has stored on this device."
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .voice, .mode, .editor, .privacy: return 1
        case .security:                         return hasPIN ? 2 : 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .voice:
            let seg = UISegmentedControl(items: ["Girl", "Boy"])
            seg.selectedSegmentIndex = (voiceStyle == "boy") ? 1 : 0
            seg.addTarget(self, action: #selector(voiceChanged(_:)), for: .valueChanged)
            cell.accessoryView = seg
            seg.frame = CGRect(x: 0, y: 0, width: 160, height: 30)
            cell.textLabel?.text = "Voice Style"
            cell.selectionStyle = .none

        case .mode:
            let seg = UISegmentedControl(items: ["Default", "Custom"])
            seg.selectedSegmentIndex = (configurationMode == .custom) ? 1 : 0
            seg.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
            cell.accessoryView = seg
            seg.frame = CGRect(x: 0, y: 0, width: 200, height: 30)
            cell.textLabel?.text = "Mode"
            cell.selectionStyle = .none

        case .editor:
            cell.textLabel?.text = "Edit Panels…"
            cell.imageView?.image = UIImage(systemName: "square.and.pencil")
            cell.accessoryType = .disclosureIndicator
            cell.isUserInteractionEnabled = (configurationMode == .custom)
            cell.textLabel?.isEnabled = (configurationMode == .custom)

        case .security:
            if indexPath.row == 0 {
                cell.textLabel?.text = hasPIN ? "Change PIN" : "Set PIN"
                cell.imageView?.image = UIImage(systemName: "lock.fill")
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Clear PIN"
                cell.textLabel?.textColor = .systemRed
                cell.imageView?.image = UIImage(systemName: "lock.open")
            }

        case .privacy:
            cell.textLabel?.text = "Clear All My Data…"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "trash")
        }
        return cell
    }

    // MARK: - Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .voice, .mode:
            break
        case .editor:
            guard configurationMode == .custom else { return }
            gateThenRun { [weak self] in self?.pushEditor() }
        case .security:
            if indexPath.row == 0 {
                // Set/Change PIN — gate when changing an existing PIN.
                gateThenRun { [weak self] in self?.pushPINSetup() }
            } else {
                gateThenRun { [weak self] in self?.confirmClearPIN() }
            }
        case .privacy:
            gateThenRun { [weak self] in self?.confirmClearAllData() }
        }
    }

    // MARK: - Actions

    @objc private func voiceChanged(_ sender: UISegmentedControl) {
        let value = (sender.selectedSegmentIndex == 1) ? "boy" : "girl"
        voiceStyle = value
        UserDefaults.standard.set(value, forKey: "voice_style")
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let mode: ConfigurationMode = (sender.selectedSegmentIndex == 1) ? .custom : .default
        configurationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: ConfigurationMode.userDefaultsKey)
        // Refresh the editor / footer rows to reflect the new mode.
        tableView.reloadSections([Section.editor.rawValue], with: .none)
    }

    private func pushEditor() {
        navigationController?.pushViewController(PanelListEditorViewController(), animated: true)
    }

    private func pushPINSetup() {
        navigationController?.pushViewController(PINSetupViewController(), animated: true)
    }

    private func confirmClearPIN() {
        let alert = UIAlertController(
            title: "Clear PIN?",
            message: "Anyone using this device will be able to open the editor and clear data without entering a PIN.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear PIN", style: .destructive) { [weak self] _ in
            self?.store.clearPIN()
            self?.readState()
            self?.tableView.reloadSections([Section.security.rawValue], with: .automatic)
        })
        present(alert, animated: true)
    }

    private func confirmClearAllData() {
        let alert = UIAlertController(
            title: "Clear All My Data?",
            message: "This removes every custom panel, picture, recording, and your PIN. Bundled panels stay. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.store.clearAllUserData()
            self?.readState()
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    // MARK: - PIN gating

    /// Runs `action` immediately if no PIN is set, or after a successful
    /// PIN-gate dismissal otherwise.
    private func gateThenRun(_ action: @escaping () -> Void) {
        guard store.hasPIN else { action(); return }
        let gate = PINGateViewController(store: store)
        let nav = UINavigationController(rootViewController: gate)
        nav.modalPresentationStyle = .fullScreen
        gate.onUnlock = { [weak nav] in
            nav?.dismiss(animated: true) { action() }
        }
        gate.onCancel = { [weak nav] in nav?.dismiss(animated: true) }
        present(nav, animated: true)
    }
}
