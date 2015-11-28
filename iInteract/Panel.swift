//
//  Panel.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import UIKit

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
    


}
