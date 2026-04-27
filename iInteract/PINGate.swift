//
//  PINGate.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

/// Length / charset rules for a user-chosen PIN. Existing PINs hashed
/// under earlier rules (4-digit numeric, 4–6 alphanumeric) still verify
/// because the store hashes whatever string is submitted; this only
/// constrains *new* PIN entry.
enum PINPolicy {
    static let minLength = 4
    static let maxLength = 8
    static let humanDescription = "4–8 letters or numbers"
    static let invalidMessage = "PIN must be \(humanDescription)."

    static func isValid(_ pin: String) -> Bool {
        let count = pin.count
        guard count >= minLength, count <= maxLength else { return false }
        return pin.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Strips non-alphanumeric characters (handles whitespace from paste,
    /// keyboard punctuation, emoji). Does NOT truncate — callers must
    /// validate length explicitly via `isValid` and surface an error
    /// rather than silently dropping characters.
    static func sanitize(_ raw: String) -> String {
        String(raw.filter { $0.isLetter || $0.isNumber })
    }
}

extension UITextField {
    /// Adds a trailing eye toggle that flips `isSecureTextEntry` between
    /// hidden (default) and visible. Use on every PIN entry field so the
    /// caregiver can verify what they're typing on a small keyboard.
    func attachShowPINToggle() {
        let button = UIButton(type: .system)
        button.tintColor = .secondaryLabel
        let initialName = isSecureTextEntry ? "eye.slash" : "eye"
        button.setImage(UIImage(systemName: initialName), for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 32, height: 24)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self = self else { return }
            self.isSecureTextEntry.toggle()
            let name = self.isSecureTextEntry ? "eye.slash" : "eye"
            button?.setImage(UIImage(systemName: name), for: .normal)
        }, for: .touchUpInside)
        rightView = button
        rightViewMode = .always
    }
}

extension UIViewController {
    /// Runs `action` immediately when no PIN is set, or after the user
    /// successfully unlocks the PIN gate when one is set. `onCancel` fires
    /// when the user dismisses the gate (so callers like swipe actions can
    /// reset their UI state). Used to wrap privileged actions (open editor,
    /// restore from trash) so they can't be triggered accidentally or by
    /// an unattended child.
    ///
    /// For destructive actions that would otherwise show a follow-up
    /// "Cancel / Delete" confirmation after the PIN, prefer
    /// `confirmDestructiveWithPIN(...)` instead — it folds both steps into a
    /// single alert (PIN field + Cancel + destructive button).
    func gatePINIfSet(store: PanelStore = .shared,
                      onCancel: (() -> Void)? = nil,
                      _ action: @escaping () -> Void) {
        guard store.hasPIN else { action(); return }
        let gate = PINGateViewController(store: store)
        let nav = UINavigationController(rootViewController: gate)
        nav.modalPresentationStyle = .fullScreen
        gate.onUnlock = { [weak nav] in
            nav?.dismiss(animated: true) { action() }
        }
        gate.onCancel = { [weak nav] in
            nav?.dismiss(animated: true) { onCancel?() }
        }
        present(nav, animated: true)
    }

