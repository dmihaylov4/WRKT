import Foundation

struct CutExerciseInfoModel: Equatable {
    enum Tab: String, CaseIterable { case info = "Info", timer = "Timer", stats = "Stats" }
    struct Line: Equatable, Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }
    let title: String
    let metadata: String
    let videoURL: URL?
    let muscles: [Line]
    let cues: [String]
    let progression: [Line]
    let progressionReason: String?
    let restTime: String
    let restSource: String
    let canEdit: Bool
}

enum CutExerciseInfoLogic {
    static func model(exercise: Exercise, meta: ExerciseGuideMeta, videoURL: URL?,
                      progression: ProgressionSuggestion?, unit: WeightUnit,
                      restSeconds: Int, hasOverride: Bool) -> CutExerciseInfoModel {
        let groups = [("Primary", exercise.primaryMuscles), ("Secondary", exercise.secondaryMuscles), ("Tertiary", exercise.tertiaryMuscles)]
        let muscles = groups.compactMap { title, values -> CutExerciseInfoModel.Line? in
            values.isEmpty ? nil : .init(title: title, value: values.joined(separator: ", "))
        }
        let changes: [CutExerciseInfoModel.Line]
        if let progression {
            if progression.type == .increaseReps && progression.previousWeight == 0 {
                changes = [.init(title: "Previous", value: "\(progression.suggestedReps - 1) reps"),
                           .init(title: "Suggested", value: "\(progression.suggestedReps) reps")]
            } else {
                let factor = unit == .kg ? 1.0 : 2.20462
                changes = [.init(title: "Previous", value: String(format: "%.1f%@", progression.previousWeight * factor, unit.rawValue)),
                           .init(title: "Suggested", value: String(format: "%.1f%@", progression.suggestedWeight * factor, unit.rawValue))]
            }
        } else { changes = [] }
        return .init(title: exercise.name, metadata: [meta.equipment, meta.difficulty].filter { !$0.isEmpty }.joined(separator: " · "),
            videoURL: videoURL, muscles: muscles, cues: meta.cues, progression: changes, progressionReason: progression?.reason,
            restTime: String(format: "%d:%02d", restSeconds / 60, restSeconds % 60),
            restSource: hasOverride ? "Custom" : exercise.mechanic?.lowercased() == "compound" ? "Compound Default" : "Isolation Default",
            canEdit: exercise.isCustom)
    }

    static func visibleCues(_ cues: [String], expanded: Bool) -> [String] {
        Array(cues.prefix(expanded ? cues.count : 3))
    }
}
