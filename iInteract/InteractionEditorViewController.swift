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
        case .edit(let interaction):
            self.workingID = interaction.id
            self.workingName = interaction.name ?? ""
            self.workingPicture = interaction.picture
            self.existingBoyAudioURL = interaction.boySound
            self.existingGirlAudioURL = interaction.girlSound
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

    @objc private func cancelTapped() {
        stopAnyPlayback()
        try? FileManager.default.removeItem(at: tempDirectory)
        navigationController?.popViewController(animated: true)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        stopAnyPlayback()
        do {
            // Picture: clear-then-pick wins; otherwise copy temp; otherwise
            // keep existing. New interactions must have a picture (validation
            // should have prevented Save being enabled otherwise).
            if clearedPicture && tempPictureURL == nil {
                try? FileManager.default.removeItem(at: store.assetURL(for: workingID, kind: .picture))
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
            try? FileManager.default.removeItem(at: dest)
            return
        }
        if let temp = temp {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: temp, to: dest)
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
                let thumb = UIImageView(image: img)
                thumb.contentMode = .scaleAspectFill
                thumb.clipsToBounds = true
                thumb.layer.cornerRadius = 6
                thumb.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                cell.accessoryView = thumb
            } else {
                cell.accessoryType = .disclosureIndicator
            }

        case .audio:
            let voice: PanelStore.Voice = (indexPath.row == 0) ? .boy : .girl
            let voiceName = voice == .boy ? "Boy voice" : "Girl voice"
            var content = cell.defaultContentConfiguration()
            content.text = voiceName

            let isRecording = currentlyRecordingVoice == voice
            let hasAudio = audioURL(for: voice) != nil
            content.secondaryText = isRecording ? "Recording…"
                                  : (hasAudio ? "Recorded ✓" : "Not recorded")
            cell.contentConfiguration = content

            // Trailing button: Stop while recording, otherwise Record (and a
            // small Play if there's a recording to preview).
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false

            if hasAudio && !isRecording {
                let play = makeIconButton(systemName: "play.circle",
                                          tint: .systemBlue,
                                          action: #selector(playTapped(_:)))
                play.tag = voice == .boy ? 0 : 1
                stack.addArrangedSubview(play)
            }

            let recordButton = makeIconButton(
                systemName: isRecording ? "stop.circle.fill" : "mic.circle",
                tint: isRecording ? .systemRed : .systemBlue,
                action: isRecording ? #selector(stopRecordTapped) : #selector(recordTapped(_:))
            )
            recordButton.tag = voice == .boy ? 0 : 1
            stack.addArrangedSubview(recordButton)

            cell.accessoryView = stack
            stack.frame = CGRect(x: 0, y: 0, width: hasAudio && !isRecording ? 80 : 36, height: 30)
        }

        return cell
    }

    private func makeIconButton(systemName: String,
                                tint: UIColor,
                                action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: systemName), for: .normal)
        b.tintColor = tint
        b.addTarget(self, action: action, for: .touchUpInside)
        b.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        return b
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

    // MARK: - Picture picker

    private func presentPicturePicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            guard let self = self,
                  let image = object as? UIImage else { return }
            DispatchQueue.main.async {
                self.workingPicture = image
                // Stash a temp JPEG so save can re-encode without re-loading from PhotoKit.
                let url = self.tempDirectory.appendingPathComponent("picture.jpg")
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: url, options: .atomic)
                    self.tempPictureURL = url
                }
                self.tableView.reloadSections([Section.picture.rawValue], with: .none)
                self.revalidate()
            }
        }
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
