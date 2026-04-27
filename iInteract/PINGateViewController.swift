//
//  PINGateViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

// MARK: - State machine (testable)

/// PIN-gate verification state, separated from the view so it can be unit
/// tested without spinning up a UI. Tracks attempt count and lockout window.
final class PINGateState {
    static let maxAttempts: Int = 5
    static let lockoutDuration: TimeInterval = 60

    enum Outcome: Equatable {
        case success
        case wrong(remainingAttempts: Int)
        case lockedOut(secondsRemaining: Int)
    }

    private let store: PanelStore
    private let now: () -> Date
    private(set) var attempts: Int = 0
    private(set) var lockedUntil: Date?

    init(store: PanelStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    var isLocked: Bool {
        guard let until = lockedUntil else { return false }
        return until > now()
    }

    var lockoutSecondsRemaining: Int {
        guard let until = lockedUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now())))
    }

    func attempt(_ pin: String) -> Outcome {
        if isLocked { return .lockedOut(secondsRemaining: lockoutSecondsRemaining) }
        if store.verifyPIN(pin) {
            attempts = 0
            lockedUntil = nil
            return .success
        }
        attempts += 1
        if attempts >= Self.maxAttempts {
            lockedUntil = now().addingTimeInterval(Self.lockoutDuration)
            return .lockedOut(secondsRemaining: Int(Self.lockoutDuration))
        }
        return .wrong(remainingAttempts: Self.maxAttempts - attempts)
    }
}

// MARK: - Gate screen

/// Modal screen presented before the PanelListEditor when a PIN is set. On
/// success, calls `onUnlock`. Cancel calls `onCancel`. Forgot PIN routes to
/// either the iCloud account reset or the security-question answer flow.
final class PINGateViewController: UIViewController, UITextFieldDelegate {

    private let store: PanelStore
    private let state: PINGateState

    private let dotsStack = UIStackView()
    private let pinField = UITextField()
    private let messageLabel = UILabel()
    private let forgotButton = UIButton(type: .system)
    private var lockoutTimer: Timer?

    var onUnlock: (() -> Void)?
    var onCancel: (() -> Void)?

