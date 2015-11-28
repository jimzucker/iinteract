//
//  AppDelegate.swift
//  iInteract
//
//  Created by Jim Zucker on 11/17/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        defaultSettings()
        
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


        // MARK - Settings
    
        //registerDefaults - will only update values that where not previously set so it is safe to call everytime we launch the application
        // Reference  - http://oleb.net/blog/2014/02/nsuserdefaults-handling-default-values/
    private func defaultSettings() {
        let userDefaults = NSUserDefaults.standardUserDefaults()
        let appDefaults = [
            "voice_enabled" : "YES"
            , "voice_style" : "girl"
            , "configuration_enabled" : "NO"
            , "displaySplashScreen" : "0.0"
        ]
        userDefaults.registerDefaults(appDefaults)
    }

}

