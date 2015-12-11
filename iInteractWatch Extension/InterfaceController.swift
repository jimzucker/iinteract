//
//  InterfaceController.swift
//  iInteractWatch Extension
//
//  Created by Jim Zucker on 12/4/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import WatchKit
import Foundation


class InterfaceController: WKInterfaceController {
    
    @IBOutlet var tableView:WKInterfaceTable!
    var panels:[Panel] = [Panel]()
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        panels = Panel.readFromPlist()
    }
    
    override func willActivate() {
        super.willActivate()
        setupTable()
    }
    
    private func setupTable() {

        var rowTypesList = [String]()
        
        for _ in panels {
            rowTypesList.append("PanelRow")
        }
        
        tableView.setRowTypes(rowTypesList)
        
        for var i = 0; i < tableView.numberOfRows; i++ {
            
            let panelRow = tableView.rowControllerAtIndex(i) as! PanelRow
            let panel = panels[i]
            panelRow.button.setTitle(panel.title)
            panelRow.button.setBackgroundColor(panel.color)
        }
        
    }
    
    override func contextForSegueWithIdentifier(segueIdentifier: String, inTable table: WKInterfaceTable, rowIndex: Int) -> AnyObject? {
        return panels[rowIndex]
    }
    
    
}
