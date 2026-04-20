//
//  Panel.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 - 2020
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. 
//

import UIKit
import Foundation


class Panel {
    // MARK: Properties
    
    var title: String
    var color: UIColor
    var interactions = [Interaction]()

    // MARK: Initialization
    
    init(title: String, color: UIColor, interactions: [Interaction]) {
        self.title = title
        self.color = color
        self.interactions = interactions
    }
    
    init( dataDictionary:Dictionary<String,NSObject> ) {
        self.title = dataDictionary["title"] as! String
        
        let RGB   = dataDictionary["color"] as! [String: NSNumber]
        let red   = CGFloat(RGB["red"]!.floatValue)   / 255.0
        let green = CGFloat(RGB["green"]!.floatValue) / 255.0
        let blue  = CGFloat(RGB["blue"]!.floatValue)  / 255.0
        self.color = UIColor(red: red, green: green, blue: blue, alpha: 1.0)

        let interactions = dataDictionary["interactions"] as! [String]
        
        for item in interactions
        {
            self.interactions.append(Interaction(interactionName: item))
        }
    }

    class func readFromPlist() -> [Panel] {
        
        var array = [Panel]()
        let dataPath = Bundle.main.path(forResource: "panels", ofType: "plist")
        
        let plist = NSArray(contentsOfFile: dataPath!)
        
        for line in plist as! [Dictionary<String, NSObject>] {
            let panel = Panel(dataDictionary: line)
            array.append(panel)
        }
        
        return array
    }


}