    /// Single-step PIN-gated confirmation. When a PIN is set, the alert
    /// includes a PIN field; on the action button we verify the PIN before
    /// calling `onConfirm`. When no PIN is set, a plain Cancel / action
    /// alert is shown. Wrong PIN re-presents the alert with a
    /// remaining-attempts message; after 5 wrong attempts the user is
    /// locked out for 60s (same window as the editor-entry gate).
    ///
    /// `actionStyle` controls the button color — `.destructive` (red) for
    /// delete-style actions, `.default` (blue) for restores or anything
    /// non-destructive.
    func confirmActionWithPIN(title: String,
                              message: String,
                              actionTitle: String,
                              actionStyle: UIAlertAction.Style = .destructive,
                              store: PanelStore = .shared,
                              onForgotPIN: (() -> Void)? = nil,
                              onCancel: (() -> Void)? = nil,
                              onConfirm: @escaping () -> Void) {
        guard store.hasPIN else {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in onCancel?() })
            alert.addAction(UIAlertAction(title: actionTitle, style: actionStyle) { _ in onConfirm() })
            present(alert, animated: true)
            return
        }
        let state = PINGateState(store: store)
        presentCombinedPINConfirm(title: title,
                                  baseMessage: message,
                                  actionTitle: actionTitle,
                                  actionStyle: actionStyle,
                                  state: state,
                                  errorMessage: nil,
                                  onForgotPIN: onForgotPIN,
                                  onCancel: onCancel,
                                  onConfirm: onConfirm)
    }

    /// Backwards-compatible alias — destructive is the most common case.
    func confirmDestructiveWithPIN(title: String,
                                   message: String,
                                   destructiveTitle: String,
                                   store: PanelStore = .shared,
                                   onCancel: (() -> Void)? = nil,
                                   onConfirm: @escaping () -> Void) {
        confirmActionWithPIN(title: title, message: message,
                             actionTitle: destructiveTitle,
                             actionStyle: .destructive,
                             store: store,
                             onCancel: onCancel,
                             onConfirm: onConfirm)
    }

    private func presentCombinedPINConfirm(title: String,
                                           baseMessage: String,
                                           actionTitle: String,
                                           actionStyle: UIAlertAction.Style,
                                           state: PINGateState,
                                           errorMessage: String?,
                                           onForgotPIN: (() -> Void)?,
                                           onCancel: (() -> Void)?,
                                           onConfirm: @escaping () -> Void) {
        var lines: [String] = [baseMessage, "", "Enter your PIN (\(PINPolicy.humanDescription)) to confirm."]
        if let err = errorMessage { lines.append(err) }
        let alert = UIAlertController(title: title,
                                      message: lines.joined(separator: "\n"),
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "PIN"
            tf.keyboardType = .asciiCapable
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.isSecureTextEntry = true
            tf.attachShowPINToggle()
        }
        let primary = UIAlertAction(title: actionTitle, style: actionStyle) { [weak self, weak alert] _ in
            let entered = PINPolicy.sanitize(alert?.textFields?.first?.text ?? "")
            switch state.attempt(entered) {
            case .success:
                onConfirm()
            case .wrong(let remaining):
                let msg = "Incorrect PIN. \(remaining) attempt\(remaining == 1 ? "" : "s") remaining."
                self?.presentCombinedPINConfirm(title: title,
                                                baseMessage: baseMessage,
                                                actionTitle: actionTitle,
                                                actionStyle: actionStyle,
                                                state: state,
                                                errorMessage: msg,
                                                onForgotPIN: onForgotPIN,
                                                onCancel: onCancel,
                                                onConfirm: onConfirm)
            case .lockedOut(let seconds):
                let lock = UIAlertController(title: "Too Many Attempts",
                                             message: "Try again in \(seconds)s.",
                                             preferredStyle: .alert)
                lock.addAction(UIAlertAction(title: "OK", style: .default) { _ in onCancel?() })
                self?.present(lock, animated: true)
            }
        }
        // Stack carries only Cancel + the primary action. Forgot PIN? lives
        // on the keyboard toolbar below as a small link, so it's reachable
        // while typing without competing for visual weight with the primary.
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in onCancel?() })
        alert.addAction(primary)
        alert.preferredAction = primary

        if let onForgotPIN = onForgotPIN, let pinField = alert.textFields?.first {
            let bar = UIToolbar()
            bar.sizeToFit()
            bar.tintColor = .systemBlue
            // Custom-view button so we can bold the label — bare bar buttons
            // render in default weight and are easy to overlook on the
            // keyboard accessory.
            let button = UIButton(type: .system)
            button.setTitle("Forgot PIN?", for: .normal)
            button.setTitleColor(.systemBlue, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.addAction(UIAction { [weak alert] _ in
                alert?.dismiss(animated: true) { onForgotPIN() }
            }, for: .touchUpInside)
            button.sizeToFit()
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let link = UIBarButtonItem(customView: button)
            bar.items = [spacer, link]
            pinField.inputAccessoryView = bar
        }

        present(alert, animated: true)
    }

    /// Reusable Forgot-PIN flow: action sheet with "Reset via iCloud Account"
    /// (signed-in check) and "Answer Security Question" (when one is set).
    /// On successful reset the PIN is cleared from PanelStore and `onReset`
    /// is called so the caller can proceed (e.g. open the editor).
    /// `onAbort` fires whenever the user dismisses the flow without
    /// resetting (Cancel, iCloud not signed in, wrong answer) — callers
    /// use it to re-present the original PIN-confirm alert so the user
    /// isn't dead-ended.
    func presentForgotPINResetSheet(store: PanelStore = .shared,
                                    sourceView: UIView? = nil,
                                    onAbort: (() -> Void)? = nil,
                                    onReset: @escaping () -> Void) {
        let sheet = UIAlertController(title: "Reset PIN",
                                      message: "Choose how to reset your PIN.",
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Reset via iCloud Account", style: .default) { [weak self] _ in
            do {
                try store.resetPINViaICloudAccount()
                onReset()
            } catch {
                self?.presentSimpleInfoAlert(
                    title: "Couldn't Reset",
                    message: "Sign into iCloud in Settings, then try again.",
                    onDismiss: onAbort
                )
            }
        })
        if store.hasSecurityQuestion {
            sheet.addAction(UIAlertAction(title: "Answer Security Question", style: .default) { [weak self] _ in
                self?.presentSecurityAnswerPrompt(store: store,
                                                  onAbort: onAbort,
                                                  onReset: onReset)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            onAbort?()
        })
        if let popover = sheet.popoverPresentationController, let src = sourceView {
            popover.sourceView = src
            popover.sourceRect = src.bounds
        }
        present(sheet, animated: true)
    }

    private func presentSecurityAnswerPrompt(store: PanelStore,
                                             onAbort: (() -> Void)?,
                                             onReset: @escaping () -> Void) {
        let alert = UIAlertController(title: "Security Question",
                                      message: store.securityQuestion,
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Your answer" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            onAbort?()
        })
        alert.addAction(UIAlertAction(title: "Reset PIN", style: .destructive) { [weak self, weak alert] _ in
            let answer = alert?.textFields?.first?.text ?? ""
            do {
                try store.resetPIN(securityAnswer: answer)
                onReset()
            } catch {
                self?.presentSimpleInfoAlert(
                    title: "Wrong Answer",
                    message: "That's not the answer we have on file.",
                    onDismiss: onAbort
                )
            }
        })
        present(alert, animated: true)
    }

    private func presentSimpleInfoAlert(title: String,
                                        message: String,
                                        onDismiss: (() -> Void)? = nil) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in onDismiss?() })
        present(a, animated: true)
    }
}

