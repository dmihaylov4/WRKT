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

    @MainActor
    func testPostDetailRefreshesLikedStateBeforeUnliking() async {
        let postId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let authorId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let currentUserId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let post = WorkoutPost(
            id: postId,
            userId: authorId,
            workoutData: makeWorkout(name: "Strength", id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
            likesCount: 0
        )
        let postWithAuthor = PostWithAuthor(
            id: postId,
            post: post,
            author: UserProfile(id: authorId, username: "author"),
            isLikedByCurrentUser: false
        )
        let repository = PostDetailRepositorySpy(isPostLikedByUserResult: true)
        let authService = PostDetailAuthServiceStub(currentUserId: currentUserId)
        let viewModel = PostDetailViewModel(
            post: postWithAuthor,
            postRepository: repository,
            authService: authService
        )

        await viewModel.refreshLikeState()
        await viewModel.toggleLike()

        XCTAssertEqual(repository.likePostIds, [])
        XCTAssertEqual(repository.unlikePostIds, [postId])
        XCTAssertFalse(viewModel.post.isLikedByCurrentUser)
        XCTAssertEqual(viewModel.post.post.likesCount, 0)
        XCTAssertEqual(repository.checkedLikePostId, postId)
        XCTAssertEqual(repository.checkedLikeUserId, currentUserId)
    }

    func testPostLikeNotificationMigrationDedupesRelikeNotifications() throws {
        let migration = try String(
            contentsOfFile: sourcePath("supabase/migrations/20260516120000_dedupe_post_like_notifications.sql"),
            encoding: .utf8
        ).lowercased()

        XCTAssertTrue(migration.contains("idx_notifications_post_like_unique"))
        XCTAssertTrue(migration.contains("where type = 'post_like'"))
        XCTAssertTrue(migration.contains("on conflict (user_id, type, actor_id, target_id)"))
        XCTAssertTrue(migration.contains("do nothing"))
        XCTAssertTrue(migration.contains("after insert on public.post_likes"))
    }

    private func makeWorkout(name: String, id: UUID) -> CompletedWorkout {
        CompletedWorkout(
            id: id,
            date: makeDate(year: 2026, month: 5, day: 11),
            entries: [],
            workoutName: name
        )
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

@MainActor
private final class PostDetailRepositorySpy: PostDetailPostRepository {
    var isPostLikedByUserResult: Bool
    var checkedLikePostId: UUID?
    var checkedLikeUserId: UUID?
    var likePostIds: [UUID] = []
    var unlikePostIds: [UUID] = []

    init(isPostLikedByUserResult: Bool) {
        self.isPostLikedByUserResult = isPostLikedByUserResult
    }

    func fetchCommentsWithReplies(postID: UUID) async throws -> [PostComment] {
        []
    }

    func parseMentions(from text: String) -> [String] {
        []
    }

    func searchUsersByUsername(query: String, limit: Int) async throws -> [UserProfile] {
        []
    }

    func postComment(
        postID: UUID,
        content: String,
        parentCommentID: UUID?,
        mentionedUserIDs: [UUID]
    ) async throws -> PostComment {
        PostComment(postId: postID, userId: UUID(), content: content, parentCommentID: parentCommentID)
    }

    func deleteComment(commentId: UUID) async throws {}

    func likePost(_ postId: UUID) async throws {
        likePostIds.append(postId)
    }

    func unlikePost(_ postId: UUID) async throws {
        unlikePostIds.append(postId)
    }

    func isPostLikedByUser(postId: UUID, userId: UUID) async throws -> Bool {
        checkedLikePostId = postId
        checkedLikeUserId = userId
        return isPostLikedByUserResult
    }
}

private struct PostDetailAuthServiceStub: PostDetailAuthProviding {
    let currentUser: AuthUser?

    init(currentUserId: UUID) {
        currentUser = AuthUser(
            id: currentUserId,
            email: "current@example.com",
            profile: UserProfile(id: currentUserId, username: "current")
        )
    }
}
