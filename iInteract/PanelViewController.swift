
//
//  PanelViewController.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
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
                        
            let numButtons = panel.interactions.count

            for var index = 0; index < numButtons; ++index {
                buttons[index].image = panel.interactions[index].picture
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
    @IBAction func cancel(sender: UIBarButtonItem) {
        
        // Depending on style of presentation (modal or push presentation), this view controller needs to be dismissed in two different ways.
        let isPresentingInAddMealMode = presentingViewController is UINavigationController
        if isPresentingInAddMealMode {
            dismissViewControllerAnimated(true, completion: nil)
        } else {
            navigationController!.popViewControllerAnimated(true)
        }

    }
    
    
    @IBAction func selectInteraction(recongnizer: UITapGestureRecognizer) {
        var duration = 1.0      //min duration for a transiation
        let delay = 0.5         //delay % of calculated duration
        
        if let button: UIImageView = (recongnizer.view as! UIImageView) {
            
            //set the image to display
            interactionButton.alpha = hidden
            interactionButton.image = button.image

                //if the voice is enabled load it
            if self.voiceEnabled {
                let index = buttons.indexOf(button)
                do {
                        //ensure we cleaned up the last time we ran
                    if audioPlayer != nil {
                        audioPlayer?.stop()
                        audioPlayer = nil
                    }
                    
                        //create the new voice
                    if self.voiceStyle == "girl" {
                        try audioPlayer = AVAudioPlayer(contentsOfURL: panel!.interactions[index!].girlSound!)
                    } else {
                        try audioPlayer = AVAudioPlayer(contentsOfURL: panel!.interactions[index!].boySound!)
                    }
                    
                        //get it ready to play and figure out the duration (if we dont do the prepare duration returns 0)
                    audioPlayer?.prepareToPlay()
                    if let recordingDuration = audioPlayer?.duration where recordingDuration > duration {
                        duration = recordingDuration
                    }
                    duration -= (duration * delay)
                    
                        //ok now play it
                    audioPlayer!.play()
                    
                } catch {
                    print("Error playing sound")
                }
            }


                //do the animation, syncronized with the audio
            UIView.animateWithDuration(duration, delay: 0.0, options: UIViewAnimationOptions.CurveEaseOut, animations: {
                self.interactionButton.alpha = self.visible
                }, completion: nil)

        }
        
    }
    
    @IBAction func  hideInteraction(recongnizer: UITapGestureRecognizer) {
        let duration = 1.0
        
        UIView.animateWithDuration(duration, delay: 0.0, options: UIViewAnimationOptions.CurveEaseOut, animations: {
            self.interactionButton.alpha = self.hidden
                }, completion: nil)
    }

}

