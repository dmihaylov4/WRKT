//
//  AppEvents.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 07.10.25.
//

import Foundation

extension Notification.Name {
    static let openLiveWorkoutTab = Notification.Name("WRKT.OpenLiveWorkoutTab")
    static let presentLiveWorkoutSheet = Notification.Name("WRKT.PresentLiveWorkoutSheet")
}

// MARK: - App Lifecycle Tracking

extension UserDefaults {
    private static let cleanShutdownKey = "app.cleanShutdown"
    private static let hasLaunchedBeforeKey = "app.hasLaunchedBefore"

    /// Tracks whether the app exited cleanly (backgrounded) or was force quit/crashed.
    /// - `true`: App went to background normally (clean exit)
    /// - `false`: App is currently running or was force quit/crashed
    /// - Returns `true` on first launch to avoid false positives
    var didExitCleanly: Bool {
        get {
            // On first launch, return true (no previous session to check)
            guard object(forKey: Self.cleanShutdownKey) != nil else {
                return true
            }
            return bool(forKey: Self.cleanShutdownKey)
        }
        set {
            set(newValue, forKey: Self.cleanShutdownKey)
        }
    }

    /// Mark that the app has launched at least once
    func markAppLaunched() {
        if !bool(forKey: Self.hasLaunchedBeforeKey) {
            set(true, forKey: Self.hasLaunchedBeforeKey)
        }
    }
}
