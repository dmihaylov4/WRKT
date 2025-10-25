//
//  RestTimerPreferences.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 20.10.25.
//

import Foundation
import Combine
/// Manages default and per-exercise rest timer preferences
class RestTimerPreferences: ObservableObject {
    static let shared = RestTimerPreferences()

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let defaultCompoundSeconds = "rest_timer_default_compound"
        static let defaultIsolationSeconds = "rest_timer_default_isolation"
        static let perExerciseOverrides = "rest_timer_per_exercise_overrides"
        static let isEnabled = "rest_timer_enabled"
    }

    // MARK: - Published Properties
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    @Published var defaultCompoundSeconds: Int {
        didSet {
            UserDefaults.standard.set(defaultCompoundSeconds, forKey: Keys.defaultCompoundSeconds)
        }
    }

    @Published var defaultIsolationSeconds: Int {
        didSet {
            UserDefaults.standard.set(defaultIsolationSeconds, forKey: Keys.defaultIsolationSeconds)
        }
    }

    // Trigger for view updates when preferences change
    @Published private(set) var lastUpdate = Date()

    // Per-exercise overrides: [exerciseID: seconds]
    private var perExerciseOverrides: [String: Int] {
        didSet {
            if let data = try? JSONEncoder().encode(perExerciseOverrides) {
                UserDefaults.standard.set(data, forKey: Keys.perExerciseOverrides)
            }
            lastUpdate = Date() // Trigger view updates
        }
    }

    // MARK: - Initialization
    private init() {
        // Load from UserDefaults
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.defaultCompoundSeconds = UserDefaults.standard.object(forKey: Keys.defaultCompoundSeconds) as? Int ?? 180 // 3 min
        self.defaultIsolationSeconds = UserDefaults.standard.object(forKey: Keys.defaultIsolationSeconds) as? Int ?? 90 // 90 sec

        if let data = UserDefaults.standard.data(forKey: Keys.perExerciseOverrides),
           let overrides = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.perExerciseOverrides = overrides
        } else {
            self.perExerciseOverrides = [:]
        }
    }

    // MARK: - Public API

    /// Get rest duration for an exercise (checks overrides first, then defaults based on mechanics)
    func restDuration(for exercise: Exercise) -> TimeInterval {
        // Check for per-exercise override first
        if let override = perExerciseOverrides[exercise.id] {
            return TimeInterval(override)
        }

        // Use default based on mechanics
        let isCompound = exercise.mechanic?.lowercased() == "compound"
        let defaultSeconds = isCompound ? defaultCompoundSeconds : defaultIsolationSeconds
        return TimeInterval(defaultSeconds)
    }

    /// Set a custom rest duration for a specific exercise
    func setRestDuration(_ seconds: Int, for exerciseID: String) {
        perExerciseOverrides[exerciseID] = seconds
    }

    /// Remove custom override for an exercise (revert to default)
    func removeOverride(for exerciseID: String) {
        perExerciseOverrides.removeValue(forKey: exerciseID)
    }

    /// Check if exercise has a custom override
    func hasOverride(for exerciseID: String) -> Bool {
        perExerciseOverrides[exerciseID] != nil
    }

    /// Get the override value (if it exists)
    func getOverride(for exerciseID: String) -> Int? {
        perExerciseOverrides[exerciseID]
    }

    /// Reset all overrides
    func resetAllOverrides() {
        perExerciseOverrides.removeAll()
    }

    /// Bulk set rest duration for multiple exercises
    func setRestDuration(_ seconds: Int, for exerciseIDs: [String]) {
        for id in exerciseIDs {
            perExerciseOverrides[id] = seconds
        }
    }
}
