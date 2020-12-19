//
//  FeelingTableViewController.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 - 2020
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
    var voiceEnabled        : Bool      = true
    var voiceStyle          : String    = "girl"
    var enableConfiguration : Bool      = false
    
    //dislay splash screen 1 time then disable it by setting a preference, we use an int so we can show newer splash screens, it will be set to the current version # once it shows
    var displaySplashScreen : String     = ""
    
   fileprivate func loadPanels() {
        panels = Panel.readFromPlist()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

            //enable/disable configuration
        configurationButton = navigationItem.rightBarButtonItem
        if !enableConfiguration {
            navigationItem.rightBarButtonItem = nil
        }
        
        //register for settings
        NotificationCenter.default.addObserver(self, selector: #selector(FeelingTableViewController.settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
  
        //update settings
        updateSettings()
        
        //show the preferences
//        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
        
        //load sample data
        loadPanels()
        
        //show the splash screen if this is a new version
        showSplashScreen()
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
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
        let statusBarHeight = self.topLayoutGuide.length-(self.navigationController?.navigationBar.frame.height)!
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
        enableConfiguration = userDefaults.bool(forKey: "configuration_enabled")
        displaySplashScreen = userDefaults.string(forKey: "displaySplashScreen")!
        
            //show hide the configuration buttons
        if !enableConfiguration {
            navigationItem.rightBarButtonItem = nil
        } else if navigationItem.rightBarButtonItem == nil && configurationButton != nil {
            navigationItem.rightBarButtonItem = configurationButton
        }

    }
  
    @objc func settingsChanged() {
            //note currently if the panel is showing this does not take effect until the close and go back to the main menu this is becuase we currently set this in 'prepareForSegue'
        updateSettings()
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
