import XCTest
@testable import WRKT

final class PostRepositoryMultiWorkoutPayloadTests: WRKTTestCase {
    func testSingleWorkoutPayloadOmitsWorkoutDataList() throws {
        let workout = makeWorkout(name: "Strength", id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        let payload = try WorkoutPostInsertPayload(
            workouts: [workout],
            caption: "single",
            images: nil,
            visibility: .friends,
            userId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )

        XCTAssertEqual(payload.workout_data.id, workout.id)
        XCTAssertNil(payload.workout_data_list)
        XCTAssertEqual(payload.visibility, "friends")
    }

    func testMultiWorkoutPayloadWritesPrimaryAndFullList() throws {
        let first = makeWorkout(name: "HIIT", id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let second = makeWorkout(name: "Elliptical", id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)

        let payload = try WorkoutPostInsertPayload(
            workouts: [first, second],
            caption: nil,
            images: [],
            visibility: .publicPost,
            userId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )

        XCTAssertEqual(payload.workout_data.id, first.id)
        XCTAssertEqual(payload.workout_data_list?.map(\.id), [first.id, second.id])
        XCTAssertEqual(payload.visibility, "public")
    }

    func testEmptyWorkoutPayloadThrowsBeforeNetworkInsert() {
        XCTAssertThrowsError(
            try WorkoutPostInsertPayload(
                workouts: [],
                caption: nil,
                images: nil,
                visibility: .friends,
                userId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            )
        )
    }

    private func makeWorkout(name: String, id: UUID) -> CompletedWorkout {
        CompletedWorkout(
            id: id,
            date: makeDate(year: 2026, month: 5, day: 11),
            entries: [],
            workoutName: name
        )
    }
}
