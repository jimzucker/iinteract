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
    var voiceStyle          : String    = "Girl"
    var enableConfiguration : Bool      = false
    
   private func loadSamplePanels() {
        
        panels = [
            Panel(title: "I feel", color: UIColor.blueColor()
                , interactions: [Interaction(interactionName: "happy" )
                    , Interaction(interactionName: "sad")
                    , Interaction(interactionName: "angry")]
            )
            
            , Panel(title: "I need", color: UIColor.greenColor()
                , interactions: [Interaction(interactionName: "drink" )
                    , Interaction(interactionName: "eat")
                    , Interaction(interactionName: "bathroom")
                    , Interaction(interactionName: "break")]
            )
            
            , Panel(title: "I want to", color: UIColor.orangeColor()
                , interactions: [Interaction(interactionName: "tv" )
                    , Interaction(interactionName: "play")
                    , Interaction(interactionName: "book")
                    , Interaction(interactionName: "computer")]
            )
            
            , Panel(title: "I need help", color: UIColor.redColor()
                , interactions: [Interaction(interactionName: "headache" )
                    , Interaction(interactionName: "stomach")
                    , Interaction(interactionName: "cut")]
            )
            
            , Panel(title: "Food", color: UIColor.greenColor()
                , interactions: [Interaction(interactionName: "breakfast" )
                    , Interaction(interactionName: "lunch")
                    , Interaction(interactionName: "dinner")
                    , Interaction(interactionName: "dessert")]
            )
            
            , Panel(title: "Drink", color: UIColor.blueColor()
                , interactions: [Interaction(interactionName: "milk" )
                    , Interaction(interactionName: "water")
                    , Interaction(interactionName: "juice")
                    , Interaction(interactionName: "soda")]
            )
            
            , Panel(title: "Snacks", color: UIColor.greenColor()
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
                let indexPath = tableView.indexPathForCell(cell)!
                let selectedPanel = panels[indexPath.row]
                panelViewController.panel = selectedPanel

                //make the title size/font match on the list ant the panel
                panelViewController.font = cell.panelTitle.font
                
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
    
}
