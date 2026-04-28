//
//  FeelingTableViewController.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. 
//

import UIKit

class FeelingTableViewController: UITableViewController {

    // MARK: Properties
    
    
    var panels = [Panel]()
    var configurationButton : UIBarButtonItem?

    // MARK: Settings Properties
    var voiceEnabled        : Bool                = true
    var voiceStyle          : String              = "girl"
    var configurationMode   : ConfigurationMode   = .default

    //dislay splash screen 1 time then disable it by setting a preference, we use an int so we can show newer splash screens, it will be set to the current version # once it shows
    var displaySplashScreen : String     = ""

   fileprivate func loadPanels() {
        panels = Panel.load(mode: configurationMode)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

            //gear icon is the entry to panel/interaction editing and the
            //Trash. Always visible — even in default mode — so it can't be
            //hidden by leftover state from the storyboard's + button.
            //Voice / Mode / PIN / Clear Data live in iOS Settings.bundle.
        configurationButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(showEditor)
        )
        navigationItem.rightBarButtonItem = configurationButton

        //register for settings + iCloud KVS panel sync + foreground resume
        NotificationCenter.default.addObserver(self, selector: #selector(FeelingTableViewController.settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(FeelingTableViewController.panelStoreChanged), name: PanelStore.didChangeNotification, object: nil)
        // didBecomeActive fires whenever the app comes back from
        // background — including from iOS Settings — so we can pick up
        // pin_enabled / pending_clear_all changes even when the user is
        // currently on a pushed sub-screen (editor, panel editor, etc).
        NotificationCenter.default.addObserver(self, selector: #selector(FeelingTableViewController.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        //read mode/voice from defaults
        updateSettings()

        //show the preferences
//        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)

        //load panels for the current mode
        loadPanels()
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // UserDefaults.didChangeNotification only fires for changes made in
        // this process, NOT for changes made in iOS Settings (which runs in
        // its own process). Re-read settings every time we appear.
        updateSettings()
        // Apply any PIN/clear-data requests the user made in iOS Settings.
        applyPendingSettingsActions()
        // Pick up any visibility/order edits from the in-app editor.
        loadPanels()
        tableView.reloadData()
        // Keep the watch's mirror of the visible built-in list current.
        WatchSync.shared.pushVisiblePanels()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showSplashScreen()
    }

    /// Computes pending iOS-Settings effects via `SettingsReconciler` and
    /// dispatches each to the corresponding in-app prompt. The reconciler
    /// is the single source of truth for "what does the user want us to
    /// do given current toggle state vs. PIN store state" and is fully
    /// unit-tested. This method only handles the modal-up retry policy
    /// and the dispatch table from Effect → prompt method.
    ///
    /// If another modal is already up when we'd present, retry on a short
    /// delay so a Settings change made while the user was mid-dialog still
    /// reaches the user once the existing dialog dismisses. Coalesces
    /// multiple concurrent retries via `pendingRetryScheduled` so we
    /// don't stack timers.
    private func applyPendingSettingsActions(retriesRemaining: Int = 5) {
        let modalIsUp = topmostPresenter().presentedViewController != nil
        switch PendingActionsDecision.decide(modalIsUp: modalIsUp,
                                              pendingRetryScheduled: pendingRetryScheduled,
                                              retriesRemaining: retriesRemaining) {
        case .skip:
            return
        case .scheduleRetry:
            pendingRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.pendingRetryScheduled = false
                self.applyPendingSettingsActions(retriesRemaining: retriesRemaining - 1)
            }
            return
        case .fire:
            break
        }

        let reconciler = SettingsReconciler()
        for effect in reconciler.reconcile() {
            switch effect {
            case .enablePIN:    promptEnablePIN()
            case .disablePIN:   promptDisablePIN()
            case .changePIN:    promptChangePIN()
            case .clearAllData: confirmAndClearAllData()
            }
        }
    }

