//
//  PanelController.swift
//  iInteract
//
//  Created by Jim Zucker on 12/7/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import WatchKit
import Foundation


class PanelController: WKInterfaceController {

    //Mark : Properties
    @IBOutlet var PanelVerticalGroup: WKInterfaceGroup!
    @IBOutlet var PanelTitle: WKInterfaceLabel!
    @IBOutlet var Button1: WKInterfaceButton!
    @IBOutlet var Button2: WKInterfaceButton!
    @IBOutlet var Button3: WKInterfaceButton!
    @IBOutlet var Button4: WKInterfaceButton!
    
    
    var panel : Panel?
    
    //Mark :  Functions
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        let selectedPanel = context as? Panel

        //if we are already configured skip this ;)
        let buttons = [self.Button1,self.Button2,self.Button3,self.Button4]
        for button in buttons {
            button.setHidden(true)
        }
    
        // Configure interface objects here.
        self.panel = selectedPanel
        PanelVerticalGroup.setBackgroundColor(panel!.color)
        PanelTitle.setText(panel!.title + " ...")
        PanelTitle.setTextColor(UIColor.blackColor())

        var i = 0
        for interaction in panel!.interactions {
            let button = buttons[i++]
            button.setHidden(false)
            button.setBackgroundImage(interaction.picture)
        }

    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
    
    
    override func contextForSegueWithIdentifier(segueIdentifier: String) -> AnyObject? {
        let index = Int(segueIdentifier)
        
        //return the interaction object so we can draw the button etc
        let interaction = panel!.interactions[index!]
        let color = panel!.color
        let params : [AnyObject]? = [interaction,color]
        return params
    }
    
}
