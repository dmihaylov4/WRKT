//
//  ExerciseStatsAggregator.swift
//  WRKT
//
//  Service for aggregating and computing exercise statistics from workout history
//

import Foundation
import OSLog

final class ExerciseStatsAggregator {
    private let logger = Logger(subsystem: "com.wrkt.app", category: "ExerciseStats")

    // MARK: - Public API

    /// Compute comprehensive statistics for a specific exercise
    func computeStatistics(
        exerciseID: String,
        exerciseName: String,
        trackingMode: TrackingMode,
        from workouts: [CompletedWorkout]
    ) -> ExerciseStatistics {
        logger.debug("Computing statistics for exercise: \(exerciseName) (ID: \(exerciseID))")

        // Filter workouts that contain this exercise
        let relevantWorkouts = filterWorkoutsContaining(exerciseID: exerciseID, in: workouts)

        guard !relevantWorkouts.isEmpty else {
            logger.info("No history found for exercise: \(exerciseName)")
            return .empty(exerciseID: exerciseID, exerciseName: exerciseName, trackingMode: trackingMode)
        }

        logger.debug("Found \(relevantWorkouts.count) workouts containing this exercise")

        // Build all stats components
        let prs = computePersonalRecords(
            exerciseID: exerciseID,
            trackingMode: trackingMode,
            workouts: relevantWorkouts
        )

        let volumeStats = computeVolumeStatistics(
            exerciseID: exerciseID,
            trackingMode: trackingMode,
            workouts: relevantWorkouts
        )

        let frequencyStats = computeFrequencyStatistics(workouts: relevantWorkouts)

        let timeStats = computeTimeStatistics(
            exerciseID: exerciseID,
            workouts: relevantWorkouts
        )

        let history = buildExerciseHistory(
            exerciseID: exerciseID,
            trackingMode: trackingMode,
            workouts: relevantWorkouts,
            prs: prs
        )

        let progressData = computeProgressData(
            exerciseID: exerciseID,
            trackingMode: trackingMode,
            workouts: relevantWorkouts,
            volumeStats: volumeStats
        )

        logger.info("Successfully computed statistics for \(exerciseName): \(frequencyStats.totalTimesPerformed) sessions, \(volumeStats.totalSets) sets")

        return ExerciseStatistics(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            trackingMode: trackingMode,
            personalRecords: prs,
            volumeStats: volumeStats,
            frequencyStats: frequencyStats,
            timeStats: timeStats,
            history: history,
            progressData: progressData
        )
    }

    // MARK: - Personal Records