    private var pendingRetryScheduled: Bool {
        get { (objc_getAssociatedObject(self, &Self.pendingRetryKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.pendingRetryKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private static var pendingRetryKey: UInt8 = 0

    /// User toggled "Enable PIN" on in iOS Settings but no PIN is set
    /// yet. Delegates the cycle-on-failure / prefill / cancel logic to
    /// `PINPromptCoordinator` so the flow is unit-testable end-to-end
    /// without needing a real UIAlertController.
    private func promptEnablePIN() {
        let coordinator = PINPromptCoordinator(presenter: topmostPresenter())
        // Hold the coordinator alive until the flow completes — the
        // presenter is held weakly inside the coordinator and the
        // coordinator itself has no other owner during the async
        // alert chain.
        objc_setAssociatedObject(self, &Self.enableCoordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // Production flow includes the optional security-question step
        // after the PIN is saved, so the user has a Forgot-PIN reset
        // path even when iCloud isn't signed in.
        coordinator.runEnablePINFlowWithSecurityQuestion { [weak self] _ in
            objc_setAssociatedObject(self ?? UIViewController(),
                                     &Self.enableCoordinatorKey, nil,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private static var enableCoordinatorKey: UInt8 = 0

    /// User toggled "Change PIN" in iOS Settings. Verify current PIN
    /// (using the existing PINVerifyCoordinator under confirmActionWithPIN),
    /// then on success, run the cycling new-PIN flow. Cancel at either
    /// step leaves the existing PIN intact (Change is a no-op rollback).
    private func promptChangePIN() {
        confirmActionWithPIN(
            title: "Change PIN",
            message: "Enter your current PIN to continue.",
            actionTitle: "Continue",
            actionStyle: .default,
            onForgotPIN: { [weak self] in
                self?.presentForgotPINResetSheet(
                    onAbort: { [weak self] in self?.promptChangePIN() },
                    onReset: { [weak self] in
                        // PIN cleared via reset — there's no current PIN
                        // anymore, so the change flow doesn't apply.
                        // Tell the user and bring iOS Settings in line.
                        UserDefaults.standard.set(false, forKey: "pin_enabled")
                        UserDefaults.standard.synchronize()
                        let info = UIAlertController(
                            title: "PIN Cleared",
                            message: "Your PIN was reset and is now off. Re-enable it any time in Settings → iInteract → Enable PIN.",
                            preferredStyle: .alert
                        )
                        info.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.topmostPresenter().present(info, animated: true)
                    }
                )
            }
        ) { [weak self] in
            // Verify succeeded — prompt for new PIN with cycling validation.
            self?.runSetNewPINAfterVerify()
        }
    }

    private func runSetNewPINAfterVerify() {
        let coordinator = PINPromptCoordinator(presenter: topmostPresenter())
        objc_setAssociatedObject(self, &Self.changeCoordinatorKey,
                                 coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        coordinator.runChangePINFlow { [weak self] _ in
            objc_setAssociatedObject(self ?? UIViewController(),
                                     &Self.changeCoordinatorKey, nil,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private static var changeCoordinatorKey: UInt8 = 0

    /// User toggled "Enable PIN" off in iOS Settings while a PIN is
    /// set. Delegates to PINPromptCoordinator.runDisablePINFlow so the
    /// verify-then-clear logic and the cancel-reverts-toggle behavior
    /// are unit-testable end-to-end without UIKit.
    private func promptDisablePIN() {
        let coordinator = PINPromptCoordinator(presenter: topmostPresenter())
        objc_setAssociatedObject(self, &Self.disableCoordinatorKey,
                                 coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        coordinator.runDisablePINFlow { [weak self] _ in
            objc_setAssociatedObject(self ?? UIViewController(),
                                     &Self.disableCoordinatorKey, nil,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private static var disableCoordinatorKey: UInt8 = 0

    private func presentSimpleAlert(title: String, message: String) {
        let host = topmostPresenter()
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        host.present(a, animated: true)
    }

    /// Walks the active scene's view-controller hierarchy to find the
    /// frontmost presenter, so prompts triggered by a foreground resume
    /// don't get buried under a pushed editor or modal.
    private func topmostPresenter() -> UIViewController {
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

    private func confirmAndClearAllData() {
        confirmDestructiveWithPIN(
            title: "Clear All My Data?",
            message: "This permanently removes every custom panel, picture, recording, trashed item, and your PIN. Bundled panels are unaffected. The app will return to Default mode. This cannot be undone.",
            destructiveTitle: "Clear All"
        ) { [weak self] in
            PanelStore.shared.clearAllUserData()
            // Reset mode to default so a freshly-wiped device looks
            // like a first-launch install. clearAllUserData already
            // dropped the KVS mode key; write default through both to
            // keep UserDefaults in sync and notify any other devices.
            PanelStore.shared.setConfigurationMode(.default)
            // Hole #1 fix: clearAllUserData wipes the PIN hash, so the
            // pin_enabled toggle in iOS Settings must follow — otherwise
            // the next reconcile sees "wants PIN, has none" and prompts
            // the user to set one as if fresh, which is confusing right
            // after a deliberate wipe.
            UserDefaults.standard.set(false, forKey: "pin_enabled")
            UserDefaults.standard.synchronize()
            self?.updateSettings()
            self?.loadPanels()
            self?.tableView.reloadData()
        }
    }

    @objc func showEditor() {
        // Default mode is a child-safe read-only state. The gear is still
        // visible (parents discover where config lives), but tapping it
        // explains all three modes and points them to iOS Settings.
        if configurationMode == .default {
            let alert = UIAlertController(
                title: "Configuration is Off",
                message: """
                iInteract is in Default mode — the bundled panels only, with no editing.

                To change this, open Settings → iInteract → Mode and choose:

                • Configurable — Hide and reorder the bundled panels.

                • Customize — Add your own panels with custom pictures and voice recordings.
                """,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        // PIN gates ENTRY to the editor (in addition to each destructive
        // action inside it). Combined alert: PIN field + Cancel + Configure,
        // with a Forgot PIN? action that opens the iCloud / security
        // question reset paths.
        let openEditor: () -> Void = { [weak self] in
            guard let self = self else { return }
            let editor = PanelListEditorViewController(mode: self.configurationMode)
            self.navigationController?.pushViewController(editor, animated: true)
        }
        // No PIN set → no protection to enforce, so don't show the
        // Cancel/Configure alert with its misleading "PIN-protected"
        // message. Open the editor directly.
        guard PanelStore.shared.hasPIN else {
            openEditor()
            return
        }
        // Wrapped so we can re-present the PIN-confirm alert when the
        // Forgot PIN flow aborts (iCloud signed out, wrong answer,
        // user cancels) — without this the user is dead-ended at the
        // info alert and has to tap the gear again.
        showPINGateForEditor(openEditor: openEditor)
    }

    private func showPINGateForEditor(openEditor: @escaping () -> Void) {
        confirmActionWithPIN(
            title: "Open Configuration",
            message: "Configuration is PIN-protected. Enter your PIN to open the editor.",
            actionTitle: "Configure",
            actionStyle: .default,
            onForgotPIN: { [weak self] in
                self?.presentForgotPINResetSheet(
                    onAbort: { [weak self] in
                        // Re-present the PIN-confirm alert so the user
                        // isn't dropped back to the main list with no
                        // way to retry.
                        self?.showPINGateForEditor(openEditor: openEditor)
                    },
                    onReset: { [weak self] in
                        // PIN was reset (cleared from KVS). Bring the iOS
                        // Settings toggle in line so Settings doesn't lie
                        // about PIN being on, and tell the user what
                        // happened before we open the editor.
                        UserDefaults.standard.set(false, forKey: "pin_enabled")
                        UserDefaults.standard.synchronize()
                        let info = UIAlertController(
                            title: "PIN Cleared",
                            message: "Your PIN was reset and is now off. Re-enable it any time in Settings → iInteract → Enable PIN.",
                            preferredStyle: .alert
                        )
                        info.addAction(UIAlertAction(title: "Open Editor", style: .default) { _ in
                            openEditor()
                        })
                        self?.topmostPresenter().present(info, animated: true)
                    }
                )
            }
        ) {
            openEditor()
        }
    }

    // Built-ins use the storyboard's PanelViewController (ShowPanel segue);
    // user panels go to the programmatic CustomPanelViewController instead.
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        guard identifier == "ShowPanel",
              let cell = sender as? UITableViewCell,
              let indexPath = tableView.indexPath(for: cell) else {
            return true
        }
        let panel = panels[indexPath.row]
        if panel.isBuiltIn { return true }

        let custom = CustomPanelViewController(panel: panel,
                                               voiceEnabled: voiceEnabled,
                                               voiceStyle: voiceStyle)
        navigationController?.pushViewController(custom, animated: true)
        return false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return panels.count
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
 
        // Table view cells are reused and should be dequeued using a cell identifier.
        let cellIdentifier = "FeelingTableViewCell"

        //get panel for the selected cell
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! FeelingTableViewCell
        let panel = panels[(indexPath as NSIndexPath).row]

        //update the cell
        cell.panelTitle.text = panel.title
        cell.backgroundColor = panel.color

        return cell
    }
    

    //new to review this when we add rows
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        //scale the cells to use the whole view
        let numberRows = panels.count
        let heightView = tableView.frame.size.height //this actually returns the height of the screen so we have to subtract StatusBar and NavBar
        let navBarHeight = self.navigationController?.navigationBar.frame.size.height
        let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        lazy var statusBarHeight = window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0

        let heightScrollView = heightView - navBarHeight! - statusBarHeight

        let heightOfCell = heightScrollView/CGFloat(numberRows)
        return heightOfCell
    }


    /*
    // Override to support conditional editing of the table view.
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(tableView: UITableView, moveRowAtIndexPath fromIndexPath: NSIndexPath, toIndexPath: NSIndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        
        if segue.identifier == "ShowPanel" {
            
            let panelViewController = segue.destination as! PanelViewController
            
            // Get the cell that generated this segue.
            if let cell = sender as? FeelingTableViewCell {
                let indexPath               = tableView.indexPath(for: cell)!
                let selectedPanel           = panels[(indexPath as NSIndexPath).row]
                panelViewController.panel   = selectedPanel

                //make the title size/font match on the list ant the panel
                panelViewController.font    = cell.panelTitle.font
                
                //setup the voice
                panelViewController.voiceEnabled    = self.voiceEnabled
                panelViewController.voiceStyle      = self.voiceStyle
            }

        }
        else if segue.identifier == "AddPanel" {
            
        }

    }
    
    // MARK: - Settings
 
    fileprivate func updateSettings() {
        let userDefaults = UserDefaults.standard
        voiceEnabled = userDefaults.bool(forKey: "voice_enabled")
        voiceStyle = userDefaults.string(forKey: "voice_style")!
        displaySplashScreen = userDefaults.string(forKey: "displaySplashScreen")!

        // Reconcile UserDefaults ↔ iCloud KVS so a Settings.bundle change
        // gets pushed to cloud, and a remote change (already mirrored down by
        // the KVS observer) is what we read here.
        let newMode = PanelStore.shared.reconcileConfigurationMode(defaults: userDefaults)
        let modeChanged = newMode != configurationMode
        configurationMode = newMode

        // Hide the gear when iOS Settings → Hide Configuration is on, so
        // children don't see configuration exists. Parents toggle it off
        // in iOS Settings to bring it back.
        navigationItem.rightBarButtonItem = SettingsView.gearVisible(userDefaults)
            ? configurationButton : nil

        if modeChanged && isViewLoaded {
            loadPanels()
            tableView.reloadData()
            popPushedEditorsIfModeChanged()
        }
    }
  
    @objc func settingsChanged() {
            //note currently if the panel is showing this does not take effect until the close and go back to the main menu this is becuase we currently set this in 'prepareForSegue'
        updateSettings()
    }

    @objc func appDidBecomeActive() {
        // Foreground resume — re-read iOS Settings to catch toggle changes
        // even when the user is currently on a pushed sub-screen.
        // updateSettings() will pop any pushed editor whose mode no longer
        // matches the active one (built into the modeChanged branch).
        applyPendingSettingsActions()
        updateSettings()
    }

    /// If a `PanelListEditorViewController` is sitting on the nav stack with a
    /// mode that no longer matches the active one, pop back to root so the
    /// editor doesn't render with stale mode-aware affordances. Default mode
    /// also has no editor at all, so any open editor must close.
    private func popPushedEditorsIfModeChanged() {
        guard let nav = navigationController else { return }
        let needsPop = nav.viewControllers.contains { vc in
            if let editor = vc as? PanelListEditorViewController {
                return editor.editorMode != configurationMode
            }
            // Custom panel detail and panel/interaction editors only exist in
            // Customize. Drop them if we left Customize.
            if configurationMode != .custom,
               (vc is PanelEditorViewController
                || vc is InteractionEditorViewController
                || vc is CustomPanelViewController
                || vc is TrashViewController) {
                return true
            }
            return false
        }
        if needsPop { nav.popToRootViewController(animated: true) }
    }

    @objc func panelStoreChanged() {
        // Another device pushed a layout/panel change via iCloud KVS.
        // Refresh our list whenever we're showing layout-aware results
        // (configurable applies hide+reorder to built-ins; custom adds
        // user panels). Default ignores the layout entirely.
        if configurationMode != .default {
            loadPanels()
            tableView.reloadData()
        }
    }
    
    // Mark: Splash Screen
    fileprivate func showSplashScreen() {
        let nsObject: AnyObject? = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as AnyObject?
        let appVersion = nsObject as! String

        if displaySplashScreen != appVersion {
            
            //display the screen
            //Create the AlertController
            let actionSheetController: UIAlertController = UIAlertController(title: "Voice Style"
                , message: "Select default voice, you can change it any time under settings."
                , preferredStyle: .alert)
            
            //Create the choices
            let boyVoice: UIAlertAction = UIAlertAction(title: "Boy", style: .default) { action -> Void in
                self.voiceStyle = "boy"
                let userDefaults = UserDefaults.standard
                userDefaults.set( self.voiceStyle , forKey: "voice_style")
                userDefaults.synchronize()
            }
            actionSheetController.addAction(boyVoice)
            let girlVoice: UIAlertAction = UIAlertAction(title: "Girl", style: .default) { action -> Void in
                self.voiceStyle = "girl"
                let userDefaults = UserDefaults.standard
                userDefaults.set( self.voiceStyle , forKey: "voice_style")
                userDefaults.synchronize()
            }
            actionSheetController.addAction(girlVoice)

            //Present the AlertController
            self.present(actionSheetController, animated: true, completion: nil)

            //Remember not to show it again!
            let userDefaults = UserDefaults.standard
            userDefaults.set( appVersion , forKey: "displaySplashScreen")
            userDefaults.synchronize()
        }
    }
}
