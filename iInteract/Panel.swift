//
//  Panel.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
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
        self.color = UIColor(colorLiteralRed: red/255.0, green: green/255.0, blue: blue/255.0, alpha: 1.0)
        
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