    private func computePersonalRecords(
        exerciseID: String,
        trackingMode: TrackingMode,
        workouts: [(workout: CompletedWorkout, entry: WorkoutEntry)]
    ) -> PersonalRecords {
        var bestE1RM: PRRecord?
        var heaviestWeight: PRRecord?
        var mostReps: PRRecord?
        var bestVolume: PRRecord?
        var longestHold: PRRecord?
        var mostRepsBodyweight: PRRecord?

        // Track best values across all workouts
        var maxE1RM: Double = 0
        var maxWeight: (weight: Double, reps: Int, workout: CompletedWorkout)?
        var maxReps: (reps: Int, weight: Double, workout: CompletedWorkout)?
        var maxVolume: (volume: Double, workout: CompletedWorkout)?
        var maxHold: (seconds: Int, workout: CompletedWorkout)?
        var maxBodyweightReps: (reps: Int, setCount: Int, workout: CompletedWorkout)?

        for (workout, entry) in workouts {
            var sessionVolume: Double = 0
            var sessionBodyweightReps: Int = 0  // Track total reps per workout for bodyweight
            var sessionBodyweightSetCount: Int = 0  // Track number of unweighted sets

            for set in entry.sets where set.isCompleted {
                // Volume calculation
                if trackingMode == .weighted {
                    sessionVolume += Double(set.reps) * set.weight
                }

                switch trackingMode {
                case .weighted:
                    // E1RM calculation using Epley formula: weight × (1 + reps/30)
                    if set.weight > 0 && set.reps > 0 {
                        let e1rm = set.weight * (1 + Double(set.reps) / 30.0)
                        if e1rm > maxE1RM {
                            maxE1RM = e1rm
                            bestE1RM = PRRecord(
                                value: e1rm,
                                secondaryValue: set.weight,
                                date: workout.date,
                                workoutID: workout.id,
                                displayText: String(format: "%.1f kg E1RM", e1rm),
                                setCount: nil
                            )
                        }
                    }

                    // Heaviest weight
                    if set.weight > (maxWeight?.weight ?? 0) {
                        maxWeight = (set.weight, set.reps, workout)
                        heaviestWeight = PRRecord(
                            value: set.weight,
                            secondaryValue: Double(set.reps),
                            date: workout.date,
                            workoutID: workout.id,
                            displayText: String(format: "%.1f kg × %d reps", set.weight, set.reps),
                            setCount: nil
                        )
                    }

                    // Most reps at any weight
                    if set.reps > (maxReps?.reps ?? 0) {
                        maxReps = (set.reps, set.weight, workout)
                        mostReps = PRRecord(
                            value: Double(set.reps),
                            secondaryValue: set.weight,
                            date: workout.date,
                            workoutID: workout.id,
                            displayText: "\(set.reps) reps @ \(String(format: "%.1f", set.weight)) kg",
                            setCount: nil
                        )
                    }

                case .timed:
                    if set.durationSeconds > (maxHold?.seconds ?? 0) {
                        maxHold = (set.durationSeconds, workout)
                        longestHold = PRRecord(
                            value: Double(set.durationSeconds),
                            secondaryValue: nil,
                            date: workout.date,
                            workoutID: workout.id,
                            displayText: formatDuration(set.durationSeconds),
                            setCount: nil
                        )
                    }

                case .bodyweight:
                    // For bodyweight exercises, track BOTH weighted and unweighted PRs
                    if set.weight == 0 {
                        // Unweighted bodyweight tracking
                        sessionBodyweightReps += set.reps  // Accumulate total reps for this workout
                        sessionBodyweightSetCount += 1  // Count this set

                        // Track max reps in a single set (kept for compatibility)
                        if set.reps > (maxBodyweightReps?.reps ?? 0) {
                            maxBodyweightReps = (set.reps, 1, workout)  // Single set PR
                            mostRepsBodyweight = PRRecord(
                                value: Double(set.reps),
                                secondaryValue: nil,
                                date: workout.date,
                                workoutID: workout.id,
                                displayText: "\(set.reps) reps (unweighted)",
                                setCount: 1
                            )
                        }
                    } else {
                        // Weighted bodyweight tracking (e.g., weighted pull-ups)
                        // Track just like weighted exercises - E1RM, heaviest weight, most reps
                        let e1rm = set.weight * (1 + Double(set.reps) / 30.0)
                        if e1rm > maxE1RM {
                            maxE1RM = e1rm
                            bestE1RM = PRRecord(
                                value: e1rm,
                                secondaryValue: set.weight,
                                date: workout.date,
                                workoutID: workout.id,
                                displayText: String(format: "%.1f kg E1RM", e1rm),
                                setCount: nil
                            )
                        }

                        if set.weight > (maxWeight?.weight ?? 0) {
                            maxWeight = (set.weight, set.reps, workout)
                            heaviestWeight = PRRecord(
                                value: set.weight,
                                secondaryValue: Double(set.reps),
                                date: workout.date,
                                workoutID: workout.id,
                                displayText: String(format: "+%.1f kg × %d reps", set.weight, set.reps),
                                setCount: nil
                            )
                        }

                        if set.reps > (maxReps?.reps ?? 0) {
                            maxReps = (set.reps, set.weight, workout)
                            mostReps = PRRecord(
                                value: Double(set.reps),
                                secondaryValue: set.weight,
                                date: workout.date,
                                workoutID: workout.id,
                                displayText: "\(set.reps) reps @ +\(String(format: "%.1f", set.weight)) kg",
                                setCount: nil
                            )
                        }
                    }

                case .distance:
                    break // Future implementation
                }
            }

            // Best total reps in a single workout for bodyweight exercises (only unweighted sets)
            if trackingMode == .bodyweight && sessionBodyweightReps > 0 && sessionBodyweightReps > (maxBodyweightReps?.reps ?? 0) {
                let avgRepsPerSet = sessionBodyweightReps / max(1, sessionBodyweightSetCount)
                maxBodyweightReps = (sessionBodyweightReps, sessionBodyweightSetCount, workout)
                mostRepsBodyweight = PRRecord(
                    value: Double(sessionBodyweightReps),
                    secondaryValue: nil,
                    date: workout.date,
                    workoutID: workout.id,
                    displayText: "\(sessionBodyweightSetCount)×\(avgRepsPerSet) (\(sessionBodyweightReps) total reps, unweighted)",
                    setCount: sessionBodyweightSetCount
                )
            }

            // Best volume in a single workout
            if trackingMode == .weighted && sessionVolume > (maxVolume?.volume ?? 0) {
                maxVolume = (sessionVolume, workout)
                bestVolume = PRRecord(
                    value: sessionVolume,
                    secondaryValue: nil,
                    date: workout.date,
                    workoutID: workout.id,
                    displayText: String(format: "%.0f kg total", sessionVolume),
                    setCount: nil
                )
            }
        }

        return PersonalRecords(
            bestE1RM: bestE1RM,
            heaviestWeight: heaviestWeight,
            mostReps: mostReps,
            bestVolume: bestVolume,
            longestHold: longestHold,
            mostRepsBodyweight: mostRepsBodyweight
        )
    }

