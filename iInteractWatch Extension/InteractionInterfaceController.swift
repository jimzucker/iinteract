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
    
   // var player : WKAudioFilePlayer?
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        // Configure interface objects here.
        let params = context as? [AnyObject]
        
        let interaction = params![0] as? Interaction
        let picture = interaction?.picture
        InteractionButton.setBackgroundImage(picture)

        let color = params![1] as? UIColor
        backgroundGroup.setBackgroundColor(color)
       
/* sound seems to need a bluetooth headset
  
        let sound = interaction?.boySound
        if sound != nil {
            let asset = WKAudioFileAsset(URL: sound!)
            let playerItem = WKAudioFilePlayerItem(asset: asset)
            player = WKAudioFilePlayer(playerItem: playerItem)
            player!.play()
        }

*/
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    @IBAction func cancel() {
        popController()
    }
}
