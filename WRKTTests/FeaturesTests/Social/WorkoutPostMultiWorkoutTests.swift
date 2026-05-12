import XCTest
@testable import WRKT

final class WorkoutPostMultiWorkoutTests: WRKTTestCase {
    func testLegacyPostWithoutWorkoutDataListDecodesAsSingleWorkout() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "caption": "legacy",
          "workout_data": {
            "id": "33333333-3333-3333-3333-333333333333",
            "date": "2026-05-11T10:00:00Z",
            "entries": [],
            "workoutName": "Run"
          },
          "visibility": "friends",
          "likes_count": 0,
          "comments_count": 0,
          "created_at": "2026-05-11T10:05:00Z",
          "updated_at": "2026-05-11T10:05:00Z"
        }
        """

        let post = try decodePost(json)

        XCTAssertNil(post.workoutDataList)
        XCTAssertFalse(post.isMultiWorkout)
        XCTAssertEqual(post.allWorkouts.count, 1)
        XCTAssertEqual(post.allWorkouts.first?.workoutName, "Run")
    }

    func testMultiWorkoutPostDecodesWorkoutDataListAndKeepsPrimaryWorkout() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "caption": "session",
          "workout_data": {
            "id": "33333333-3333-3333-3333-333333333333",
            "date": "2026-05-11T10:00:00Z",
            "entries": [],
            "workoutName": "HIIT"
          },
          "workout_data_list": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "date": "2026-05-11T10:00:00Z",
              "entries": [],
              "workoutName": "HIIT"
            },
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "date": "2026-05-11T10:45:00Z",
              "entries": [],
              "workoutName": "Elliptical",
              "matchedHealthKitUUID": "55555555-5555-5555-5555-555555555555",
              "matchedHealthKitDuration": 1500,
              "matchedHealthKitCalories": 180,
              "cardioWorkoutType": "Elliptical"
            }
          ],
          "visibility": "friends",
          "likes_count": 0,
          "comments_count": 0,
          "created_at": "2026-05-11T10:05:00Z",
          "updated_at": "2026-05-11T10:05:00Z"
        }
        """

        let post = try decodePost(json)

        XCTAssertEqual(post.workoutData.workoutName, "HIIT")
        XCTAssertEqual(post.workoutDataList?.count, 2)
        XCTAssertTrue(post.isMultiWorkout)
        XCTAssertEqual(post.allWorkouts.map { $0.workoutName ?? $0.workoutTypeDisplayName }, ["HIIT", "Elliptical"])
    }

    func testExplicitSingleWorkoutListDoesNotCountAsMultiWorkout() {
        let workout = CompletedWorkout(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: makeDate(year: 2026, month: 5, day: 11),
            entries: [],
            workoutName: "Run"
        )
        let post = WorkoutPost(
            userId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            workoutData: workout,
            workoutDataList: [workout]
        )

        XCTAssertFalse(post.isMultiWorkout)
        XCTAssertEqual(post.allWorkouts.count, 1)
    }

    func testMapImageHeuristicOnlyMatchesGeneratedMapPaths() {
        XCTAssertTrue(PostImage(storagePath: "workout-images-public/u/route_map_123_0.jpg", isPublic: true).isGeneratedMapImage)
        XCTAssertTrue(PostImage(storagePath: "workout-images-public/u/map_123_0.jpg", isPublic: true).isGeneratedMapImage)
        XCTAssertFalse(PostImage(storagePath: "workout-images-public/u/workout_123_0.jpg", isPublic: true).isGeneratedMapImage)
        XCTAssertFalse(PostImage(storagePath: "workout-images-public/u/photo_of_maple_tree.jpg", isPublic: true).isGeneratedMapImage)
    }

    private func decodePost(_ json: String) throws -> WorkoutPost {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkoutPost.self, from: Data(json.utf8))
    }
}
