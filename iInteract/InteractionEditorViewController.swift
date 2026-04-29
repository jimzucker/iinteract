//
//  InteractionEditorViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit
import PhotosUI
import AVFoundation

/// Editor for a single user-authored Interaction: name, picture (PHPicker),
/// and a boy + girl voice recording (AVAudioRecorder). New picks/recordings
/// land in a per-edit temp directory and are only copied to the PanelStore
/// asset paths on Save, so Cancel discards everything cleanly.
final class InteractionEditorViewController: UITableViewController,
                                             PHPickerViewControllerDelegate,
                                             UIImagePickerControllerDelegate,
                                             UINavigationControllerDelegate,
                                             AVAudioRecorderDelegate {

    enum Intent {
        case new
        case edit(Interaction)
    }

    // MARK: Sections

    private enum Section: Int, CaseIterable {
        case name, picture, audio
    }

    // MARK: State

    private let store: PanelStore
    private let intent: Intent

    private let workingID: UUID
    private var workingName: String
    private var workingPicture: UIImage?

    /// Per-edit scratch dir; deleted on save or cancel.
    private let tempDirectory: URL

    /// In-temp file URLs for picks/recordings (nil until the user picks/records).
    private var tempPictureURL: URL?
    private var tempBoyAudioURL: URL?
    private var tempGirlAudioURL: URL?

    /// Existing on-disk asset URLs (used when editing — Save will copy temp
    /// over them; if the user didn't re-record, the existing file is kept).
    private let existingBoyAudioURL: URL?
    private let existingGirlAudioURL: URL?

    /// Snapshot of the interaction state at init time. Used to detect
    /// unsaved changes when the user taps Cancel.
    private let originalName: String
    private let originalHadPicture: Bool
    private let originalHadBoyAudio: Bool
    private let originalHadGirlAudio: Bool

    /// Swipe-to-clear flags. When true, the corresponding existing asset
    /// (if any) is deleted from PanelStore on Save. UI hides the asset
    /// immediately so the user sees it as "removed."
    private var clearedPicture = false
    private var clearedBoyAudio = false
    private var clearedGirlAudio = false

    private var saveButton: UIBarButtonItem!

    // Recording / playback
    private var recorder: AVAudioRecorder?
    private var currentlyRecordingVoice: PanelStore.Voice?
    private var previewPlayer: AVAudioPlayer?

    var onSave: ((Interaction) -> Void)?

    // MARK: Init

    init(intent: Intent = .new, store: PanelStore = .shared) {
        self.intent = intent
        self.store = store

        switch intent {
        case .new:
            self.workingID = UUID()
            self.workingName = ""
            self.workingPicture = nil
            self.existingBoyAudioURL = nil
            self.existingGirlAudioURL = nil
            self.originalName = ""
            self.originalHadPicture = false
            self.originalHadBoyAudio = false
            self.originalHadGirlAudio = false
        case .edit(let interaction):
            self.workingID = interaction.id
            self.workingName = interaction.name ?? ""
            self.workingPicture = interaction.picture
            self.existingBoyAudioURL = interaction.boySound
            self.existingGirlAudioURL = interaction.girlSound
            self.originalName = interaction.name ?? ""
            self.originalHadPicture = interaction.picture != nil
            self.originalHadBoyAudio = interaction.boySound != nil
            self.originalHadGirlAudio = interaction.girlSound != nil
        }

        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractionEditor-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("InteractionEditorViewController is programmatic")
    }

    deinit {
        // Make sure scratch is cleaned up even if pop animation already completed.
        try? FileManager.default.removeItem(at: tempDirectory)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isEditingExisting ? "Edit Interaction" : "New Interaction"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        saveButton = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem = saveButton

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        revalidate()
    }

    private var isEditingExisting: Bool {
        if case .edit = intent { return true } else { return false }
    }

    // MARK: Validation

    private func revalidate() {
        let trimmed = workingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !trimmed.isEmpty
        let hasPicture = workingPicture != nil
        saveButton.isEnabled = hasName && hasPicture
    }

    // MARK: Save / Cancel

    /// True when the user has made any changes the Cancel/X button
    /// would discard. Used to gate the discard-confirmation alert.
    private var hasUnsavedChanges: Bool {
        let trimmedName = workingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != originalName.trimmingCharacters(in: .whitespacesAndNewlines) {
            return true
        }
        if tempPictureURL != nil { return true }
        if clearedPicture && originalHadPicture { return true }
        if tempBoyAudioURL != nil { return true }
        if clearedBoyAudio && originalHadBoyAudio { return true }
        if tempGirlAudioURL != nil { return true }
        if clearedGirlAudio && originalHadGirlAudio { return true }
        return false
    }

    @objc private func cancelTapped() {
        stopAnyPlayback()
        guard hasUnsavedChanges else {
            try? FileManager.default.removeItem(at: tempDirectory)
            navigationController?.popViewController(animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Discard Changes?",
            message: "Your edits to this interaction haven't been saved. Are you sure you want to discard them?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            try? FileManager.default.removeItem(at: self?.tempDirectory ?? URL(fileURLWithPath: "/dev/null"))
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        stopAnyPlayback()
        do {
            // Picture: clear-then-pick wins; otherwise copy temp; otherwise
            // keep existing. New interactions must have a picture (validation
            // should have prevented Save being enabled otherwise).
            if clearedPicture && tempPictureURL == nil {
                // Route through the AssetStore so CloudKit-backed
                // deployments enqueue a deleteAsset push (LocalFS just
                // removes the file, same as before).
                store.deleteInteractionAsset(kind: .picture, id: workingID)
            }
            if let picURL = tempPictureURL,
               let image = UIImage(contentsOfFile: picURL.path) {
                try store.saveInteractionPicture(image, id: workingID)
            } else if !isEditingExisting {
                throw PanelStore.StoreError.assetWriteFailed
            }
            // Audio: same pattern per voice.
            try writeOrClearAudio(.boy,
                                  temp: tempBoyAudioURL,
                                  cleared: clearedBoyAudio)
            try writeOrClearAudio(.girl,
                                  temp: tempGirlAudioURL,
                                  cleared: clearedGirlAudio)

            let interaction = Interaction(id: workingID,
                                          name: workingName.trimmingCharacters(in: .whitespacesAndNewlines))
            store.hydrate(interaction)
            try? FileManager.default.removeItem(at: tempDirectory)
            onSave?(interaction)
            navigationController?.popViewController(animated: true)
        } catch {
            present(alert: "Save Failed", message: "\(error)")
        }
    }

    private func writeOrClearAudio(_ voice: PanelStore.Voice, temp: URL?, cleared: Bool) throws {
        let dest = store.assetURL(for: workingID, kind: voice.assetKind)
        if cleared && temp == nil {
            // Route through the AssetStore so CloudKit deployments
            // enqueue a deleteAsset push.
            store.deleteInteractionAsset(kind: voice.assetKind, id: workingID)
            return
        }
        if let temp = temp {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: temp, to: dest)
            // FileManager.copyItem bypasses the AssetStore, so notify
            // it explicitly. CloudKit-backed stores enqueue an upload;
            // local-FS stores no-op.
            store.didExternallyWriteAsset(kind: voice.assetKind, id: workingID)
        }
        // else: untouched — keep existing
    }

    private func present(alert title: String, message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    // MARK: - Table view

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .name:    return "Name"
        case .picture: return "Picture"
        case .audio:   return "Voices"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .name:    return nil
        case .picture: return "Tap to choose a picture from your photos."
        case .audio:   return "Record a boy and a girl voice. Either one is required."
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .name:    return 1
        case .picture: return 1
        case .audio:   return 2  // boy, girl
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        // Reset
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.contentConfiguration = nil

        switch Section(rawValue: indexPath.section)! {
        case .name:
            let field = UITextField()
            field.placeholder = "happy, snack, hello…"
            field.text = workingName
            field.autocorrectionType = .no
            field.returnKeyType = .done
            field.addTarget(self, action: #selector(nameChanged(_:)), for: .editingChanged)
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
            ])

        case .picture:
            var content = cell.defaultContentConfiguration()
            content.text = workingPicture == nil ? "Choose Picture…" : "Change Picture…"
            cell.contentConfiguration = content
            if let img = workingPicture {
                // Thumb on the right + a visible Clear (trash) button so the
                // picture can be removed without discovering the swipe gesture.
                let thumb = UIImageView(image: img)
                thumb.contentMode = .scaleAspectFill
                thumb.clipsToBounds = true
                thumb.layer.cornerRadius = 6
                thumb.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    thumb.widthAnchor.constraint(equalToConstant: 44),
                    thumb.heightAnchor.constraint(equalToConstant: 44),
                ])
                let clear = Self.makeClearButton(target: self, action: #selector(clearPictureTapped))
                let stack = UIStackView(arrangedSubviews: [clear, thumb])
                stack.axis = .horizontal
                stack.spacing = 12
                stack.alignment = .center
                stack.frame = CGRect(x: 0, y: 0, width: 92, height: 44)
                cell.accessoryView = stack
            } else {
                cell.accessoryType = .disclosureIndicator
            }

        case .audio:
            // Custom layout — title left, status center, action buttons right,
            // all in one Auto-Layout stack inside the cell's contentView. The
            // old accessoryView-only approach left the buttons cramped against
            // the right edge and made the title overlap the buttons on
            // narrower screens.
            let voice: PanelStore.Voice = (indexPath.row == 0) ? .boy : .girl
            let voiceName = voice == .boy ? "Boy voice" : "Girl voice"
            let isRecording = currentlyRecordingVoice == voice
            let hasAudio = audioURL(for: voice) != nil

            let title = UILabel()
            title.text = voiceName
            title.font = .preferredFont(forTextStyle: .body)
            title.setContentHuggingPriority(.required, for: .horizontal)

            let status = UILabel()
            status.text = isRecording ? "Recording…"
                                      : (hasAudio ? "Recorded ✓" : "Not recorded")
            status.font = .preferredFont(forTextStyle: .footnote)
            status.textColor = isRecording ? .systemRed : .secondaryLabel
            status.textAlignment = .right
            status.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let buttons = UIStackView()
            buttons.axis = .horizontal
            buttons.spacing = 16
            buttons.alignment = .center

            if hasAudio && !isRecording {
                let clear = Self.makeAudioButton(systemName: "trash",
                                                 tint: .systemRed,
                                                 tag: voice == .boy ? 0 : 1,
                                                 target: self,
                                                 action: #selector(clearVoiceTapped(_:)))
                buttons.addArrangedSubview(clear)
                let play = Self.makeAudioButton(systemName: "play.circle",
                                                tint: .systemBlue,
                                                tag: voice == .boy ? 0 : 1,
                                                target: self,
                                                action: #selector(playTapped(_:)))
                buttons.addArrangedSubview(play)
            }

            let recordSymbol = isRecording ? "stop.circle.fill" : "mic.circle"
            let recordTint: UIColor = isRecording ? .systemRed : .systemBlue
            let recordSelector = isRecording ? #selector(stopRecordTapped)
                                             : #selector(recordTapped(_:))
            let record = Self.makeAudioButton(systemName: recordSymbol,
                                              tint: recordTint,
                                              tag: voice == .boy ? 0 : 1,
                                              target: self,
                                              action: recordSelector)
            buttons.addArrangedSubview(record)

            let row = UIStackView(arrangedSubviews: [title, status, buttons])
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            ])
        }

        return cell
    }

    private static func makeAudioButton(systemName: String,
                                        tint: UIColor,
                                        tag: Int,
                                        target: Any,
                                        action: Selector) -> UIButton {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        b.tintColor = tint
        b.tag = tag
        b.addTarget(target, action: action, for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 36),
            b.heightAnchor.constraint(equalToConstant: 36),
        ])
        return b
    }

    private static func makeClearButton(target: Any, action: Selector) -> UIButton {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "trash", withConfiguration: config), for: .normal)
        b.tintColor = .systemRed
        b.addTarget(target, action: action, for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 36),
            b.heightAnchor.constraint(equalToConstant: 36),
        ])
        return b
    }

    @objc private func clearPictureTapped() {
        confirmClear(title: "Remove picture?",
                     message: "You'll need to choose a new one before saving.",
                     apply: { [weak self] in
            self?.workingPicture = nil
            self?.tempPictureURL = nil
            self?.clearedPicture = true
            self?.tableView.reloadSections([Section.picture.rawValue], with: .automatic)
            self?.revalidate()
        }, done: { _ in })
    }

    @objc private func clearVoiceTapped(_ sender: UIButton) {
        let voice: PanelStore.Voice = (sender.tag == 0) ? .boy : .girl
        let voiceName = voice == .boy ? "boy" : "girl"
        confirmClear(title: "Remove \(voiceName) recording?",
                     message: nil,
                     apply: { [weak self] in
            switch voice {
            case .boy:  self?.tempBoyAudioURL  = nil; self?.clearedBoyAudio  = true
            case .girl: self?.tempGirlAudioURL = nil; self?.clearedGirlAudio = true
            }
            self?.tableView.reloadSections([Section.audio.rawValue], with: .automatic)
        }, done: { _ in })
    }

    private func audioURL(for voice: PanelStore.Voice) -> URL? {
        switch voice {
        case .boy:
            if clearedBoyAudio { return nil }
            return tempBoyAudioURL ?? existingBoyAudioURL
        case .girl:
            if clearedGirlAudio { return nil }
            return tempGirlAudioURL ?? existingGirlAudioURL
        }
    }

    // MARK: - Swipe-to-clear

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
                            -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section)! {
        case .name:
            return nil
        case .picture:
            guard workingPicture != nil else { return nil }
            return Self.clearActionConfig { [weak self] done in
                self?.confirmClear(title: "Remove picture?",
                                   message: "You'll need to choose a new one before saving.",
                                   apply: { [weak self] in
                    self?.workingPicture = nil
                    self?.tempPictureURL = nil
                    self?.clearedPicture = true
                    self?.tableView.reloadSections([Section.picture.rawValue], with: .automatic)
                    self?.revalidate()
                }, done: done)
            }
        case .audio:
            let voice: PanelStore.Voice = (indexPath.row == 0) ? .boy : .girl
            guard audioURL(for: voice) != nil, currentlyRecordingVoice != voice else { return nil }
            let voiceName = voice == .boy ? "boy" : "girl"
            return Self.clearActionConfig { [weak self] done in
                self?.confirmClear(title: "Remove \(voiceName) recording?",
                                   message: nil,
                                   apply: { [weak self] in
                    switch voice {
                    case .boy:  self?.tempBoyAudioURL  = nil; self?.clearedBoyAudio  = true
                    case .girl: self?.tempGirlAudioURL = nil; self?.clearedGirlAudio = true
                    }
                    self?.tableView.reloadSections([Section.audio.rawValue], with: .automatic)
                }, done: done)
            }
        }
    }

    private static func clearActionConfig(_ run: @escaping (@escaping (Bool) -> Void) -> Void)
        -> UISwipeActionsConfiguration {
        let action = UIContextualAction(style: .destructive, title: "Clear") { _, _, completion in
            run(completion)
        }
        action.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func confirmClear(title: String,
                              message: String?,
                              apply: @escaping () -> Void,
                              done: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
            apply(); done(true)
        })
        present(alert, animated: true)
    }

    @objc private func nameChanged(_ field: UITextField) {
        workingName = field.text ?? ""
        revalidate()
    }

    // MARK: Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .picture {
            presentPicturePicker()
        }
    }

    // MARK: - Picture picker (camera or library)

    private func presentPicturePicker() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentCamera()
            })
        }
        sheet.addAction(UIAlertAction(title: "Choose from Library", style: .default) { [weak self] _ in
            self?.presentLibrary()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // iPad needs a source rect for the popover.
        if let popover = sheet.popoverPresentationController,
           let cell = tableView.cellForRow(at: IndexPath(row: 0, section: Section.picture.rawValue)) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func presentLibrary() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    /// Shared "got an image" path used by both the library picker and camera.
    private func adoptPickedImage(_ image: UIImage) {
        workingPicture = image
        clearedPicture = false
        // Stash a temp JPEG so Save can re-encode without re-loading from PhotoKit.
        let url = tempDirectory.appendingPathComponent("picture.jpg")
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
            tempPictureURL = url
        }
        revalidate()
        // Defer the reload to the next runloop tick so the picker's
        // dismiss animation can complete before we trigger layout —
        // calling reloadSections mid-transition was tripping the
        // "UITableView was told to layout … without being in the
        // view hierarchy" warning when the picker was the active modal.
        reloadSectionWhenSafe(.picture)
    }

    private func reloadSectionWhenSafe(_ section: Section) {
        safeReloadSections([section.rawValue], with: .none)
    }

    // PHPickerViewControllerDelegate
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            DispatchQueue.main.async {
                guard let self = self, let image = object as? UIImage else { return }
                self.adoptPickedImage(image)
            }
        }
    }

    // UIImagePickerControllerDelegate (camera)
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) { [weak self] in
            guard let image = info[.originalImage] as? UIImage else { return }
            self?.adoptPickedImage(image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    // MARK: - Recording

    @objc private func recordTapped(_ sender: UIButton) {
        let voice: PanelStore.Voice = (sender.tag == 0) ? .boy : .girl
        requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    self.present(alert: "Microphone Access",
                                 message: "Enable microphone access in Settings to record voices.")
                    return
                }
                self.beginRecording(voice: voice)
            }
        }
    }

    private func requestRecordPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    private func beginRecording(voice: PanelStore.Voice) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = tempDirectory.appendingPathComponent("\(voice == .boy ? "boy" : "girl").m4a")
            let settings: [String: Any] = [
                AVFormatIDKey:           Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey:         44100,
                AVNumberOfChannelsKey:   1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.record()
            recorder = r
            currentlyRecordingVoice = voice
            tableView.reloadSections([Section.audio.rawValue], with: .none)
        } catch {
            present(alert: "Recording Failed", message: "\(error)")
        }
    }

    @objc private func stopRecordTapped() {
        guard let r = recorder, let voice = currentlyRecordingVoice else { return }
        r.stop()
        let url = r.url
        switch voice {
        case .boy:  tempBoyAudioURL = url
        case .girl: tempGirlAudioURL = url
        }
        recorder = nil
        currentlyRecordingVoice = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        tableView.reloadSections([Section.audio.rawValue], with: .none)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { present(alert: "Recording Failed", message: "Audio capture stopped unexpectedly.") }
    }

    // MARK: - Playback

    @objc private func playTapped(_ sender: UIButton) {
        let voice: PanelStore.Voice = (sender.tag == 0) ? .boy : .girl
        guard let url = audioURL(for: voice) else { return }
        stopAnyPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.play()
            previewPlayer = p
        } catch {
            present(alert: "Playback Failed", message: "\(error)")
        }
    }

    private func stopAnyPlayback() {
        previewPlayer?.stop()
        previewPlayer = nil
    }
}
