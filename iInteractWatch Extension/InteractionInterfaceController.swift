//
//  InteractionInterfaceController.swift
//  iInteract
//
//  Created by Jim Zucker on 12/8/15.
//  Copyright © 2015 
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. */
//

import WatchKit
import Foundation


class InteractionInterfaceController: WKInterfaceController {

    @IBOutlet var InteractionButton: WKInterfaceButton!
    @IBOutlet var backgroundGroup: WKInterfaceGroup!
    
   // var player : WKAudioFilePlayer?
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
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
        pop()
    }
}
