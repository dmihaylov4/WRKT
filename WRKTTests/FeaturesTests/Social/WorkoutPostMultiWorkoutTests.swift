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

    func testCachedPostRoundTripPreservesWorkoutDataList() throws {
        let userId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = CompletedWorkout(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: makeDate(year: 2026, month: 5, day: 11, hour: 10),
            entries: [],
            workoutName: "HIIT"
        )
        let second = CompletedWorkout(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            date: makeDate(year: 2026, month: 5, day: 11, hour: 11),
            entries: [],
            workoutName: "Elliptical"
        )
        let post = WorkoutPost(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            userId: userId,
            caption: "session",
            workoutData: first,
            visibility: .friends,
            workoutDataList: [first, second]
        )
        let author = UserProfile(id: userId, username: "tester")
        let postWithAuthor = PostWithAuthor(
            id: post.id,
            post: post,
            author: author,
            isLikedByCurrentUser: true
        )

        let cached = CachedPost.from(postWithAuthor)
        let restored = try XCTUnwrap(cached.toPostWithAuthor())

        XCTAssertTrue(restored.post.isMultiWorkout)
        XCTAssertEqual(restored.post.workoutData.workoutName, "HIIT")
        XCTAssertEqual(restored.post.workoutDataList?.map { $0.workoutName }, ["HIIT", "Elliptical"])
        XCTAssertEqual(restored.post.allWorkouts.map { $0.workoutName ?? $0.workoutTypeDisplayName }, ["HIIT", "Elliptical"])
    }

    func testCachedPostRoundTripPreservesSharedPostPartner() throws {
        let creatorId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let partnerId = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let workout = CompletedWorkout(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: makeDate(year: 2026, month: 5, day: 28, hour: 8),
            entries: [],
            workoutName: "Virtual Run"
        )
        let post = WorkoutPost(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            userId: creatorId,
            caption: "together",
            workoutData: workout,
            visibility: .friends,
            postType: .shared
        )
        let partner = PostParticipant(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            postId: post.id,
            userId: partnerId,
            workoutData: nil,
            vrStats: VRPartnerSummary(distanceM: 4900, durationS: 1800, paceSecPerKm: 367, avgHR: 151),
            joinedAt: makeDate(year: 2026, month: 5, day: 28, hour: 8),
            removedAt: nil,
            profile: UserProfile(id: partnerId, username: "partner")
        )
        let postWithAuthor = PostWithAuthor(
            id: post.id,
            post: post,
            author: UserProfile(id: creatorId, username: "creator"),
            isLikedByCurrentUser: false,
            partners: [partner]
        )

        let restored = try XCTUnwrap(CachedPost.from(postWithAuthor).toPostWithAuthor())

        XCTAssertEqual(restored.post.postType, .shared)
        XCTAssertEqual(restored.partners.count, 1)
        XCTAssertEqual(restored.partners.first?.userId, partnerId)
        XCTAssertEqual(restored.partners.first?.vrStats?.distanceM, 4900)
        XCTAssertEqual(restored.partners.first?.profile?.username, "partner")
    }

    private func decodePost(_ json: String) throws -> WorkoutPost {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkoutPost.self, from: Data(json.utf8))
    }
}
