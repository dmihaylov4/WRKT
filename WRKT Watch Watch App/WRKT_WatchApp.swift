//
//  WRKT_WatchApp.swift
//  WRKT Watch Watch App
//
//  Created by Dimitar Mihaylov on 20.11.25.
//

import SwiftUI

@main
struct WRKT_Watch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Root view that observes workout state and switches between views
struct RootView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced

    // Store reference to the observable singletons
    let healthManager = WatchHealthKitManager.shared
    let virtualRunManager = VirtualRunManager.shared

    var body: some View {
        Group {
            if virtualRunManager.showVirtualRunUI {
                VirtualRunView(isLuminanceReduced: isLuminanceReduced)
                    .environment(virtualRunManager)
            } else if healthManager.isWorkoutActive {
                ActiveWorkoutView(isLuminanceReduced: isLuminanceReduced)
            } else {
                SimpleTimerView()
            }
        }
    }
}