// MARK: - PINPromptCoordinator (UIKit-free, unit-testable)

/// Configuration for a PIN-related alert. Models the alert as data so the
/// coordinator can drive the flow without importing UIKit; a `PINPresenter`
/// (production: UIAlertController, tests: in-memory recorder) translates
/// the config into a real surface.
struct PINAlertConfig {
    let title: String
    let message: String
    let fields: [Field]
    let buttons: [Button]

    struct Field {
        let placeholder: String
        let prefilledText: String
        let isSecureEntry: Bool
        let attachShowToggle: Bool
    }

    struct Button {
        let title: String
        let style: Style
        enum Style { case cancel, `default`, destructive }
    }
}

/// Renders a `PINAlertConfig` and reports user interaction back. Production
/// is a UIViewController extension that maps to UIAlertController; tests
/// use a recorder that lets them script the user's taps deterministically.
protocol PINPresenter: AnyObject {
    /// Present `config`. When the user taps a button, call `handler` with
    /// the tapped button index and the current text-field values.
    func presentPINAlert(_ config: PINAlertConfig,
                         handler: @escaping (_ buttonIndex: Int, _ fieldValues: [String]) -> Void)
}

/// Drives PIN-prompt cycling logic without depending on UIKit. Extracted
/// so the validate/cycle/cancel paths are unit-testable.
final class PINPromptCoordinator {

    private let store: PanelStore
    private let defaults: UserDefaults
    private weak var presenter: PINPresenter?

    init(store: PanelStore = .shared,
         defaults: UserDefaults = .standard,
         presenter: PINPresenter) {
        self.store = store
        self.defaults = defaults
        self.presenter = presenter
    }

    /// Cycling set-PIN flow with confirmation. On every invalid-input
    /// path the alert is re-presented with the user's typed values
    /// prefilled and an explicit error message — Cancel is the only
    /// way out, on which `pin_enabled` is reverted to false.
    /// `onComplete(true)` after a successful set; `onComplete(false)`
    /// after Cancel.
    func runEnablePINFlow(onComplete: @escaping (Bool) -> Void) {
        runEnablePIN(prefillPIN: "", prefillConfirm: "",
                     errorMessage: nil, onComplete: onComplete)
    }

