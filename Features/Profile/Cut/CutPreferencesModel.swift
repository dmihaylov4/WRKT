//
//  CutPreferencesModel.swift
//  WRKT
//
//  What the Cut Preferences page shows, as plain values, and the pure rules behind it, taken
//  from PreferencesView: the age and bodyweight lines, the weight increment options per unit,
//  the rest timer steps and typed times, the footers that change with a switch, which rows show
//  (social only when signed in, the notification settings link only when nudges are on but not
//  allowed, Reset weekly goal only with a goal set), the age and bodyweight wheels, the version
//  line and the CSV export.
//

import Foundation

/// The facts the page depends on, read by CutPreferencesHost.
struct CutPreferencesFacts {
    struct Zone: Equatable {
        var zone: Int
        var name: String
        var range: String
    }

    struct CustomExercise: Equatable {
        var id: String
        var name: String
        var primaryMuscle: String?
        var mechanic: String?
        var equipment: String?
    }

    /// The age the zones use (AgeSetting); nil when none is saved.
    var age: Int?
    var bodyweightKg: Double = 70
    /// Nil when the stored unit is not one the app knows (the legacy fallback prints kg).
    var unit: WeightUnit? = .kg
    var restTimerEnabled = true
    var compoundSeconds = 180
    var isolationSeconds = 90
    var maxHR = 190
    var zones: [Zone] = []
    var zonesMethodDescription = ""
    var customExercises: [CustomExercise] = []
    var isSignedIn = false
    var smartNudgesEnabled = false
    var notificationsAuthorized = false
    var hasWeeklyGoal = false
    var shortVersion: String?
    var buildNumber: String?
}

struct CutPreferencesModel: Equatable {
    struct Zone: Identifiable, Equatable {
        var id: Int
        var title: String
        var range: String
    }

    struct CustomExercise: Identifiable, Equatable {
        var id: String
        var name: String
        var detail: String
    }

    var title = "Preferences"
    /// Always editable: a saved age still ages by itself each year.
    var age: String
    var bodyweight: String
    var profileFooter = CutPreferencesLogic.profileFooter
    var incrementOptions: [CutSettingsOption<Double>]
    var unitOptions: [CutSettingsOption<String>]
    var showsRestTimerDetails: Bool
    var compoundRest: String
    var isolationRest: String
    var workoutFooter: String
    var maxHeartRate: String
    var zones: [Zone]
    var zonesFooter: String
    var customExercises: [CustomExercise]
    var customFooter = CutPreferencesLogic.customFooter
    var showsSocial: Bool
    var socialFooter = CutPreferencesLogic.socialFooter
    var showsNotificationSettingsLink: Bool
    var notificationsFooter: String
    var dataFooter = CutPreferencesLogic.dataFooter
    var version: String
    var showsResetWeeklyGoal: Bool
    var resetFooter = CutPreferencesLogic.resetFooter
}

enum CutPreferencesLogic {
    static let privacyURL = URL(string: "https://dmihaylov4.github.io/trak-privacy/")

    static let profileFooter = "Age is used for heart rate zones (Max HR = 220 - age) and updates automatically each year. Bodyweight is used for bodyweight exercise volume."
    static let customFooter = "Create custom exercises from the exercise browser by tapping the + button. Swipe left to delete."
    static let socialFooter = "When enabled, workouts will be automatically posted to your social feed for friends to see."
    static let dataFooter = "Export your workout history to CSV for analysis in other apps."
    static let resetFooter = "Reset all data will permanently delete workouts, stats, XP, level, PR dex, favorites, and custom timers. Runs/cardio from HealthKit will be preserved."
    static let customEmptyLine = "No custom exercises yet"

    static func model(_ facts: CutPreferencesFacts) -> CutPreferencesModel {
        CutPreferencesModel(
            age: AgeSetting.line(facts.age),
            bodyweight: bodyweightLine(kg: facts.bodyweightKg, unit: facts.unit),
            incrementOptions: incrementOptions(unit: facts.unit ?? .kg),
            unitOptions: unitOptions,
            showsRestTimerDetails: facts.restTimerEnabled,
            compoundRest: restLine(facts.compoundSeconds),
            isolationRest: restLine(facts.isolationSeconds),
            workoutFooter: workoutFooter(restTimerEnabled: facts.restTimerEnabled),
            maxHeartRate: "\(facts.maxHR) bpm",
            zones: facts.zones.map { CutPreferencesModel.Zone(id: $0.zone, title: "Zone \($0.zone), \($0.name)", range: $0.range) },
            zonesFooter: facts.zonesMethodDescription,
            customExercises: facts.customExercises.map {
                CutPreferencesModel.CustomExercise(id: $0.id, name: $0.name, detail: customDetail($0))
            },
            showsSocial: facts.isSignedIn,
            showsNotificationSettingsLink: showsNotificationSettingsLink(
                nudgesEnabled: facts.smartNudgesEnabled, authorized: facts.notificationsAuthorized),
            notificationsFooter: notificationsFooter(nudgesEnabled: facts.smartNudgesEnabled),
            version: version(short: facts.shortVersion, build: facts.buildNumber),
            showsResetWeeklyGoal: facts.hasWeeklyGoal
        )
    }