    // MARK: - Volume Statistics

    private func computeVolumeStatistics(
        exerciseID: String,
        trackingMode: TrackingMode,
        workouts: [(workout: CompletedWorkout, entry: WorkoutEntry)]
    ) -> VolumeStatistics {
        var totalVolume: Double = 0
        var totalSets: Int = 0
        var totalReps: Int = 0
        var totalWorkTime: TimeInterval = 0
        var totalWeightSum: Double = 0
        var weightedSetCount: Int = 0
        var volumeByWeek: [Date: (volume: Double, sessions: Int, sets: Int)] = [:]
        var weightFrequency: [Double: Int] = [:]

        let calendar = Calendar.current

        for (workout, entry) in workouts {
            let weekStart = calendar.startOfWeek(for: workout.date)
            var sessionVolume: Double = 0
            var sessionSets: Int = 0

            for set in entry.sets where set.isCompleted {
                totalSets += 1
                sessionSets += 1

                switch trackingMode {
                case .weighted:
                    let setVolume = Double(set.reps) * set.weight
                    sessionVolume += setVolume
                    totalVolume += setVolume
                    totalReps += set.reps
                    totalWeightSum += set.weight
                    weightedSetCount += 1

                    // Track weight distribution (round to nearest 2.5kg for bucketing)
                    let bucketedWeight = round(set.weight / 2.5) * 2.5
                    weightFrequency[bucketedWeight, default: 0] += 1

                case .timed:
                    totalWorkTime += TimeInterval(set.durationSeconds)

                case .bodyweight:
                    totalReps += set.reps

                case .distance:
                    break // Future implementation
                }
            }

            // Update weekly aggregates
            var weekData = volumeByWeek[weekStart] ?? (volume: 0, sessions: 0, sets: 0)
            weekData.volume += sessionVolume
            weekData.sessions += 1
            weekData.sets += sessionSets
            volumeByWeek[weekStart] = weekData
        }

        // Convert weekly data to array and sort
        let weeklyVolumeArray = volumeByWeek.map { weekStart, data in
            WeeklyVolume(
                weekStart: weekStart,
                volume: data.volume,
                sessions: data.sessions,
                sets: data.sets
            )
        }.sorted { $0.weekStart < $1.weekStart }

        // Convert weight distribution to array
        let weightBuckets = weightFrequency.map { weight, frequency in
            WeightBucket(
                weight: weight,
                frequency: frequency,
                percentage: Double(frequency) / Double(totalSets) * 100
            )
        }.sorted { $0.weight < $1.weight }

        let averageWeight = weightedSetCount > 0 ? totalWeightSum / Double(weightedSetCount) : 0
        let averageVolumePerSession = workouts.count > 0 ? totalVolume / Double(workouts.count) : 0

        return VolumeStatistics(
            totalVolume: totalVolume,
            averageVolumePerSession: averageVolumePerSession,
            totalSets: totalSets,
            totalReps: totalReps,
            totalWorkTime: totalWorkTime,
            volumeByWeek: weeklyVolumeArray,
            averageWeight: averageWeight,
            weightDistribution: weightBuckets
        )
    }

