import Foundation
import Testing

struct WorkoutStoreSmartNotificationTests {
    @Test func allCurrentWorkoutFinishPathsRefreshSmartNotificationLearning() throws {
        let source = try String(contentsOfFile: sourcePath("Features/WorkoutSession/Services/WorkoutStoreV2.swift"))

        let finishCurrentWorkoutBody = try functionBody(named: "finishCurrentWorkout", in: source)
        let finishCurrentWorkoutAndReturnPRsBody = try functionBody(named: "finishCurrentWorkoutAndReturnPRs", in: source)

        #expect(finishCurrentWorkoutBody.contains("refreshSmartNotificationLearningAfterWorkoutCompletion()"))
        #expect(finishCurrentWorkoutAndReturnPRsBody.contains("refreshSmartNotificationLearningAfterWorkoutCompletion()"))
    }

    @Test func allCurrentWorkoutFinishPathsUpdateCompetitiveFeatures() throws {
        let source = try String(contentsOfFile: sourcePath("Features/WorkoutSession/Services/WorkoutStoreV2.swift"))

        let finishCurrentWorkoutBody = try functionBody(named: "finishCurrentWorkout", in: source)
        let finishCurrentWorkoutAndReturnPRsBody = try functionBody(named: "finishCurrentWorkoutAndReturnPRs", in: source)

        #expect(finishCurrentWorkoutBody.contains("updateCompetitiveFeatures(for: completed)"))
        #expect(finishCurrentWorkoutAndReturnPRsBody.contains("updateCompetitiveFeatures(for: completed)"))
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

    private func functionBody(named name: String, in source: String) throws -> String {
        guard let range = source.range(of: "func \(name)") else {
            throw TestFailure("Missing function \(name)")
        }

        guard let openingBrace = source[range.lowerBound...].firstIndex(of: "{") else {
            throw TestFailure("Missing opening brace for \(name)")
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            }
            index = source.index(after: index)
        }

        throw TestFailure("Missing closing brace for \(name)")
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
