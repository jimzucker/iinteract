//
//  PanelTableViewController.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import UIKit

class PanelTableViewController: UITableViewController {

    // MARK: Properties
    
    
    var panels = [Panel]()
    var configurationButton : UIBarButtonItem?
    
    // MARK: Settings Properties
    var voiceEnabled        : Bool      = true
    var voiceStyle          : String    = "girl"
    var enableConfiguration : Bool      = false
    
    //dislay splash screen 1 time then disable it by setting a preference, we use an int so we can show newer splash screens, it will be set to the current version # once it shows
    var displaySplashScreen : String     = ""
    
   private func loadSamplePanels() {
        
        panels = [
            Panel(title: "I feel"
                , color: UIColor(red: 87.0/255.0, green: 192.0/255.0, blue: 255.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "happy" )
                    , Interaction(interactionName: "sad")
                    , Interaction(interactionName: "angry")]
            )
            
            , Panel(title: "I need"
                , color: UIColor(colorLiteralRed: 255.0/255.0, green: 255.0/255.0, blue: 83.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "drink" )
                    , Interaction(interactionName: "eat")
                    , Interaction(interactionName: "bathroom")
                    , Interaction(interactionName: "break")]
            )
            
            , Panel(title: "I want to"
                , color: UIColor(colorLiteralRed: 253.0/255.0, green: 135.0/255.0, blue: 39.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "tv" )
                    , Interaction(interactionName: "play")
                    , Interaction(interactionName: "book")
                    , Interaction(interactionName: "computer")]
            )
            
            , Panel(title: "I need help"
                , color: UIColor(colorLiteralRed: 251.0/255.0, green: 0.0/255.0, blue: 6.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "headache" )
                    , Interaction(interactionName: "stomach")
                    , Interaction(interactionName: "cut")]
            )
            
            , Panel(title: "Food"
                , color: UIColor(colorLiteralRed: 18.0/255.0, green: 136.0/255.0, blue: 67.0/255.0, alpha: 1.0)
               // , color: UIColor(colorLiteralRed: 11.0/255.0, green: 85.0/255.0, blue: 39.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "breakfast" )
                    , Interaction(interactionName: "lunch")
                    , Interaction(interactionName: "dinner")
                    , Interaction(interactionName: "dessert")]
            )
            
            , Panel(title: "Drink"
                , color: UIColor(colorLiteralRed: 42.0/255.0, green: 130.0/255.0, blue: 255.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "milk" )
                    , Interaction(interactionName: "water")
                    , Interaction(interactionName: "juice")
                    , Interaction(interactionName: "soda")]
            )
            
            , Panel(title: "Snacks"
                , color: UIColor(colorLiteralRed: 88.0/255.0, green: 197.0/255.0, blue: 84.0/255.0, alpha: 1.0)
                , interactions: [Interaction(interactionName: "chips" )
                    , Interaction(interactionName: "cookie")
                    , Interaction(interactionName: "pretzel")
                    , Interaction(interactionName: "fruit")]
            )
            
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()

            //enable/disable configuration
        configurationButton = navigationItem.rightBarButtonItem
        if !enableConfiguration {
            navigationItem.rightBarButtonItem = nil
        }
        
        //register for settings
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "settingsChanged", name: NSUserDefaultsDidChangeNotification, object: nil)
  
        //update settings
        updateSettings()
        
        //show the preferences
//        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
        
        //load sample data
        loadSamplePanels()
        
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

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return panels.count
    }

    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
 
        // Table view cells are reused and should be dequeued using a cell identifier.
        let cellIdentifier = "PanelTableViewCell"

        //get panel for the selected cell
        let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier, forIndexPath: indexPath) as! PanelTableViewCell
        let panel = panels[indexPath.row]

        //update the cell
        cell.panelTitle.text = panel.title
        cell.backgroundColor = panel.color

        return cell
    }
    

    //new to review this when we add rows
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {

        
        //scale the cells to use the whole view
        let numberRows = panels.count
        let heightView = tableView.frame.height - tableView.sectionHeaderHeight - tableView.sectionFooterHeight
        let heightOfCell = heightView/CGFloat(numberRows)

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
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        
        if segue.identifier == "ShowPanel" {
            
            let panelViewController = segue.destinationViewController as! PanelViewController
            
            // Get the cell that generated this segue.
            if let cell = sender as? PanelTableViewCell {
                let indexPath               = tableView.indexPathForCell(cell)!
                let selectedPanel           = panels[indexPath.row]
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
 
    private func updateSettings() {
        let userDefaults = NSUserDefaults.standardUserDefaults()
        voiceEnabled = userDefaults.boolForKey("voice_enabled")
        voiceStyle = userDefaults.stringForKey("voice_style")!
        enableConfiguration = userDefaults.boolForKey("configuration_enabled")
        displaySplashScreen = userDefaults.stringForKey("displaySplashScreen")!
        
            //show hide the configuration buttons
        if !enableConfiguration {
            navigationItem.rightBarButtonItem = nil
        } else if navigationItem.rightBarButtonItem == nil && configurationButton != nil {
            navigationItem.rightBarButtonItem = configurationButton
        }

    }
  
    func settingsChanged() {
            //note currently if the panel is showing this does not take effect until the close and go back to the main menu this is becuase we currently set this in 'prepareForSegue'
        updateSettings()
    }
    
    // Mark: Splash Screen
    private func showSplashScreen() {
        let nsObject: AnyObject? = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"]
        let appVersion = nsObject as! String

        if displaySplashScreen != appVersion {
            
            //display the screen
            //Create the AlertController
            let actionSheetController: UIAlertController = UIAlertController(title: "Voice Style"
                , message: "Select default voice, you can change it any time under settings."
                , preferredStyle: .Alert)
            
            //Create the choices
            let boyVoice: UIAlertAction = UIAlertAction(title: "Boy", style: .Default) { action -> Void in
                self.voiceStyle = "boy"
                let userDefaults = NSUserDefaults.standardUserDefaults()
                userDefaults.setObject( self.voiceStyle , forKey: "voice_style")
                userDefaults.synchronize()
            }
            actionSheetController.addAction(boyVoice)
            let girlVoice: UIAlertAction = UIAlertAction(title: "Girl", style: .Default) { action -> Void in
                self.voiceStyle = "girl"
                let userDefaults = NSUserDefaults.standardUserDefaults()
                userDefaults.setObject( self.voiceStyle , forKey: "voice_style")
                userDefaults.synchronize()
            }
            actionSheetController.addAction(girlVoice)

            //Present the AlertController
            self.presentViewController(actionSheetController, animated: true, completion: nil)

            //Remember not to show it again!
            let userDefaults = NSUserDefaults.standardUserDefaults()
            userDefaults.setObject( appVersion , forKey: "displaySplashScreen")
            userDefaults.synchronize()
        }
    }
}
