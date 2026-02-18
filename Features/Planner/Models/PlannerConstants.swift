//
//  PlannerConstants.swift
//  WRKT
//
//  Centralized constants for the Planner feature

import Foundation

enum PlannerConstants {

    // MARK: - Workflow Steps

    enum Steps {
        /// Total number of steps in the planner carousel
        static let total = 6
    }

    // MARK: - Timing

    enum Timing {
        /// Delay before auto-advancing to next step (seconds)
        static let autoAdvanceDelay: TimeInterval = 0.4

        /// Debounce delay for search input (milliseconds)
        static let searchDebounceMs = 300
    }

    // MARK: - Exercise Limits

    enum ExerciseLimits {
        /// Minimum exercises per workout part
        static let minPerPart = 3

        /// Maximum exercises per workout part
        static let maxPerPart = 10

        /// Trigger point for pagination (load more when N items from end)
        static let paginationTrigger = 10
    }

    // MARK: - Custom Split Limits

    enum CustomSplit {
        /// Maximum length for split name
        static let maxNameLength = 30

        /// Minimum number of parts in a split
        static let minParts = 2

        /// Maximum number of parts in a split
        static let maxParts = 4

        /// Maximum number of custom splits a user can create
        static let maxCustomSplits = 20
    }

    // MARK: - Training Frequency

    enum TrainingFrequency {
        /// Minimum training days per week
        static let minDaysPerWeek = 3

        /// Maximum training days per week
        static let maxDaysPerWeek = 6

        /// Days in a week
        static let daysInWeek = 7
    }

    // MARK: - Program Duration

    enum ProgramDuration {
        /// Minimum program length in weeks
        static let minWeeks = 1

        /// Maximum program length in weeks
        static let maxWeeks = 52

        /// Default program length in weeks
        static let defaultWeeks = 8

        /// Deload frequency (every N weeks)
        static let deloadFrequency = 4
    }
}
