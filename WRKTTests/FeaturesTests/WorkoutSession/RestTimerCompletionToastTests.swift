import Foundation
import Testing

struct RestTimerCompletionToastTests {
    @Test func restTimerCompletionDoesNotMountInAppToast() throws {
        let appShellSource = try String(contentsOfFile: sourcePath("App/AppShellView.swift"), encoding: .utf8)
        let exerciseSessionSource = try String(contentsOfFile: sourcePath("Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift"), encoding: .utf8)
        let restTimerViewSource = try String(contentsOfFile: sourcePath("Features/WorkoutSession/Views/RestTimer/RestTimerView.swift"), encoding: .utf8)

        #expect(!appShellSource.contains("RestTimerCompletionToast("))
        #expect(!exerciseSessionSource.contains("RestTimerCompletionToast("))
        #expect(!restTimerViewSource.contains("struct RestTimerCompletionToast"))
        #expect(!restTimerViewSource.contains("Rest Complete!"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: relativePath).path
    }
}
