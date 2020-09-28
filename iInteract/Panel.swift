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
        
        let RGB     : Dictionary<String,float_t> = dataDictionary["color"] as! Dictionary<String,float_t>
        let red     : float_t = RGB["red"]!
        let green   : float_t = RGB["green"]!
        let blue    : float_t = RGB["blue"]!
        
        //updated for swift 4.0 see:
        //    https://stackoverflow.com/questions/45361704/initcolorliteralred-green-blue-alpha-deprecated-in-swift-4/46350529#46350529
        self.color = UIColor(displayP3Red: CGFloat(red/255.0), green: CGFloat(green/255.0), blue: CGFloat(blue/255.0), alpha: 1.0)

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
