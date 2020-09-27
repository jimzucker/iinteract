//
//  iInteractApp.swift
//  iInteractWatch Extension
//
//  Created by Jim Zucker on 9/27/20.
//  Copyright © 2020 Strategic Software Engineering LLC. All rights reserved.
//

import SwiftUI

@main
struct iInteractApp: App {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
            }
        }

        WKNotificationScene(controller: NotificationController.self, category: "myCategory")
    }
}
