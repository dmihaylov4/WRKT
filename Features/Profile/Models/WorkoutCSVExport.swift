//
//  WorkoutCSVExport.swift
//  WRKT
//
//  The "Export workouts as CSV" file, shared by the legacy and the Cut Preferences screens. One
//  row per set, oldest workout first. The last column says whether the set was completed (the
//  old file put a check mark there under a "Notes" header; sets have no notes). Nothing in the
//  app reads this file back: the importer takes the JSON bundle from Data portability.
//

import Foundation

enum WorkoutCSVExport {
    static let header = "Date,Exercise,Set Number,Tag,Reps,Weight (kg),Completed"

    static func csv(_ workouts: [CompletedWorkout], timeZone: TimeZone = .current) -> String {
        var csv = header + "\n"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = timeZone
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            let date = quoted(formatter.string(from: workout.date))
            for entry in workout.entries {
                for (index, set) in entry.sets.enumerated() {
                    let fields = [date, quoted(entry.exerciseName), "\(index + 1)", quoted(set.tag.label),
                                  "\(set.reps)", "\(set.weight)", set.isCompleted ? "Yes" : "No"]
                    csv += fields.joined(separator: ",") + "\n"
                }
            }
        }
        return csv
    }

    /// A text field in quotes, with any quote inside doubled (RFC 4180).
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