    // MARK: - Frequency Statistics

    private func computeFrequencyStatistics(
        workouts: [(workout: CompletedWorkout, entry: WorkoutEntry)]
    ) -> FrequencyStatistics {
        let sortedWorkouts = workouts.sorted { $0.workout.date < $1.workout.date }

        let firstPerformed = sortedWorkouts.first?.workout.date
        let lastPerformed = sortedWorkouts.last?.workout.date
        let totalTimesPerformed = workouts.count

        // Calculate average per week
        var averagePerWeek: Double = 0
        if let first = firstPerformed, let last = lastPerformed {
            let daysBetween = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
            let weeksBetween = max(1, Double(daysBetween) / 7.0)
            averagePerWeek = Double(totalTimesPerformed) / weeksBetween
        }

        // Calculate streaks
        let calendar = Calendar.current
        var weekStarts = Set<Date>()
        for (workout, _) in workouts {
            let weekStart = calendar.startOfWeek(for: workout.date)
            weekStarts.insert(weekStart)
        }

        let sortedWeeks = weekStarts.sorted()
        var longestStreak = 0
        var currentStreakCount = 0
        var tempStreak = 1

        for i in 1..<sortedWeeks.count {
            let prevWeek = sortedWeeks[i - 1]
            let currentWeek = sortedWeeks[i]

            if let weeksBetween = calendar.dateComponents([.weekOfYear], from: prevWeek, to: currentWeek).weekOfYear,
               weeksBetween == 1 {
                tempStreak += 1
            } else {
                longestStreak = max(longestStreak, tempStreak)
                tempStreak = 1
            }
        }
        longestStreak = max(longestStreak, tempStreak)

        // Calculate current streak (from most recent workout)
        if let last = lastPerformed {
            let now = Date.now
            let currentWeekStart = calendar.startOfWeek(for: now)
            let lastWeekStart = calendar.startOfWeek(for: last)

            if calendar.isDate(lastWeekStart, equalTo: currentWeekStart, toGranularity: .weekOfYear) ||
               calendar.isDate(lastWeekStart, equalTo: calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) ?? currentWeekStart, toGranularity: .weekOfYear) {
                // Count backwards from last performed week
                currentStreakCount = 1
                if sortedWeeks.count > 1 {
                    for i in stride(from: sortedWeeks.count - 2, through: 0, by: -1) {
                        let week = sortedWeeks[i]
                        let nextWeek = sortedWeeks[i + 1]
                        if let weeksBetween = calendar.dateComponents([.weekOfYear], from: week, to: nextWeek).weekOfYear,
                           weeksBetween == 1 {
                            currentStreakCount += 1
                        } else {
                            break
                        }
                    }
                }
            }
        }

        // Days since last performed
        var daysSinceLastPerformed: Int?
        if let last = lastPerformed {
            daysSinceLastPerformed = calendar.dateComponents([.day], from: last, to: Date.now).day
        }

