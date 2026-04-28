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

/// Pure-logic helpers for reading iOS-Settings flags that drive UI
/// state (gear visibility, etc.). Extracted so the read paths are
/// unit-testable without instantiating a UIViewController.
enum SettingsView {
    /// True when the gear icon should be visible. False when the user
    /// has set Hide Configuration in iOS Settings → iInteract.
    static func gearVisible(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: "hide_config")
    }
}

/// Pure decision for `applyPendingSettingsActions`'s modal-up retry
/// policy. Extracted so the coalesce / max-retry behavior is testable
/// without scheduling real timers.
enum PendingActionsDecision: Equatable {
    /// No modal up — fire the reconciler effects now.
    case fire
    /// Modal up and no retry pending — schedule a retry.
    case scheduleRetry
    /// Modal up but a retry is already pending OR retries exhausted —
    /// drop this call (it would either stack timers or spin forever).
    case skip

    static func decide(modalIsUp: Bool,
                       pendingRetryScheduled: Bool,
                       retriesRemaining: Int) -> PendingActionsDecision {
        if !modalIsUp { return .fire }
        if pendingRetryScheduled { return .skip }
        // After retries exhaust, fire anyway so we don't silently drop
        // the user's pending iOS-Settings change. The presentation
        // layers on top of whatever modal is up via topmostPresenter
        // (UIAlertController-on-UIAlertController is supported).
        if retriesRemaining <= 0 { return .fire }
        return .scheduleRetry
    }
}

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

