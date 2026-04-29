import Foundation
import Testing
@testable import WRKT

@MainActor
struct ProgramSerializerTests {

    private func makeSplit() -> WorkoutSplit {
        let pushExercises = [
            PlanBlockExercise(
                exerciseID: "bb-bench",
                exerciseName: "Bench",
                sets: 3,
                reps: 8,
                startingWeight: 80.0,
                progressionStrategy: .linear(increment: 2.5),
                order: 0
            ),
            PlanBlockExercise(
                exerciseID: "ohp",
                exerciseName: "OHP",
                sets: 3,
                reps: 10,
                startingWeight: 40.0,
                progressionStrategy: .autoregulated,
                order: 1
            )
        ]
        let push = PlanBlock(dayName: "Push", exercises: pushExercises, isRestDay: false)
        let rest = PlanBlock(dayName: "Rest", exercises: [], isRestDay: true)
        return WorkoutSplit(name: "PPL", planBlocks: [push, rest], reschedulePolicy: .rolling)
    }

    @Test func toStructureDropsWeights() throws {
        let split = makeSplit()
        let structure = ProgramSerializer.toStructure(
            split,
            creator: .init(userID: "creator-uid", username: "alice", displayName: "Alice")
        )

        #expect(structure.version == 1)
        #expect(structure.creator?.userID == "creator-uid")
        #expect(structure.planBlocks.count == 2)
        #expect(structure.planBlocks[0].exercises.count == 2)

        let data = try JSONEncoder().encode(structure)
        let jsonString = try #require(String(data: data, encoding: .utf8))
        #expect(!jsonString.contains("startingWeight"))
        #expect(!jsonString.contains("\"weight\""))
    }

    @Test func roundTripPreservesStructureAndAttribution() {
        let original = makeSplit()
        let structure = ProgramSerializer.toStructure(
            original,
            creator: .init(userID: "creator-uid", username: "alice", displayName: "Alice")
        )
        let restored = ProgramSerializer.fromStructure(
            structure,
            name: "Imported PPL",
            reschedulePolicy: .rolling,
            description: "Imported",
            originProgramID: UUID()
        )

        #expect(restored.planBlocks.count == 2)
        #expect(restored.planBlocks[0].exercises.count == 2)
        #expect(restored.creatorUserID == "creator-uid")
        #expect(restored.creatorUsername == "alice")
        #expect(restored.creatorDisplayName == "Alice")
        #expect(restored.isActive == false)
        #expect(restored.programDescription == "Imported")
    }
}
