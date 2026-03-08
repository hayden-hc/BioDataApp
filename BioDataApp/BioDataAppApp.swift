//
//  BioDataAppApp.swift
//  BioDataApp
//
//  Created by Hayden C on 3/7/26.
//

import SwiftUI

@main
struct BioDataAppApp: App {
    init() {
            HealthBridge.shared.fetchHistory(daysBack: 90)
            HealthBridge.shared.setup()
        }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


