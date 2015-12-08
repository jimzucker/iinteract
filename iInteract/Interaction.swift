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
    var name: String?
    var picture: UIImage?
    var boySound: NSURL?
    var girlSound: NSURL?

    //convience method for default interactions
    init(interactionName: String) {
        name = interactionName
        
        self.picture = UIImage(named: name!)

            //set boy and girl sounds
        if let path = NSBundle.mainBundle().pathForResource("boy_" + name! , ofType: "mp3", inDirectory: "sounds" ) {
            self.boySound = NSURL.fileURLWithPath(path)
        }
        
        if let path = NSBundle.mainBundle().pathForResource("girl_" + name! , ofType: "mp3", inDirectory: "sounds" ) {
            self.girlSound = NSURL.fileURLWithPath(path)
        }
    }
    

    init(interactionName: String, picture: UIImage, boySound: NSURL?, girlSound: NSURL?) {
        self.name = interactionName
        self.picture = picture
        self.boySound = boySound
        self.girlSound = girlSound
    }
}
