import Testing
import Foundation
@testable import WRKT

@Suite("ExportBundle")
struct ExportBundleTests {
    @Test("round-trips through JSON without data loss")
    func roundTrip() throws {
        let plate = EarnedPlateExport(
            id: "abc", tierID: 1, weightKg: 5.0, engravingText: "First",
            earnedAt: Date(timeIntervalSince1970: 2_000_000), earnedByEvent: "first_workout",
            sourceWorkoutID: nil, isRacked: false, rackPosition: nil, displayOrder: 2_000_000
        )
        var workout = CompletedWorkout(entries: [])
        workout.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let bundle = ExportBundle(
            version: ExportBundle.currentVersion,
            appVersion: "1.0",
            exportedAt: Date(timeIntervalSince1970: 3_000_000),
            completedWorkouts: [workout],
            earnedPlates: [plate]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ExportBundle.self, from: data)

        #expect(decoded.version == ExportBundle.currentVersion)
        #expect(decoded.completedWorkouts.count == 1)
        #expect(decoded.earnedPlates.count == 1)
        #expect(decoded.earnedPlates[0].id == "abc")
    }
}
