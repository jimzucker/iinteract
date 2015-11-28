//
//  PanelTableViewCell.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import UIKit

class PanelTableViewCell: UITableViewCell {

    
    // MARK: Properties
    @IBOutlet weak var panelTitle: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
