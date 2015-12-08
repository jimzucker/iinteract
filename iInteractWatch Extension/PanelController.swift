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
    @IBOutlet var Button1: WKInterfaceImage!
    @IBOutlet var Button2: WKInterfaceImage!
    @IBOutlet var Button3: WKInterfaceImage!
    @IBOutlet var Button4: WKInterfaceImage!
    @IBOutlet var interactionButton: WKInterfaceImage!
    
    
    var buttons = [WKInterfaceImage]()

    //Mark :  Functions
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        buttons = [self.Button1,self.Button2,self.Button3,self.Button4]
        interactionButton.setHidden(true)
        
        for button in buttons {
            button.setHidden(true)
        }
        
        if self.Button1 != nil {
            // Configure interface objects here.
            let panel = context as! Panel
            var i = 0
            for interaction in panel.interactions {
                let button = buttons[i++]
                button.setHidden(false)
                button.setImage(interaction.picture)
            }
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
    
    private func showSplashScreen() {
        interactionButton.setHidden(true)
    }
    
    private func hideSplashScreen() {
        interactionButton.setHidden(false)
    }

}