extension UITableViewController {
    /// `tableView.reloadSections` that defers to the next runloop if
    /// the view isn't in a window yet — avoids "UITableView was told
    /// to layout … outside the view hierarchy" warnings when reloads
    /// fire from async callbacks (PHPicker, AVAudioRecorder, alert
    /// dismiss handlers) that race a transition animation.
    func safeReloadSections(_ sections: [Int],
                            with animation: UITableView.RowAnimation = .automatic) {
        let indexSet = IndexSet(sections)
        if isViewLoaded, view.window != nil {
            tableView.reloadSections(indexSet, with: animation)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      self.isViewLoaded, self.view.window != nil else { return }
                self.tableView.reloadSections(indexSet, with: animation)
            }
        }
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
        // Delegate the cycle/lockout/Forgot-PIN logic to PINVerifyCoordinator
        // so it's testable end-to-end. Keep the coordinator alive with an
        // associated object until the flow completes (it owns its own
        // PINGateState and weakly references this presenter).
        let coordStyle: PINAlertConfig.Button.Style
        switch actionStyle {
        case .cancel:      coordStyle = .cancel
        case .destructive: coordStyle = .destructive
        default:           coordStyle = .default
        }
        let coordinator = PINVerifyCoordinator(store: store, presenter: self)
        objc_setAssociatedObject(self, &Self.verifyCoordinatorKey,
                                 coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        coordinator.runVerifyFlow(
            title: title,
            message: message,
            actionTitle: actionTitle,
            actionStyle: coordStyle,
            onForgotPIN: onForgotPIN,
            onCancel: { [weak self] in
                objc_setAssociatedObject(self ?? UIViewController(),
                                         &Self.verifyCoordinatorKey,
                                         nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                onCancel?()
            },
            onConfirm: { [weak self] in
                objc_setAssociatedObject(self ?? UIViewController(),
                                         &Self.verifyCoordinatorKey,
                                         nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                onConfirm()
            }
        )
    }

    private static var verifyCoordinatorKey: UInt8 = 0

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
        // Knowledge-based reset only. Face ID / iCloud-account checks
        // were both removable by a child with physical access to the
        // parent's signed-in phone ("can you unlock this for me?" or
        // just being in the same room). The security question is the
        // only barrier the child can't trivially bypass — and is now
        // mandatory at PIN setup time, so every active PIN has one.
        sheet.addAction(UIAlertAction(title: "Answer Security Question", style: .default) { [weak self] _ in
            self?.presentSecurityAnswerPrompt(store: store,
                                              onAbort: onAbort,
                                              onReset: onReset)
        })
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

// MARK: - PINPromptCoordinator + PINVerifyCoordinator (UIKit-free, unit-testable)

/// Configuration for a PIN-related alert. Models the alert as data so the
/// coordinators can drive the flow without importing UIKit; a `PINPresenter`
/// (production: UIAlertController, tests: in-memory recorder) translates
/// the config into a real surface.
struct PINAlertConfig {
    let title: String
    let message: String
    let fields: [Field]
    let buttons: [Button]
    /// When non-nil, the presenter renders a Forgot-PIN link (production:
    /// keyboard input accessory toolbar; tests: simulated by calling
    /// `simulateForgotPIN()` on the test presenter). Tapping it dismisses
    /// the alert and reports `.forgotPIN` to the coordinator.
    let forgotPINButtonTitle: String?

    init(title: String,
         message: String,
         fields: [Field],
         buttons: [Button],
         forgotPINButtonTitle: String? = nil) {
        self.title = title
        self.message = message
        self.fields = fields
        self.buttons = buttons
        self.forgotPINButtonTitle = forgotPINButtonTitle
    }

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

/// Outcome of a `PINPresenter` interaction. Either the user tapped one
/// of the regular buttons (producing the index + the current text-field
/// values) or they tapped the Forgot-PIN link (no values).
enum PINAlertResult {
    case buttonTapped(index: Int, fieldValues: [String])
    case forgotPIN
}

/// Renders a `PINAlertConfig` and reports user interaction back. Production
/// is a UIViewController extension that maps to UIAlertController; tests
/// use a recorder that lets them script the user's taps deterministically.
protocol PINPresenter: AnyObject {
    /// Present `config`. When the user takes an action (tap button or tap
    /// the Forgot-PIN link), call `handler` exactly once.
    func presentPINAlert(_ config: PINAlertConfig,
                         handler: @escaping (PINAlertResult) -> Void)
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
        presenter?.presentPINAlert(config) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .forgotPIN:
                // Set-PIN flow doesn't expose Forgot PIN — config has
                // forgotPINButtonTitle = nil — but be defensive.
                return
            case .buttonTapped(let buttonIndex, let values):
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

    /// Production set-PIN flow: PIN-and-confirm cycle followed by a
    /// MANDATORY security-question step. The security question is the
    /// only Forgot-PIN recovery path now — Face ID / iCloud-signed-in
    /// resets were removable by a child with physical access to the
    /// parent's phone. Cancel at the PIN step reverts pin_enabled (via
    /// runEnablePINFlow); the question step has no Cancel — the user
    /// must enter both fields to complete. Behavior is "no question,
    /// no PIN" — if they really want to back out they cancel at the
    /// PIN step.
    func runEnablePINFlowWithSecurityQuestion(onComplete: @escaping (Bool) -> Void) {
        runEnablePINFlow { [weak self] pinSet in
            guard let self = self, pinSet else {
                onComplete(false)
                return
            }
            self.runSecurityQuestionPrompt(prefillQuestion: "",
                                           prefillAnswer: "",
                                           errorMessage: nil,
                                           onComplete: onComplete)
        }
    }

    private func runSecurityQuestionPrompt(prefillQuestion: String,
                                           prefillAnswer: String,
                                           errorMessage: String?,
                                           onComplete: @escaping (Bool) -> Void) {
        var lines = [
            "Required. This is the only way to reset your PIN if you forget it.",
            "Pick a question only you would know the answer to (case- and whitespace-insensitive on reset)."
        ]
        if let err = errorMessage {
            lines.insert(err, at: 0)
            lines.insert("", at: 1)
        }
        let config = PINAlertConfig(
            title: "Set a Security Question",
            message: lines.joined(separator: "\n"),
            fields: [
                .init(placeholder: "Question (e.g. Mother's maiden name)",
                      prefilledText: prefillQuestion,
                      isSecureEntry: false,
                      attachShowToggle: false),
                .init(placeholder: "Answer",
                      prefilledText: prefillAnswer,
                      isSecureEntry: false,
                      attachShowToggle: false),
            ],
            buttons: [
                .init(title: "Save", style: .default),
            ]
        )
        presenter?.presentPINAlert(config) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .forgotPIN:
                return  // not exposed in this flow
            case .buttonTapped(_, let values):
                let q = (values.indices.contains(0) ? values[0] : "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let a = (values.indices.contains(1) ? values[1] : "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if q.isEmpty || a.isEmpty {
                    // Cycle on empty input — user must fill both.
                    self.runSecurityQuestionPrompt(prefillQuestion: q,
                                                   prefillAnswer: a,
                                                   errorMessage: "Both Question and Answer are required.",
                                                   onComplete: onComplete)
                    return
                }
                self.store.setSecurityQuestion(q, answer: a)
                onComplete(true)
            }
        }
    }

    /// Cycling new-PIN flow used by the Change PIN action. Same alert
    /// shape as `runEnablePINFlow` but DOES NOT touch `pin_enabled` —
    /// the user already has a PIN, so Cancel here means "keep the old
    /// one." Title and body copy reflect that.
    func runChangePINFlow(onComplete: @escaping (Bool) -> Void) {
        runChangePIN(prefillPIN: "", prefillConfirm: "",
                     errorMessage: nil, onComplete: onComplete)
    }

    private func runChangePIN(prefillPIN: String,
                              prefillConfirm: String,
                              errorMessage: String?,
                              onComplete: @escaping (Bool) -> Void) {
        let config = PINAlertConfig(
            title: "New PIN",
            message: composeChangePINMessage(error: errorMessage),
            fields: [
                .init(placeholder: "New PIN",
                      prefilledText: prefillPIN,
                      isSecureEntry: true,
                      attachShowToggle: true),
                .init(placeholder: "Confirm New PIN",
                      prefilledText: prefillConfirm,
                      isSecureEntry: true,
                      attachShowToggle: true),
            ],
            buttons: [
                .init(title: "Cancel", style: .cancel),
                .init(title: "Save", style: .default),
            ]
        )
        presenter?.presentPINAlert(config) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .forgotPIN:
                return  // not exposed in this flow
            case .buttonTapped(let buttonIndex, let values):
                if buttonIndex == 0 {
                    // Cancel — leave the existing PIN in place.
                    onComplete(false)
                    return
                }
                let pin = values.indices.contains(0) ? values[0] : ""
                let confirm = values.indices.contains(1) ? values[1] : ""
                if !PINPolicy.isValid(pin) {
                    self.runChangePIN(prefillPIN: pin,
                                      prefillConfirm: confirm,
                                      errorMessage: PINPolicy.invalidMessage,
                                      onComplete: onComplete)
                } else if pin != confirm {
                    self.runChangePIN(prefillPIN: pin,
                                      prefillConfirm: confirm,
                                      errorMessage: "PINs didn't match. Try again.",
                                      onComplete: onComplete)
                } else {
                    self.store.setPIN(pin)
                    onComplete(true)
                }
            }
        }
    }

    private func composeChangePINMessage(error: String?) -> String {
        var lines = [
            "Enter a new PIN (\(PINPolicy.humanDescription)), then confirm it.",
            "Your old PIN will be replaced once you tap Save."
        ]
        if let err = error {
            lines.insert(err, at: 0)
            lines.insert("", at: 1)
        }
        return lines.joined(separator: "\n")
    }

    /// Verify-current-PIN-then-disable flow used when the user toggles
    /// Enable PIN OFF in iOS Settings. Cancel reverts pin_enabled back
    /// to true so iOS Settings reflects reality. Disable verifies the
    /// current PIN (via PINVerifyCoordinator); on success calls
    /// clearPIN(). Wrong PIN cycles via the verify coordinator's
    /// 5-attempts + 60s lockout. The inner verify coordinator is
    /// retained as a property until the flow completes — without that
    /// it gets deallocated mid-flow and the wrong/success handlers
    /// silently no-op.
    func runDisablePINFlow(now: @escaping () -> Date = Date.init,
                           onComplete: @escaping (Bool) -> Void) {
        guard let presenter = presenter else { return }
        let verify = PINVerifyCoordinator(store: store,
                                          presenter: presenter,
                                          now: now,
                                          defaults: defaults)
        activeVerifyCoordinator = verify
        verify.runVerifyFlow(
            title: "Disable PIN?",
            message: "Anyone using this device will be able to delete panels and clear data without entering a PIN.",
            actionTitle: "Disable",
            actionStyle: .destructive,
            onForgotPIN: nil,
            onCancel: { [weak self] in
                self?.activeVerifyCoordinator = nil
                self?.defaults.set(true, forKey: "pin_enabled")
                self?.defaults.synchronize()
                onComplete(false)
            },
            onConfirm: { [weak self] in
                self?.activeVerifyCoordinator = nil
                self?.store.clearPIN()
                onComplete(true)
            }
        )
    }

    /// Strong reference for an in-flight PINVerifyCoordinator (created
    /// inside `runDisablePINFlow` etc.) so the verify cycle's handlers
    /// don't dealloc mid-flow.
    private var activeVerifyCoordinator: PINVerifyCoordinator?
}

/// Drives the verify-PIN cycle (5 attempts then 60s lockout) without
/// depending on UIKit. Wraps `PINGateState` and reports outcome through
/// onCancel / onConfirm / onForgotPIN closures.
final class PINVerifyCoordinator {

