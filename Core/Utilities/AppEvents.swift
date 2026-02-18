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
    static let plannedWorkoutDeleted = Notification.Name("WRKT.PlannedWorkoutDeleted")
    static let plannedWorkoutsChanged = Notification.Name("WRKT.PlannedWorkoutsChanged")
}

// MARK: - App Lifecycle Tracking

extension UserDefaults {
    private static let cleanShutdownKey = "app.cleanShutdown"
    private static let backgroundTimestampKey = "app.backgroundTimestamp"
    private static let hadActiveWorkoutKey = "app.hadActiveWorkout"
    private static let hasLaunchedBeforeKey = "app.hasLaunchedBefore"

    /// Detects force quit by combining background state + timestamp + active workout status.
    ///
    /// Force quit detection strategy:
    /// 1. When backgrounding WITH active workout, store timestamp
    /// 2. On relaunch, if backgrounded < 5 seconds ago WITH active workout → force quit
    /// 3. Force quit = discard workout (user's strong intent to reset)
    ///
    /// This handles the common case: user force quits and immediately relaunches.
    /// If they wait 5+ seconds, we preserve (safer - maybe checking phone).
    var wasForceQuit: Bool {
        // On first launch, not a force quit
        guard object(forKey: Self.cleanShutdownKey) != nil else {
            return false
        }

        let didBackground = bool(forKey: Self.cleanShutdownKey)
        let hadActiveWorkout = bool(forKey: Self.hadActiveWorkoutKey)

        // If never backgrounded, it was a crash (not force quit)
        guard didBackground else {
            return false
        }

        // If no active workout when backgrounded, not relevant to force quit detection
        guard hadActiveWorkout else {
            return false
        }

        // Check timestamp - if backgrounded < 5 seconds ago with active workout, likely force quit
        if let backgroundTimestamp = object(forKey: Self.backgroundTimestampKey) as? Date {
            let timeSinceBackground = Date().timeIntervalSince(backgroundTimestamp)

            // If backgrounded < 5 seconds ago with active workout → force quit
            if timeSinceBackground < 5.0 {
                return true
            }
        }

        return false
    }

    /// Track when app backgrounds with active workout
    func markBackgrounded(hasActiveWorkout: Bool) {
        set(true, forKey: Self.cleanShutdownKey)
        set(hasActiveWorkout, forKey: Self.hadActiveWorkoutKey)
        set(Date(), forKey: Self.backgroundTimestampKey)
    }

    /// Track when app becomes active
    func markActive() {
        set(false, forKey: Self.cleanShutdownKey)
        set(false, forKey: Self.hadActiveWorkoutKey)
    }

    /// Legacy property name - deprecated
    @available(*, deprecated, message: "Use wasForceQuit or markBackgrounded/markActive")
    var didExitCleanly: Bool {
        get { !wasForceQuit }
        set { set(newValue, forKey: Self.cleanShutdownKey) }
    }

    /// Legacy property name - deprecated
    @available(*, deprecated, message: "Use wasForceQuit")
    var didReachBackground: Bool {
        get { !wasForceQuit }
        set { set(newValue, forKey: Self.cleanShutdownKey) }
    }

    /// Mark that the app has launched at least once
    func markAppLaunched() {
        if !bool(forKey: Self.hasLaunchedBeforeKey) {
            set(true, forKey: Self.hasLaunchedBeforeKey)
        }
    }
}
