//
//  WorkoutPatternAnalyzer.swift
//  WRKT
//
//  Learns user's typical workout time by analyzing recent workout start times
//

import Foundation
import os

/// Analyzes workout timing patterns to learn user's typical workout schedule
actor WorkoutPatternAnalyzer {
    static let shared = WorkoutPatternAnalyzer()

    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.dmihaylov.wrkt", category: "patterns")

    // UserDefaults keys
    private enum Keys {
        static let learnedWorkoutHour = "learned_workout_hour"
        static let lastPatternAnalysis = "last_pattern_analysis"
        static let workoutHourConfidence = "workout_hour_confidence"
    }

    private init() {}

    // MARK: - Public API

    /// Get learned preferred workout hour (0-23), nil if insufficient data
    func getPreferredWorkoutHour() -> Int? {
        guard hasEnoughConfidence() else { return nil }

        let hour = userDefaults.integer(forKey: Keys.learnedWorkoutHour)

        // Validate hour is in valid range
        guard hour >= 0 && hour <= 23 else { return nil }

        return hour
    }

    /// Analyze recent workouts and update learned pattern
    /// Call this after completing a workout or periodically
    func analyzeAndUpdatePattern(workouts: [CompletedWorkout]) async {
        logger.info("📊 ═══════════════════════════════════════════")
        logger.info("📊 PATTERN ANALYSIS STARTED")
        logger.info("📊 ═══════════════════════════════════════════")
        logger.info("📊 Total workouts passed: \(workouts.count)")

        // Don't re-analyze too frequently (once per day max)
        if let lastAnalysis = userDefaults.object(forKey: Keys.lastPatternAnalysis) as? Date {
            let hoursSince = Date().timeIntervalSince(lastAnalysis) / 3600
            logger.info("📊 Hours since last analysis: \(String(format: "%.1f", hoursSince))")
            guard hoursSince >= 24 else {
                logger.info("📊 Skipping analysis (throttled - less than 24 hours since last)")
                return
            }
        } else {
            logger.info("📊 No previous analysis found - first time analysis")
        }

        // Filter to last 3 months of workouts
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let workoutsInLast3Months = workouts.filter { $0.date >= threeMonthsAgo }
        logger.info("📊 Workouts in last 3 months: \(workoutsInLast3Months.count)")

        // Check how many have startedAt timestamps
        let workoutsWithStartedAt = workoutsInLast3Months.filter { $0.startedAt != nil }
        logger.info("📊 Workouts with startedAt timestamp: \(workoutsWithStartedAt.count)")
        logger.info("📊 Workouts without startedAt (will use completion time): \(workoutsInLast3Months.count - workoutsWithStartedAt.count)")

        // Log first few workouts for debugging
        for (index, workout) in workoutsInLast3Months.prefix(5).enumerated() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let dateStr = dateFormatter.string(from: workout.date)
            if let startedAt = workout.startedAt {
                let startedAtStr = dateFormatter.string(from: startedAt)
                logger.info("📊   Workout \(index + 1): date=\(dateStr), startedAt=\(startedAtStr)")
            } else {
                logger.info("📊   Workout \(index + 1): date=\(dateStr), startedAt=nil (using completion time)")
            }
        }

        // Extract hours from workouts - prefer startedAt, fall back to date (completion time)
        let recentWithTiming = workoutsInLast3Months
            .sorted { $0.date > $1.date }  // Most recent first
            .map { workout -> Int in
                // Use startedAt if available, otherwise use completion time (date)
                let timeToUse = workout.startedAt ?? workout.date
                return Calendar.current.component(.hour, from: timeToUse)
            }

        logger.info("📊 Workouts with valid timing data: \(recentWithTiming.count)")

        // Need at least 5 workouts with timing data
        guard recentWithTiming.count >= 5 else {
            logger.warning("Not enough workout timing data (have \(recentWithTiming.count), need 5)")
            userDefaults.set(0.0, forKey: Keys.workoutHourConfidence)
            return
        }

        // Calculate hour distribution
        var hourCounts: [Int: Int] = [:]
        for hour in recentWithTiming {
            hourCounts[hour, default: 0] += 1
        }

        // Log the distribution for debugging
        let sortedDistribution = hourCounts.sorted { $0.key < $1.key }
        let distributionString = sortedDistribution.map { "\(self.formatHour($0.key)): \($0.value)" }.joined(separator: ", ")
        logger.info("📊 Workout hour distribution: [\(distributionString)]")
        logger.info("📊 Raw workout hours analyzed: \(recentWithTiming.map { self.formatHour($0) }.joined(separator: ", "))")

        // Find mode (most common hour)
        guard let (mostCommonHour, count) = hourCounts.max(by: { $0.value < $1.value }) else {
            logger.warning("Failed to calculate most common hour")
            return
        }

        // Calculate confidence (0.0 to 1.0)
        let confidence = Double(count) / Double(recentWithTiming.count)

        // Log the calculation details
        logger.info("📊 Most common hour: \(self.formatHour(mostCommonHour)) with \(count)/\(recentWithTiming.count) workouts")
        logger.info("📊 Confidence calculation: \(count) ÷ \(recentWithTiming.count) = \(String(format: "%.1f", confidence * 100))%")

        // Only update if confidence >= 30% of workouts at same hour
        if confidence >= 0.3 {
            userDefaults.set(mostCommonHour, forKey: Keys.learnedWorkoutHour)
            userDefaults.set(confidence, forKey: Keys.workoutHourConfidence)
            userDefaults.set(Date(), forKey: Keys.lastPatternAnalysis)

            logger.info("✅ Updated workout pattern: hour=\(self.formatHour(mostCommonHour)), confidence=\(String(format: "%.0f", confidence * 100))% (from \(recentWithTiming.count) workouts)")
        } else {
            logger.info("⚠️ Low confidence (\(String(format: "%.0f", confidence * 100))% < 30%), not updating pattern")
            userDefaults.set(confidence, forKey: Keys.workoutHourConfidence)
        }
    }

    /// Check if we have enough confidence in the learned pattern
    func hasEnoughConfidence() -> Bool {
        let confidence = userDefaults.double(forKey: Keys.workoutHourConfidence)
        return confidence >= 0.3
    }

    /// Get confidence level for display (0.0 to 1.0)
    func getConfidence() -> Double {
        return userDefaults.double(forKey: Keys.workoutHourConfidence)
    }

    /// Reset learned pattern (for testing or user request)
    func resetPattern() {
        userDefaults.removeObject(forKey: Keys.learnedWorkoutHour)
        userDefaults.removeObject(forKey: Keys.lastPatternAnalysis)
        userDefaults.removeObject(forKey: Keys.workoutHourConfidence)
        logger.info("Reset workout pattern learning")
    }

    /// Check if initial analysis is needed (never run before)
    func needsInitialAnalysis() -> Bool {
        return userDefaults.object(forKey: Keys.lastPatternAnalysis) == nil
    }

    /// Force analysis bypassing the 24-hour throttle (for debugging or initial setup)
    func forceAnalyzePattern(workouts: [CompletedWorkout]) async {
        logger.info("📊 FORCE ANALYSIS REQUESTED (bypassing throttle)")

        // Temporarily clear the last analysis date to bypass throttle
        let savedLastAnalysis = userDefaults.object(forKey: Keys.lastPatternAnalysis) as? Date
        userDefaults.removeObject(forKey: Keys.lastPatternAnalysis)

        // Run the analysis
        await analyzeAndUpdatePattern(workouts: workouts)

        // If analysis didn't set a new date (e.g., not enough data), restore the old one
        if userDefaults.object(forKey: Keys.lastPatternAnalysis) == nil, let saved = savedLastAnalysis {
            userDefaults.set(saved, forKey: Keys.lastPatternAnalysis)
        }
    }

    // MARK: - Edge Cases

    /// Handle timezone changes
    /// Call this when app detects timezone change
    func handleTimezoneChange() {
        // Reset pattern - timezone change invalidates learned hours
        resetPattern()
        logger.warning("Timezone changed - reset workout pattern")
    }

    // MARK: - Helpers

    /// Format hour for logging (e.g., "6 PM", "2 PM")
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    /// Log current pattern state (call for debugging)
    func logCurrentPatternState() {
        let hour = userDefaults.integer(forKey: Keys.learnedWorkoutHour)
        let confidence = userDefaults.double(forKey: Keys.workoutHourConfidence)
        let lastAnalysis = userDefaults.object(forKey: Keys.lastPatternAnalysis) as? Date

        logger.info("📊 ═══════════════════════════════════════════")
        logger.info("📊 WORKOUT PATTERN STATE")
        logger.info("📊 ═══════════════════════════════════════════")

        if self.hasEnoughConfidence() {
            logger.info("📊 Learned workout hour: \(self.formatHour(hour))")
        } else {
            logger.info("📊 Learned workout hour: Not set (insufficient confidence)")
        }

        logger.info("📊 Confidence: \(String(format: "%.1f", confidence * 100))%")
        logger.info("📊 Threshold: 30%")
        logger.info("📊 Has enough confidence: \(self.hasEnoughConfidence() ? "Yes" : "No")")

        if let lastAnalysis = lastAnalysis {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            logger.info("📊 Last analysis: \(formatter.string(from: lastAnalysis))")
        } else {
            logger.info("📊 Last analysis: Never")
        }

        logger.info("📊 ═══════════════════════════════════════════")
    }
}