    private func runEnablePIN(prefillPIN: String,
                              prefillConfirm: String,
                              errorMessage: String?,
                              onComplete: @escaping (Bool) -> Void) {
        let config = PINAlertConfig(
            title: "Set PIN",
            message: composeSetPINMessage(error: errorMessage),
            fields: [
                .init(placeholder: "PIN",
                      prefilledText: prefillPIN,
                      isSecureEntry: true,
                      attachShowToggle: true),
                .init(placeholder: "Confirm PIN",
                      prefilledText: prefillConfirm,
                      isSecureEntry: true,
                      attachShowToggle: true),
            ],
            buttons: [
                .init(title: "Cancel", style: .cancel),
                .init(title: "Set PIN", style: .default),
            ]
        )
        presenter?.presentPINAlert(config) { [weak self] buttonIndex, values in
            guard let self = self else { return }
            if buttonIndex == 0 {  // Cancel
                self.defaults.set(false, forKey: "pin_enabled")
                self.defaults.synchronize()
                onComplete(false)
                return
            }
            let pin = values.indices.contains(0) ? values[0] : ""
            let confirm = values.indices.contains(1) ? values[1] : ""
            if !PINPolicy.isValid(pin) {
                self.runEnablePIN(prefillPIN: pin,
                                  prefillConfirm: confirm,
                                  errorMessage: PINPolicy.invalidMessage,
                                  onComplete: onComplete)
            } else if pin != confirm {
                self.runEnablePIN(prefillPIN: pin,
                                  prefillConfirm: confirm,
                                  errorMessage: "PINs didn't match. Try again.",
                                  onComplete: onComplete)
            } else {
                self.store.setPIN(pin)
                onComplete(true)
            }
        }
    }

    private func composeSetPINMessage(error: String?) -> String {
        var lines = [
            "Enter a PIN (\(PINPolicy.humanDescription)), then confirm it.",
            "The PIN will be required to open the configuration editor and to delete panels, recordings, or clear data."
        ]
        if let err = error {
            lines.insert(err, at: 0)
            lines.insert("", at: 1)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - UIKit-backed PINPresenter

extension UIViewController: PINPresenter {
    func presentPINAlert(_ config: PINAlertConfig,
                         handler: @escaping (Int, [String]) -> Void) {
        let alert = UIAlertController(title: config.title,
                                      message: config.message,
                                      preferredStyle: .alert)
        for field in config.fields {
            alert.addTextField { tf in
                tf.placeholder = field.placeholder
                tf.text = field.prefilledText
                tf.isSecureTextEntry = field.isSecureEntry
                tf.keyboardType = .asciiCapable
                tf.autocapitalizationType = .none
                tf.autocorrectionType = .no
                if field.attachShowToggle { tf.attachShowPINToggle() }
            }
        }
        for (index, button) in config.buttons.enumerated() {
            let style: UIAlertAction.Style
            switch button.style {
            case .cancel:      style = .cancel
            case .default:     style = .default
            case .destructive: style = .destructive
            }
            alert.addAction(UIAlertAction(title: button.title, style: style) { [weak alert] _ in
                let values = (alert?.textFields ?? []).map { $0.text ?? "" }
                handler(index, values)
            })
        }
        // Mark the last non-cancel button as preferred so iOS bolds it
        // (matches the existing combined-confirm UX).
        if let primaryIdx = config.buttons.lastIndex(where: { $0.style != .cancel }) {
            alert.preferredAction = alert.actions[primaryIdx]
        }
        topmostPresenterForPINAlert().present(alert, animated: true)
    }

    /// Walks the active scene's view-controller hierarchy to find the
    /// frontmost presenter, so an alert kicked off by the coordinator
    /// from a sub-screen still lands in front of the user.
    private func topmostPresenterForPINAlert() -> UIViewController {
        var top: UIViewController = self
        if let scene = view.window?.windowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
           let root = window.rootViewController {
            top = root
        }
        while let presented = top.presentedViewController { top = presented }
        if let nav = top as? UINavigationController, let visible = nav.visibleViewController { top = visible }
        return top
    }
}
