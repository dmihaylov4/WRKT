//
//  OnboardingManager.swift
//  WRKT
//
//  Centralized manager for tracking feature onboarding completion across the app
//

import SwiftUI
import Combine
/// Manages completion state for all feature-specific onboarding tutorials
@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    // MARK: - Feature Tutorial Keys

    /// Body Browse tutorial (Equipment filters → Movement filters → Exercise list)
    @AppStorage("tutorial_body_browse") var hasSeenBodyBrowse = false

    /// Exercise Session tutorial (Sets → Carousels → Presets → Info → Save)
    @AppStorage("tutorial_exercise_session") var hasSeenExerciseSession = false

    /// Calendar view tutorial
    @AppStorage("tutorial_calendar") var hasSeenCalendar = false

    /// Profile stats tutorial
    @AppStorage("tutorial_profile_stats") var hasSeenProfileStats = false

    /// Live workout tutorial
    @AppStorage("tutorial_live_workout") var hasSeenLiveWorkout = false

    // MARK: - Helpers

    /// Reset all tutorials (useful for debugging or user settings)
    func resetAllTutorials() {
        hasSeenBodyBrowse = false
        hasSeenExerciseSession = false
        hasSeenCalendar = false
        hasSeenProfileStats = false
        hasSeenLiveWorkout = false
    }

    /// Mark a specific tutorial as completed
    func complete(_ tutorial: TutorialType) {
        switch tutorial {
        case .bodyBrowse:
            hasSeenBodyBrowse = true
        case .exerciseSession:
            hasSeenExerciseSession = true
        case .calendar:
            hasSeenCalendar = true
        case .profileStats:
            hasSeenProfileStats = true
        case .liveWorkout:
            hasSeenLiveWorkout = true
        }
    }

    private init() {}
}

/// Enumeration of all available tutorials
enum TutorialType {
    case bodyBrowse
    case exerciseSession
    case calendar
    case profileStats
    case liveWorkout
}