        return FrequencyStatistics(
            totalTimesPerformed: totalTimesPerformed,
            firstPerformed: firstPerformed,
            lastPerformed: lastPerformed,
            averagePerWeek: averagePerWeek,
            longestStreak: longestStreak,
            currentStreak: currentStreakCount,
            daysSinceLastPerformed: daysSinceLastPerformed
        )
    }

    // MARK: - Time Statistics

    private func computeTimeStatistics(
        exerciseID: String,
        workouts: [(workout: CompletedWorkout, entry: WorkoutEntry)]
    ) -> TimeStatistics {
        var restTimes: [TimeInterval] = []
        var workDurations: [TimeInterval] = []

        for (_, entry) in workouts {
            for set in entry.sets where set.isCompleted {
                // Collect rest times - prefer actual rest over planned rest
                if let actualRest = set.actualRestSeconds {
                    restTimes.append(TimeInterval(actualRest))
                } else if let rest = set.restAfterSeconds {
                    restTimes.append(TimeInterval(rest))
                }

                // Collect work durations (for timed exercises or if timing data available)
                if let workDuration = set.workDuration {
                    workDurations.append(workDuration)
                }
            }
        }

        let averageRest = restTimes.isEmpty ? nil : restTimes.reduce(0, +) / Double(restTimes.count)
        let minRest = restTimes.min()
        let maxRest = restTimes.max()
        let averageWork = workDurations.isEmpty ? nil : workDurations.reduce(0, +) / Double(workDurations.count)

        // Total time under tension (for timed exercises)
        var totalTUT: TimeInterval = 0
        for (_, entry) in workouts {
            for set in entry.sets where set.isCompleted && set.trackingMode == .timed {
                totalTUT += TimeInterval(set.durationSeconds)
            }
        }

        return TimeStatistics(
            averageRestBetweenSets: averageRest,
            minRestTime: minRest,
            maxRestTime: maxRest,
            averageWorkDuration: averageWork,
            totalTimeUnderTension: totalTUT
        )
    }

    // MARK: - Exercise History

    private func buildExerciseHistory(
        exerciseID: String,
        trackingMode: TrackingMode,
        workouts: [(workout: CompletedWorkout, entry: WorkoutEntry)],
        prs: PersonalRecords
    ) -> ExerciseHistory {
        let sortedWorkouts = workouts.sorted { $0.workout.date > $1.workout.date }

        let allWorkoutEntries = sortedWorkouts.map { workout, entry in
            buildExerciseWorkoutEntry(workout: workout, entry: entry, trackingMode: trackingMode, prs: prs)
        }

        let recentWorkouts = Array(allWorkoutEntries.prefix(4))

        return ExerciseHistory(
            recentWorkouts: recentWorkouts,
            allWorkouts: allWorkoutEntries
        )
    }

    private func buildExerciseWorkoutEntry(
        workout: CompletedWorkout,
        entry: WorkoutEntry,
        trackingMode: TrackingMode,
        prs: PersonalRecords
    ) -> ExerciseWorkoutEntry {
        var sessionVolume: Double = 0
        var restTimes: [TimeInterval] = []
        var isPR = false
        var prType: String?

        // Check if THIS workout achieved any PRs (workout-level check)
        let isWorkoutPR = checkWorkoutPR(workout: workout, prs: prs)
        if isWorkoutPR {
            isPR = true
        }

        let setPerformances = entry.sets.enumerated().map { index, set -> SetPerformance in
            // Calculate volume for this set
            if trackingMode == .weighted {
                sessionVolume += Double(set.reps) * set.weight
            }

            // Collect rest times - prefer actual rest over planned rest
            let effectiveRest = set.actualRestSeconds ?? set.restAfterSeconds
            if let rest = effectiveRest {
                restTimes.append(TimeInterval(rest))
            }

            // Check if this set achieved any PR (set-level check)
            let setIsPR = checkIfPR(set: set, workout: workout, prs: prs)
            if setIsPR {
                isPR = true
            }

            return SetPerformance(
                setNumber: index + 1,
                reps: set.reps,
                weight: set.weight,
                durationSeconds: set.durationSeconds,
                restAfter: effectiveRest.map { TimeInterval($0) },
                tag: set.tag,
                trackingMode: set.trackingMode,
                isPR: setIsPR
            )
        }

        // Determine PR type if applicable
        if isPR {
            if prs.bestVolume?.workoutID == workout.id {
                prType = "Volume PR"
            } else if prs.bestE1RM?.workoutID == workout.id {
                prType = "E1RM PR"
            } else if prs.heaviestWeight?.workoutID == workout.id {
                prType = "Weight PR"
            } else if prs.longestHold?.workoutID == workout.id {
                prType = "Duration PR"
            } else if prs.mostReps?.workoutID == workout.id || prs.mostRepsBodyweight?.workoutID == workout.id {
                prType = "Reps PR"
            }
        }

        let averageRest = restTimes.isEmpty ? nil : restTimes.reduce(0, +) / Double(restTimes.count)

        return ExerciseWorkoutEntry(
            workoutID: workout.id,
            date: workout.date,
            sets: setPerformances,
            totalVolume: sessionVolume,
            averageRest: averageRest,
            isPR: isPR,
            prType: prType
        )
    }

    /// Check if this workout achieved any workout-level PRs (like total reps, volume, etc.)
    private func checkWorkoutPR(workout: CompletedWorkout, prs: PersonalRecords) -> Bool {
        // Check if this workout achieved any workout-level PRs
        if let pr = prs.bestVolume, pr.workoutID == workout.id {
            return true
        }
        if let pr = prs.bestE1RM, pr.workoutID == workout.id {
            return true
        }
        if let pr = prs.mostRepsBodyweight, pr.workoutID == workout.id {
            return true // Bodyweight total reps PR
        }
        return false
    }

    /// Check if this specific set achieved a set-level PR
    private func checkIfPR(set: SetInput, workout: CompletedWorkout, prs: PersonalRecords) -> Bool {
        // Check if this set from this workout matches any PR
        if let pr = prs.heaviestWeight, pr.workoutID == workout.id, pr.value == set.weight {
            return true
        }
        if let pr = prs.mostReps, pr.workoutID == workout.id, pr.value == Double(set.reps) {
            return true
        }
        if let pr = prs.longestHold, pr.workoutID == workout.id, pr.value == Double(set.durationSeconds) {
            return true
        }
        return false
    }

    // MARK: - Progress Data

    private func computeProgressData(
        exerciseID: String,
        trackingMode: TrackingMode,
        workouts: [(workout: CompletedWorkout, entry: WorkoutEntry)],
        volumeStats: VolumeStatistics
    ) -> ProgressData {
        let sortedWorkouts = workouts.sorted { $0.workout.date < $1.workout.date }

        // Weight/intensity progression (average weight per workout, or avg reps for bodyweight)
        var weightProgression: [ProgressPoint] = []
        for (workout, entry) in sortedWorkouts {
            let completedSets = entry.sets.filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }

            let progressValue: Double
            switch trackingMode {
            case .weighted:
                let weightedSets = completedSets.filter { $0.trackingMode == .weighted }
                guard !weightedSets.isEmpty else { continue }
                progressValue = weightedSets.reduce(0.0) { $0 + $1.weight } / Double(weightedSets.count)
            case .bodyweight:
                // For bodyweight, track average reps per set as "intensity"
                progressValue = completedSets.reduce(0.0) { $0 + Double($1.reps) } / Double(completedSets.count)
            case .timed:
                // For timed, track average duration per set
                progressValue = completedSets.reduce(0.0) { $0 + Double($1.durationSeconds) } / Double(completedSets.count)
            case .distance:
                // For distance, track average distance per set
                progressValue = completedSets.reduce(0.0) { $0 + $1.distanceMeters } / Double(completedSets.count)
            }

            if progressValue > 0 {
                weightProgression.append(ProgressPoint(date: workout.date, value: progressValue))
            }
        }

        // Volume progression (volume per workout)
        // For weighted: reps × weight, for bodyweight: total reps, for timed: total duration
        var volumeProgression: [ProgressPoint] = []
        for (workout, entry) in sortedWorkouts {
            let completedSets = entry.sets.filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }

            let volume: Double
            switch trackingMode {
            case .weighted:
                volume = completedSets.reduce(0.0) { sum, set in
                    sum + (Double(set.reps) * set.weight)
                }
            case .bodyweight:
                // For bodyweight, use total reps as the "volume"
                volume = completedSets.reduce(0.0) { sum, set in
                    sum + Double(set.reps)
                }
            case .timed:
                // For timed, use total duration in seconds
                volume = completedSets.reduce(0.0) { sum, set in
                    sum + Double(set.durationSeconds)
                }
            case .distance:
                // For distance, use total distance
                volume = completedSets.reduce(0.0) { sum, set in
                    sum + set.distanceMeters
                }
            }

            if volume > 0 {
                volumeProgression.append(ProgressPoint(date: workout.date, value: volume))
            }
        }

        // E1RM progression
        var e1rmProgression: [ProgressPoint] = []
        for (workout, entry) in sortedWorkouts where trackingMode == .weighted {
            let completedSets = entry.sets.filter { $0.isCompleted && $0.weight > 0 && $0.reps > 0 }
            guard !completedSets.isEmpty else { continue }

            let bestE1RM = completedSets.map { set in
                set.weight * (1 + Double(set.reps) / 30.0)
            }.max() ?? 0

            if bestE1RM > 0 {
                e1rmProgression.append(ProgressPoint(date: workout.date, value: bestE1RM))
            }
        }

        // Frequency trend (times performed per week)
        let frequencyTrend = volumeStats.volumeByWeek.map { weekly in
            FrequencyPoint(weekStart: weekly.weekStart, count: weekly.sessions)
        }

        // Calculate trend direction and percent changes
        let trendDirection = calculateTrendDirection(volumeProgression: volumeProgression)
        let volumeChange = calculatePercentChange(data: volumeProgression, weeks: 4)
        let weightChange = calculatePercentChange(data: weightProgression, weeks: 4)

        return ProgressData(
            weightProgression: weightProgression,
            volumeProgression: volumeProgression,
            e1rmProgression: e1rmProgression,
            frequencyTrend: frequencyTrend,
            trendDirection: trendDirection,
            volumeChangePercent: volumeChange,
            weightChangePercent: weightChange
        )
    }

    private func calculateTrendDirection(volumeProgression: [ProgressPoint]) -> TrendDirection {
        // Need at least 3 data points to determine a trend
        guard volumeProgression.count >= 3 else { return .insufficient }

        // Compare recent average (last 3 workouts) with previous average
        let recentCount = min(3, volumeProgression.count)
        let recent = Array(volumeProgression.suffix(recentCount))
        let recentAvg = recent.reduce(0.0) { $0 + $1.value } / Double(recent.count)

        guard volumeProgression.count >= 6 else {
            // Not enough data for full comparison, just check if recent trend is up
            if volumeProgression.count >= 2 {
                let first = volumeProgression[0].value
                let last = volumeProgression.last!.value
                if last > first * 1.1 { return .improving }
                if last < first * 0.9 { return .declining }
                return .stable
            }
            return .insufficient
        }

        let previous = Array(volumeProgression.dropLast(3).suffix(3))
        let previousAvg = previous.reduce(0.0) { $0 + $1.value } / Double(previous.count)

        let change = (recentAvg - previousAvg) / previousAvg

        if change > 0.1 { return .improving }
        if change < -0.1 { return .declining }
        return .stable
    }

    private func calculatePercentChange(data: [ProgressPoint], weeks: Int) -> Double? {
        guard data.count >= 2 else { return nil }

        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date.now) ?? Date.distantPast

        let recentData = data.filter { $0.date >= cutoffDate }
        guard recentData.count >= 2 else { return nil }

        let oldValue = recentData.first!.value
        let newValue = recentData.last!.value

        guard oldValue > 0 else { return nil }

        return ((newValue - oldValue) / oldValue) * 100
    }

    // MARK: - Helper Methods

    private func filterWorkoutsContaining(
        exerciseID: String,
        in workouts: [CompletedWorkout]
    ) -> [(workout: CompletedWorkout, entry: WorkoutEntry)] {
        var result: [(CompletedWorkout, WorkoutEntry)] = []

        for workout in workouts {
            if let entry = workout.entries.first(where: { $0.exerciseID == exerciseID }) {
                result.append((workout, entry))
            }
        }

        return result
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }
}
