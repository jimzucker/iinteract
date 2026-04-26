//
//  InterfaceController.swift
//  iInteractWatch Extension
//
//  Created by Jim Zucker on 12/4/15.
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
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
        loadPanels()
    }

    override func willActivate() {
        super.willActivate()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelOrderChanged),
            name: ExtensionDelegate.didChangeNotification,
            object: nil
        )
        setupTable()
    }

    override func willDisappear() {
        super.willDisappear()
        NotificationCenter.default.removeObserver(self, name: ExtensionDelegate.didChangeNotification, object: nil)
    }

    @objc func panelOrderChanged() {
        loadPanels()
        setupTable()
    }

    /// Reads the bundled built-ins, then applies the iPhone's most recent
    /// visibility/order push (if any). Falls back to bundle order on a fresh
    /// watch install or when the iPhone hasn't sent anything yet.
    private func loadPanels() {
        let bundled = Panel.readFromPlist()
        guard let titles = UserDefaults.standard.array(forKey: ExtensionDelegate.storageKey) as? [String] else {
            panels = bundled
            return
        }
        let byTitle = Dictionary(uniqueKeysWithValues: bundled.map { ($0.title, $0) })
        panels = titles.compactMap { byTitle[$0] }
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
