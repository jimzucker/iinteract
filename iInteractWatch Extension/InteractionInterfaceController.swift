//
//  InteractionInterfaceController.swift
//  iInteract
//
//  Created by Jim Zucker on 12/8/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import WatchKit
import Foundation


class InteractionInterfaceController: WKInterfaceController {

    @IBOutlet var InteractionButton: WKInterfaceButton!
    @IBOutlet var backgroundGroup: WKInterfaceGroup!
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        // Configure interface objects here.
        let params = context as? [AnyObject]
        
        let interaction = params![0] as? Interaction
        InteractionButton.setBackgroundImage(interaction?.picture)

        let color = params![1] as? UIColor
        backgroundGroup.setBackgroundColor(color)
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

}