    // MARK: Profile

    static func bodyweightLine(kg: Double, unit: WeightUnit?) -> String {
        BodyweightScale.line(kg: kg, unit: unit)
    }

    // MARK: Workout

    static let unitOptions = [
        CutSettingsOption(value: WeightUnit.kg.rawValue, label: "kg"),
        CutSettingsOption(value: WeightUnit.lb.rawValue, label: "lb")
    ]

    /// The stored step stays 0.5, 1 or 2.5; pounds label the same three steps.
    static func incrementOptions(unit: WeightUnit) -> [CutSettingsOption<Double>] {
        switch unit {
        case .kg:
            [CutSettingsOption(value: 0.5, label: "0.5 kg"),
             CutSettingsOption(value: 1.0, label: "1 kg"),
             CutSettingsOption(value: 2.5, label: "2.5 kg")]
        case .lb:
            [CutSettingsOption(value: 0.5, label: "1.25 lb"),
             CutSettingsOption(value: 1.0, label: "2.5 lb"),
             CutSettingsOption(value: 2.5, label: "5 lb")]
        }
    }

    static func workoutFooter(restTimerEnabled: Bool) -> String {
        restTimerEnabled
            ? "Rest timer starts automatically after saving sets. Custom timers for specific exercises override these defaults."
            : "Control haptic feedback and rest timer behavior during workouts."
    }

    static let restRange = 30...600
    static let restStep = 30

    static func restLine(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "3:00", "3:30", or plain seconds ("90"). Nil when it cannot be read.
    static func parseRest(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        return Int(trimmed)
    }

    /// A typed time, clamped to the range; the current value when it cannot be read.
    static func typedRest(_ text: String, current: Int) -> Int {
        guard let parsed = parseRest(text) else { return current }
        return min(max(parsed, restRange.lowerBound), restRange.upperBound)
    }

    /// Only digits and colons survive typing.
    static func filteredRestInput(_ text: String) -> String {
        text.filter { $0.isNumber || $0 == ":" }
    }

    /// One step up or down, clamped; nil when the value would not change.
    static func bumpedRest(_ seconds: Int, by delta: Int) -> Int? {
        let next = min(max(seconds + delta, restRange.lowerBound), restRange.upperBound)
        return next == seconds ? nil : next
    }

    // MARK: Custom exercises

    static func customDetail(_ exercise: CutPreferencesFacts.CustomExercise) -> String {
        var parts = [exercise.primaryMuscle ?? "Unknown"]
        if let mechanic = exercise.mechanic { parts.append(mechanic.capitalized) }
        if let equipment = exercise.equipment { parts.append(equipment) }
        return parts.joined(separator: ", ")
    }

    // MARK: Notifications

    static func showsNotificationSettingsLink(nudgesEnabled: Bool, authorized: Bool) -> Bool {
        nudgesEnabled && !authorized
    }

    static func notificationsFooter(nudgesEnabled: Bool) -> String {
        nudgesEnabled
            ? "You'll receive notifications when friends complete workouts to help keep you motivated and accountable."
            : "Enable smart nudges to receive motivational notifications based on friend activity."
    }

    // MARK: About

    static func version(short: String?, build: String?) -> String {
        "v\(short ?? "?") (\(build ?? "?"))"
    }

    // MARK: Alerts (the legacy copy and counts)

    static func clearWorkoutsButton(_ count: Int) -> String { "Clear \(count) workouts" }
    static func clearPlansButton(_ count: Int) -> String { "Clear \(count) plans" }
    static func clearPlansMessage(plans: Int, splits: Int) -> String {
        "This will permanently delete all \(plans) planned workouts and \(splits) workout splits from the planner. This cannot be undone."
    }
    static let resetAllMessage = "This will permanently delete: all workouts, stats, XP, level, PR dex, favorites, and custom timers. Only runs/cardio from HealthKit will be preserved. This cannot be undone."
    static let resetTimersMessage = "All custom rest timers for individual exercises will be reset to defaults."

    // MARK: CSV export (byte for byte the legacy file)

    static func csvFileName(date: Date) -> String {
        "WRKT_Workouts_\(date.formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-"))"
    }

    static func csv(_ workouts: [CompletedWorkout], timeZone: TimeZone = .current) -> String {
        var csv = "Date,Exercise,Set Number,Tag,Reps,Weight (kg),Notes\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = timeZone
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            let dateStr = formatter.string(from: workout.date)
            for entry in workout.entries {
                for (index, set) in entry.sets.enumerated() {
                    let completed = set.isCompleted ? "\u{2713}" : ""
                    csv += "\"\(dateStr)\",\"\(entry.exerciseName)\",\(index + 1),\"\(set.tag.label)\",\(set.reps),\(set.weight),\"\(completed)\"\n"
                }
            }
        }
        return csv
    }
}
