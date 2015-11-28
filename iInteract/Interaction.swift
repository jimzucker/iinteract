//
//  Interaction.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//


import UIKit

class Interaction {
    
    // MARK: Properties
    var picture: UIImage?
    var boySound: NSURL?
    var girlSound: NSURL?
    
    //convience method for default interactions
    init(interactionName: String) {
        
        self.picture = UIImage(named: interactionName)
        
        if let path = NSBundle.mainBundle().pathForResource("boy_" + interactionName , ofType: "mp3") {
            self.boySound = NSURL.fileURLWithPath(path)
        }
        else {
            self.boySound = nil
        }

        if let path = NSBundle.mainBundle().pathForResource("girl_" + interactionName , ofType: "mp3") {
            self.girlSound = NSURL.fileURLWithPath(path)
        }
        else {
            self.girlSound = nil
        }

    }
    

    init(picture: UIImage, boySound: NSURL?, girlSound: NSURL?) {
        self.picture = picture
        self.boySound = boySound
        self.girlSound = girlSound
    }
}
