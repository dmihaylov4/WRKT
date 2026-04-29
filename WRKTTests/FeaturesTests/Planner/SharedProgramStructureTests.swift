import Foundation
import Testing
@testable import WRKT

struct SharedProgramStructureTests {

    @Test func decodesVersion1Payload() throws {
        let json = """
        {
          "version": 1,
          "planBlocks": [
            {
              "dayName": "Push",
              "isRestDay": false,
              "order": 0,
              "exercises": [
                {
                  "exerciseID": "bb-bench",
                  "exerciseName": "Barbell Bench Press",
                  "sets": 3,
                  "reps": 8,
                  "progressionStrategy": { "type": "linear", "increment": 2.5 },
                  "order": 0
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        #expect(decoded.version == 1)
        #expect(decoded.planBlocks.count == 1)
        #expect(decoded.planBlocks[0].dayName == "Push")
        #expect(decoded.planBlocks[0].exercises.count == 1)
        #expect(decoded.planBlocks[0].exercises[0].progressionStrategy == .linear(increment: 2.5))
    }

    @Test func decodesRestDayBlock() throws {
        let json = """
        { "version": 1, "planBlocks": [
          { "dayName": "Rest", "isRestDay": true, "order": 0, "exercises": [] }
        ] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        #expect(decoded.planBlocks[0].isRestDay)
        #expect(decoded.planBlocks[0].exercises.isEmpty)
    }

    @Test func unknownProgressionStrategyFallsBackToStatic() throws {
        let json = """
        { "version": 1, "planBlocks": [
          { "dayName": "X", "isRestDay": false, "order": 0, "exercises": [
            { "exerciseID": "x", "exerciseName": "X", "sets": 1, "reps": 1, "order": 0,
              "progressionStrategy": { "type": "timedescent", "step": 9 } }
          ] }
        ] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        #expect(decoded.planBlocks[0].exercises[0].progressionStrategy == .static)
    }

    @Test func futureVersionThrowsTypedError() {
        let json = """
        { "version": 99, "planBlocks": [] }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
            Issue.record("Expected unsupportedVersion error")
        } catch let error as SharedProgramStructure.DecodingError {
            #expect(error == .unsupportedVersion(99))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func encodesVersion1WithoutWeights() throws {
        let structure = SharedProgramStructure(
            planBlocks: [
                .init(
                    dayName: "Push",
                    isRestDay: false,
                    order: 0,
                    exercises: [
                        .init(
                            exerciseID: "bb-bench",
                            exerciseName: "Bench",
                            sets: 3,
                            reps: 8,
                            progressionStrategy: .linear(increment: 2.5),
                            order: 0
                        )
                    ]
                )
            ]
        )
        let data = try JSONEncoder().encode(structure)
        let string = try #require(String(data: data, encoding: .utf8))
        #expect(!string.contains("weight"))
        #expect(!string.contains("startingWeight"))
    }
}
