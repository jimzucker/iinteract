//
//  InterfaceController.swift
//  iInteractWatch Extension
//
//  Created by Jim Zucker on 12/4/15.
//  Copyright © 2015 - 2020
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/. 
//

import WatchKit
import Foundation


class InterfaceController: WKInterfaceController {
    
    @IBOutlet var tableView:WKInterfaceTable!
    var panels:[Panel] = [Panel]()
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        panels = Panel.readFromPlist()
    }
    
    override func willActivate() {
        super.willActivate()
        setupTable()
    }
    
    fileprivate func setupTable() {

        var rowTypesList = [String]()
        
        for _ in panels {
            rowTypesList.append("PanelRow")
        }
        
        tableView.setRowTypes(rowTypesList)
        
        for i in 0 ..< tableView.numberOfRows {
            
            let panelRow = tableView.rowController(at: i) as! PanelRow
            let panel = panels[i]
            panelRow.button.setTitle(panel.title)
            panelRow.button.setBackgroundColor(panel.color)
        }
        
    }
    
    override func contextForSegue(withIdentifier segueIdentifier: String, in table: WKInterfaceTable, rowIndex: Int) -> Any? {
        return panels[rowIndex]
    }
    
    
}