    private let store: PanelStore
    private let state: PINGateState
    private weak var presenter: PINPresenter?

    init(store: PanelStore = .shared,
         presenter: PINPresenter,
         now: @escaping () -> Date = Date.init,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.state = PINGateState(store: store, now: now, defaults: defaults)
        self.presenter = presenter
    }

    /// One-shot verify flow. Calls exactly one of:
    /// - `onConfirm()` after a correct PIN
    /// - `onCancel?()` when the user dismisses (Cancel, or OK on the
    ///   lockout alert)
    /// - `onForgotPIN?()` when the user taps the Forgot PIN keyboard link
    func runVerifyFlow(title: String,
                       message: String,
                       actionTitle: String,
                       actionStyle: PINAlertConfig.Button.Style = .destructive,
                       onForgotPIN: (() -> Void)? = nil,
                       onCancel: (() -> Void)? = nil,
                       onConfirm: @escaping () -> Void) {
        runVerify(title: title,
                  baseMessage: message,
                  actionTitle: actionTitle,
                  actionStyle: actionStyle,
                  errorMessage: nil,
                  onForgotPIN: onForgotPIN,
                  onCancel: onCancel,
                  onConfirm: onConfirm)
    }

    private func runVerify(title: String,
                           baseMessage: String,
                           actionTitle: String,
                           actionStyle: PINAlertConfig.Button.Style,
                           errorMessage: String?,
                           onForgotPIN: (() -> Void)?,
                           onCancel: (() -> Void)?,
                           onConfirm: @escaping () -> Void) {
        var lines: [String] = [baseMessage, "", "Enter your PIN (\(PINPolicy.humanDescription)) to confirm."]
        if let err = errorMessage { lines.append(err) }
        let config = PINAlertConfig(
            title: title,
            message: lines.joined(separator: "\n"),
            fields: [
                .init(placeholder: "PIN",
                      prefilledText: "",
                      isSecureEntry: true,
                      attachShowToggle: true),
            ],
            buttons: [
                .init(title: "Cancel", style: .cancel),
                .init(title: actionTitle, style: actionStyle),
            ],
            forgotPINButtonTitle: onForgotPIN != nil ? "Forgot PIN?" : nil
        )
        presenter?.presentPINAlert(config) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .forgotPIN:
                onForgotPIN?()
            case .buttonTapped(let buttonIndex, let values):
                if buttonIndex == 0 {  // Cancel
                    onCancel?()
                    return
                }
                let entered = PINPolicy.sanitize(values.first ?? "")
                switch self.state.attempt(entered) {
                case .success:
                    onConfirm()
                case .wrong(let remaining):
                    let msg = "Incorrect PIN. \(remaining) attempt\(remaining == 1 ? "" : "s") remaining."
                    self.runVerify(title: title,
                                   baseMessage: baseMessage,
                                   actionTitle: actionTitle,
                                   actionStyle: actionStyle,
                                   errorMessage: msg,
                                   onForgotPIN: onForgotPIN,
                                   onCancel: onCancel,
                                   onConfirm: onConfirm)
                case .lockedOut(let seconds):
                    self.presentLockoutAlert(seconds: seconds, onCancel: onCancel)
                }
            }
        }
    }

    private func presentLockoutAlert(seconds: Int, onCancel: (() -> Void)?) {
        let lockConfig = PINAlertConfig(
            title: "Too Many Attempts",
            message: "Try again in \(seconds)s.",
            fields: [],
            buttons: [.init(title: "OK", style: .default)]
        )
        presenter?.presentPINAlert(lockConfig) { _ in
            onCancel?()
        }
    }
}

