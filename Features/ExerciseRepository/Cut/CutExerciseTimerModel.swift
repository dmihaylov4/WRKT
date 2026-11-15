import Foundation

struct CutExerciseTimerModel: Equatable {
    var minutes: Int
    var seconds: Int
    var hasOverride: Bool
    var totalSeconds: Int { minutes * 60 + seconds }
    var canSave: Bool { minutes != 0 || seconds != 0 }
    var time: String { String(format: "%d:%02d", minutes, seconds) }
}

enum CutExerciseTimerLogic {
    static func model(duration: TimeInterval, hasOverride: Bool) -> CutExerciseTimerModel {
        let value = duration.safeInt
        return .init(minutes: value / 60, seconds: value % 60, hasOverride: hasOverride)
    }

    /// Preserve an existing recommendation that is not on the 15 second wheel, rather
    /// than silently rounding it just because the editor opened.
    static func minuteChoices(current: Int) -> [Int] { Array(Set(Array(0...10) + [current])).sorted() }
    static func secondChoices(current: Int) -> [Int] { Array(Set([0, 15, 30, 45, current])).sorted() }
}
