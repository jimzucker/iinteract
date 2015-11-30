//
//  Interaction.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//


import UIKit
import AVFoundation

class Interaction {
    
    // MARK: Properties
    var picture: UIImage?
    var boySound: NSURL?
    var girlSound: NSURL?

    var audioPlayer : AVAudioPlayer?

    //convience method for default interactions
    init(interactionName: String) {
        
        self.picture = UIImage(named: interactionName)
        
/*
        
        let docsPath = NSBundle.mainBundle().resourcePath! + "/sounds"
        print(docsPath)
        let fileManager = NSFileManager.defaultManager()
        
        do {
            let docsArray = try fileManager.contentsOfDirectoryAtPath(docsPath)
            print(docsArray)
        } catch {
            print(error)
        }

        let xx = NSBundle.mainBundle().pathForResource("boy_" + interactionName , ofType: "mp3", inDirectory: "sounds" )

        print(xx)
        let url = NSURL.fileURLWithPath(xx!)
        print(url)

        
        do {
            try  audioPlayer = AVAudioPlayer(contentsOfURL: url)
            print("Created Audio Play")

        }
        catch {
            print(error)
        }
*/
        
        if let path = NSBundle.mainBundle().pathForResource("boy_" + interactionName , ofType: "mp3", inDirectory: "sounds" ) {
            self.boySound = NSURL.fileURLWithPath(path)
/*
            do {
                try  audioPlayer = AVAudioPlayer(contentsOfURL: self.boySound!)
                audioPlayer?.prepareToPlay()
                print("Created Audio Play")
                audioPlayer!.play()
 
            }
            catch {
                print(error)
            }
*/
            
        }
        else {
            self.boySound = nil
        }


        
    }
    

    init(picture: UIImage, boySound: NSURL?, girlSound: NSURL?) {
        self.picture = picture
        self.boySound = boySound
        self.girlSound = girlSound
    }
}