    init(store: PanelStore = .shared) {
        self.store = store
        self.state = PINGateState(store: store)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Enter PIN"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )

        // 4 dots
        dotsStack.axis = .horizontal
        dotsStack.spacing = 16
        dotsStack.distribution = .fillEqually
        for _ in 0..<4 {
            let dot = UIView()
            dot.backgroundColor = .systemGray4
            dot.layer.cornerRadius = 12
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 24),
                dot.heightAnchor.constraint(equalToConstant: 24),
            ])
            dotsStack.addArrangedSubview(dot)
        }
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dotsStack)

        // Hidden text field that drives entry
        pinField.keyboardType = .numberPad
        pinField.isSecureTextEntry = true
        pinField.delegate = self
        pinField.addTarget(self, action: #selector(pinChanged(_:)), for: .editingChanged)
        pinField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pinField)

        messageLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)

        forgotButton.setTitle("Forgot PIN?", for: .normal)
        forgotButton.addTarget(self, action: #selector(forgotTapped), for: .touchUpInside)
        forgotButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(forgotButton)

        // Tap anywhere to focus the entry field
        let tap = UITapGestureRecognizer(target: self, action: #selector(focusEntry))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            dotsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dotsStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),

            pinField.topAnchor.constraint(equalTo: dotsStack.bottomAnchor, constant: 1),
            pinField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pinField.widthAnchor.constraint(equalToConstant: 1),
            pinField.heightAnchor.constraint(equalToConstant: 1),

            messageLabel.topAnchor.constraint(equalTo: dotsStack.bottomAnchor, constant: 24),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            forgotButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            forgotButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pinField.becomeFirstResponder()
    }

    @objc private func focusEntry() {
        pinField.becomeFirstResponder()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func pinChanged(_ field: UITextField) {
        let digits = (field.text ?? "").filter { $0.isNumber }
        let trimmed = String(digits.prefix(4))
        if trimmed != field.text { field.text = trimmed }
        updateDots(filledCount: trimmed.count)
        if trimmed.count == 4 {
            handleAttempt(trimmed)
        }
    }

    private func updateDots(filledCount: Int) {
        for (i, dot) in dotsStack.arrangedSubviews.enumerated() {
            dot.backgroundColor = (i < filledCount) ? .label : .systemGray4
        }
    }

    private func handleAttempt(_ pin: String) {
        switch state.attempt(pin) {
        case .success:
            onUnlock?()
        case .wrong(let remaining):
            messageLabel.text = "Incorrect PIN. \(remaining) attempt\(remaining == 1 ? "" : "s") remaining."
            messageLabel.textColor = .systemRed
            shake(dotsStack)
            pinField.text = ""
            updateDots(filledCount: 0)
        case .lockedOut(let seconds):
            beginLockoutDisplay(secondsRemaining: seconds)
        }
    }

    private func beginLockoutDisplay(secondsRemaining: Int) {
        pinField.isEnabled = false
        pinField.text = ""
        updateDots(filledCount: 0)
        updateLockoutText()
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLockoutText()
        }
    }

    private func updateLockoutText() {
        let remaining = state.lockoutSecondsRemaining
        if remaining <= 0 || !state.isLocked {
            lockoutTimer?.invalidate()
            lockoutTimer = nil
            pinField.isEnabled = true
            messageLabel.text = nil
            messageLabel.textColor = .secondaryLabel
            pinField.becomeFirstResponder()
        } else {
            messageLabel.text = "Too many attempts. Try again in \(remaining)s."
            messageLabel.textColor = .systemRed
        }
    }

    private func shake(_ v: UIView) {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.duration = 0.4
        anim.values = [-12, 12, -8, 8, -4, 4, 0]
        v.layer.add(anim, forKey: "shake")
    }

    @objc private func forgotTapped() {
        let sheet = UIAlertController(title: "Reset PIN",
                                      message: "Choose how to reset your PIN.",
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Reset via iCloud Account", style: .default) { [weak self] _ in
            self?.attemptICloudReset()
        })
        if store.hasSecurityQuestion {
            sheet.addAction(UIAlertAction(title: "Answer Security Question", style: .default) { [weak self] _ in
                self?.presentSecurityAnswerPrompt()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = forgotButton
        sheet.popoverPresentationController?.sourceRect = forgotButton.bounds
        present(sheet, animated: true)
    }

    private func attemptICloudReset() {
        do {
            try store.resetPINViaICloudAccount()
            // Reset succeeded → no PIN now → unlock
            onUnlock?()
        } catch {
            present(alert: "Couldn't Reset",
                    message: "Sign into iCloud in Settings, then try again.")
        }
    }

    private func presentSecurityAnswerPrompt() {
        let alert = UIAlertController(title: "Security Question",
                                      message: store.securityQuestion,
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Your answer" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset PIN", style: .destructive) { [weak self, weak alert] _ in
            let answer = alert?.textFields?.first?.text ?? ""
            do {
                try self?.store.resetPIN(securityAnswer: answer)
                self?.onUnlock?()
            } catch {
                self?.present(alert: "Wrong Answer",
                              message: "That's not the answer we have on file.")
            }
        })
        present(alert, animated: true)
    }

    private func present(alert title: String, message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

// MARK: - Setup screen

/// Set / change the PIN, with an optional security question. Reachable from
/// the Security row in PanelListEditor. The user is already past the gate to
/// be on this screen, so we don't re-verify the existing PIN here.
final class PINSetupViewController: UITableViewController {

    private enum Section: Int, CaseIterable { case pin, question }
    private enum Row: Int { case enter = 0, confirm = 1 }

    private let store: PanelStore
    private var newPIN: String = ""
    private var confirmPIN: String = ""
    private var question: String = ""
    private var answer: String = ""

    private var saveButton: UIBarButtonItem!
    private var errorMessage: String?
    private weak var pinFooterLabel: UILabel?
    private weak var questionFooterLabel: UILabel?

    var onComplete: (() -> Void)?

    init(store: PanelStore = .shared) {
        self.store = store
        self.question = store.securityQuestion ?? ""
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = store.hasPIN ? "Change PIN" : "Set PIN"
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

    @objc private func cancelTapped() { navigationController?.popViewController(animated: true) }

    @objc private func saveTapped() {
        view.endEditing(true)
        guard PINPolicy.isValid(newPIN), newPIN == confirmPIN else { return }
        store.setPIN(newPIN,
                     securityQuestion: question.isEmpty ? nil : question,
                     securityAnswer: answer.isEmpty ? nil : answer)
        onComplete?()
        navigationController?.popViewController(animated: true)
    }

    private func revalidate() {
        let pinValid = PINPolicy.isValid(newPIN) && newPIN == confirmPIN
        // Question + answer are both-or-neither.
        let qValid = (question.isEmpty && answer.isEmpty) ||
                     (!question.isEmpty && !answer.isEmpty)
        if !newPIN.isEmpty && !PINPolicy.isValid(newPIN) {
            errorMessage = "PIN must be \(PINPolicy.humanDescription)."
        } else if PINPolicy.isValid(newPIN) && newPIN != confirmPIN && !confirmPIN.isEmpty {
            errorMessage = "PINs don't match."
        } else if !qValid {
            errorMessage = "Set both a question and an answer, or neither."
        } else {
            errorMessage = nil
        }
        saveButton.isEnabled = pinValid && qValid
        // Update footer labels in place — reloading the section would dismiss
        // the keyboard after every keystroke.
        pinFooterLabel?.text = errorMessage
    }

    // MARK: - Table view

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .pin:      return "PIN"
        case .question: return "Security Question (optional)"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        // Footers come from viewForFooterInSection so we can update them
        // without reloading the section (which would dismiss the keyboard).
        nil
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .pin:
            let (view, label) = makeFooterLabelView(text: errorMessage, color: .systemRed)
            self.pinFooterLabel = label
            return view
        case .question:
            let (view, label) = makeFooterLabelView(text: "Lets you reset your PIN later if you forget it.",
                                                    color: .secondaryLabel)
            self.questionFooterLabel = label
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
        case .pin:      return 2
        case .question: return 2
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
        switch (Section(rawValue: indexPath.section)!, indexPath.row) {
        case (.pin, 0):
            field.placeholder = "New PIN (\(PINPolicy.humanDescription))"
            field.keyboardType = .asciiCapable
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.isSecureTextEntry = true
            field.attachShowPINToggle()
            field.text = newPIN
            field.addTarget(self, action: #selector(newPINChanged(_:)), for: .editingChanged)
        case (.pin, 1):
            field.placeholder = "Confirm PIN"
            field.keyboardType = .asciiCapable
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.isSecureTextEntry = true
            field.attachShowPINToggle()
            field.text = confirmPIN
            field.addTarget(self, action: #selector(confirmPINChanged(_:)), for: .editingChanged)
        case (.question, 0):
            field.placeholder = "Question (e.g. Mother's maiden name)"
            field.text = question
            field.addTarget(self, action: #selector(questionChanged(_:)), for: .editingChanged)
        case (.question, 1):
            field.placeholder = "Answer"
            field.text = answer
            field.addTarget(self, action: #selector(answerChanged(_:)), for: .editingChanged)
        default: break
        }
        return cell
    }

    @objc private func newPINChanged(_ f: UITextField) {
        newPIN = PINPolicy.sanitize(f.text ?? "")
        if newPIN != f.text { f.text = newPIN }
        revalidate()
    }
    @objc private func confirmPINChanged(_ f: UITextField) {
        confirmPIN = PINPolicy.sanitize(f.text ?? "")
        if confirmPIN != f.text { f.text = confirmPIN }
        revalidate()
    }
    @objc private func questionChanged(_ f: UITextField) {
        question = f.text ?? ""
        revalidate()
    }
    @objc private func answerChanged(_ f: UITextField) {
        answer = f.text ?? ""
        revalidate()
    }
}
