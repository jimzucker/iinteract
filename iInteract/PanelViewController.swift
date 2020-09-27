
//
//  PanelViewController.swift
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
import AVFoundation

class PanelViewController: UIViewController {

    // MARK: Properties
    @IBOutlet weak var panelTitle: UITextField!
    
    //navigation controls
    @IBOutlet weak var panelNavigation: UINavigationItem!
    @IBOutlet weak var cancel: UIBarButtonItem!
    @IBOutlet weak var save: UIBarButtonItem!
    @IBOutlet var panelView: UIView!

    @IBOutlet weak var Button1: UIImageView!
    @IBOutlet weak var Button2: UIImageView!
    @IBOutlet weak var Button3: UIImageView!
    @IBOutlet weak var Button4: UIImageView!
    
    @IBOutlet weak var interactionButton: UIImageView!
    
        //panel to display
    var panel: Panel?
    var buttons : [UIImageView] = []
    var audioPlayer : AVAudioPlayer?

        //runtime attributes from main screen
    var font : UIFont! = nil
    var voiceEnabled : Bool = true
    var voiceStyle : String = "girl"

        //constants for visuals
    let hidden : CGFloat = 0.0
    let visible : CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        if buttons.count < 1 {
            buttons = [ Button1, Button2, Button3, Button4 ]
        }
        
        // Set up views if editing an existing Meal.
        if let panel = panel {
            panelTitle.text = panel.title + " ..."
            panelTitle.backgroundColor = panel.color
            panelTitle.font = self.font
            self.panelView.backgroundColor = panel.color
            
            //disable everything
            for index in 0 ..< buttons.count {
                buttons[index].isUserInteractionEnabled = false
            }

            let numButtons = panel.interactions.count

            for index in 0 ..< numButtons {
                let btn = buttons[index]
                btn.image = panel.interactions[index].picture
                btn.isUserInteractionEnabled = true
            }
            
            //Hide the buttons & title we need for a 'new'
            navigationItem.title = nil
            navigationItem.rightBarButtonItem = nil
            navigationItem.leftBarButtonItem = nil

            //hide the interaction button
            interactionButton.alpha = 0

        } else {
            //     we are doing a new
        }

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: Actions
    @IBAction func cancel(_ sender: UIBarButtonItem) {
        
        // Depending on style of presentation (modal or push presentation), this view controller needs to be dismissed in two different ways.
        let isPresentingInAddMealMode = presentingViewController is UINavigationController
        if isPresentingInAddMealMode {
            dismiss(animated: true, completion: nil)
        } else {
            navigationController!.popViewController(animated: true)
        }

    }
    
    
    @IBAction func selectInteraction(_ recongnizer: UITapGestureRecognizer) {
        var duration = 1.0      //min duration for a transiation

        if let button: UIImageView = recongnizer.view as! UIImageView? {
            
            //disable user interaction so it is not dismissed before the voice finishes.
            button.isUserInteractionEnabled = false
            
            //set the image to display
            interactionButton.alpha = hidden
            interactionButton.image = button.image

                //if the voice is enabled load it
            if self.voiceEnabled {
                let index = buttons.firstIndex(of: button)
                do {
                        //ensure we cleaned up the last time we ran
                    if audioPlayer != nil {
                        audioPlayer?.stop()
                        audioPlayer = nil
                    }
                    
                        //create the new voice
                    var voiceSelected : URL?
                    if self.voiceStyle == "girl" {
                        voiceSelected =  panel!.interactions[index!].girlSound as URL?
                    } else {
                        voiceSelected =  panel!.interactions[index!].boySound as URL?
                    }
                    
                    if voiceSelected != nil {
                        
                        try audioPlayer = AVAudioPlayer(contentsOf: voiceSelected!)

                            //get it ready to play and figure out the duration (if we dont do the prepare duration returns 0)
                        audioPlayer?.prepareToPlay()
                        if let recordingDuration = audioPlayer?.duration , recordingDuration > duration {
                            duration = recordingDuration
                        }
                        
                        //ok now play it
                        audioPlayer!.play()
                    }
                    else {
                        print("Error sound not found: " + self.voiceStyle)
                    }
                    
                } catch {
                    print("Error creating AVAudioPlayer for: "  + self.voiceStyle)
                }
            }

                //do the animation, syncronized with the audio
            UIView.animate(withDuration: duration, delay: 0.0, options: UIView.AnimationOptions.curveEaseOut, animations: {
                self.interactionButton.alpha = self.visible
                button.isUserInteractionEnabled = true
                }, completion: nil)
        }
        
    }
    
    @IBAction func  hideInteraction(_ recongnizer: UITapGestureRecognizer) {
        let duration = 1.0
        
        UIView.animate(withDuration: duration, delay: 0.0, options: UIView.AnimationOptions.curveEaseOut, animations: {
            self.interactionButton.alpha = self.hidden
                }, completion: nil)
    }

}