// MARK: - SettingsReconciler (UIKit-free)

/// Examines the current iOS-Settings flags + PIN state and returns the
/// list of effects the view controller should apply. Pure logic — no
/// UIKit dependency — so every input combination is unit-testable.
///
/// Also clears one-shot toggles (`change_pin`, `pending_clear_all`) as
/// part of `reconcile()` so callers don't have to remember to do it
/// themselves and we never have a path where an effect fires twice.
final class SettingsReconciler {

    /// Action the VC should dispatch. Order in the returned array is
    /// the order the VC should run them.
    enum Effect: Equatable {
        case enablePIN
        case disablePIN
        case changePIN
        case clearAllData
    }

    private let store: PanelStore
    private let defaults: UserDefaults

    init(store: PanelStore = .shared,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    func reconcile() -> [Effect] {
        defaults.synchronize()
        var effects: [Effect] = []

        // Enable / disable PIN — derived from pin_enabled toggle vs
        // the actual store-side hasPIN. Diverging means the user just
        // changed the toggle and we need to bring state in sync.
        let wantEnabled = defaults.bool(forKey: "pin_enabled")
        let hasPIN = store.hasPIN
        if wantEnabled && !hasPIN {
            effects.append(.enablePIN)
        } else if !wantEnabled && hasPIN {
            effects.append(.disablePIN)
        }

        // Change PIN — fire-and-forget toggle. Clear immediately so it
        // doesn't fire twice on consecutive reconciles. Silently
        // consume if there's no PIN to change.
        let wantChange = defaults.bool(forKey: "change_pin")
        if wantChange {
            defaults.set(false, forKey: "change_pin")
            defaults.synchronize()
            if hasPIN {
                effects.append(.changePIN)
            }
        }

        // Clear all data — same one-shot pattern.
        let wantClear = defaults.bool(forKey: "pending_clear_all")
        if wantClear {
            defaults.set(false, forKey: "pending_clear_all")
            defaults.synchronize()
            effects.append(.clearAllData)
        }

        return effects
    }
}

// MARK: - UIKit-backed PINPresenter

extension UIViewController: PINPresenter {
    func presentPINAlert(_ config: PINAlertConfig,
                         handler: @escaping (PINAlertResult) -> Void) {
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
                handler(.buttonTapped(index: index, fieldValues: values))
            })
        }
        // Mark the last non-cancel button as preferred so iOS bolds it
        // (matches the existing combined-confirm UX).
        if let primaryIdx = config.buttons.lastIndex(where: { $0.style != .cancel }) {
            alert.preferredAction = alert.actions[primaryIdx]
        }

        // Forgot PIN link on the keyboard input accessory toolbar.
        if let forgotTitle = config.forgotPINButtonTitle, let pinField = alert.textFields?.first {
            let bar = UIToolbar()
            bar.sizeToFit()
            bar.tintColor = .systemBlue
            let button = UIButton(type: .system)
            button.setTitle(forgotTitle, for: .normal)
            button.setTitleColor(.systemBlue, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.addAction(UIAction { [weak alert] _ in
                alert?.dismiss(animated: true) { handler(.forgotPIN) }
            }, for: .touchUpInside)
            button.sizeToFit()
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let link = UIBarButtonItem(customView: button)
            bar.items = [spacer, link]
            pinField.inputAccessoryView = bar
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
