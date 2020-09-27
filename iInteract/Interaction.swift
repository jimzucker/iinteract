//
//  Interaction.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. */
//


import UIKit

class Interaction {
    
    // MARK: Properties
    var name: String?
    var picture: UIImage?
    var boySound: URL?
    var girlSound: URL?

    //convience method for default interactions
    init(interactionName: String) {
        name = interactionName
        
        self.picture = UIImage(named: name!)

            //set boy and girl sounds
        if let path = Bundle.main.path(forResource: "boy_" + name! , ofType: "mp3", inDirectory: "sounds" ) {
            self.boySound = URL(fileURLWithPath: path)
        }
        
        if let path = Bundle.main.path(forResource: "girl_" + name! , ofType: "mp3", inDirectory: "sounds" ) {
            self.girlSound = URL(fileURLWithPath: path)
        }
    }
    

    init(interactionName: String, picture: UIImage, boySound: URL?, girlSound: URL?) {
        self.name = interactionName
        self.picture = picture
        self.boySound = boySound
        self.girlSound = girlSound
    }
}
