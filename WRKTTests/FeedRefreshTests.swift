import Foundation
import Supabase
import Testing
@testable import WRKT

@MainActor
@Suite(.serialized)
struct FeedRefreshTests {
    @Test func cancelledRPCPreservesLoadedPostsWithoutError() async throws {
        let fixture = FeedRequestFixture(mode: .cancelledRPC)
        let model = makeModel(repository: fixture.repository)
        let previousUser = SupabaseAuthService.shared.currentUser
        SupabaseAuthService.shared.currentUser = fixture.user
        defer { SupabaseAuthService.shared.currentUser = previousUser }
        let existing = makePost(userID: fixture.user.id)
        model.posts = [existing]
        model.newPostsAvailable = 3

        await model.refresh()

        #expect(model.posts.map(\.id) == [existing.id])
        #expect(model.newPostsAvailable == 3)
        #expect(model.error == nil)
        #expect(!model.isRefreshing)
        #expect(fixture.paths.allSatisfy { $0.hasSuffix("/rpc/get_friend_feed") })
    }

    @Test func cancelledFallbackIsNotAnEmptySuccess() async throws {
        let fixture = FeedRequestFixture(mode: .cancelledFallback)
        do {
            _ = try await fixture.repository.fetchFeed(userId: fixture.user.id, cursor: nil)
            Issue.record("A cancelled fallback returned an empty successful page")
        } catch {
            #expect((error as? URLError)?.code == .cancelled || error is CancellationError)
        }
    }

    @Test func failedFallbackPreservesLoadedPosts() async throws {
        let fixture = FeedRequestFixture(mode: .failed)
        let model = makeModel(repository: fixture.repository)
        let previousUser = SupabaseAuthService.shared.currentUser
        SupabaseAuthService.shared.currentUser = fixture.user
        defer { SupabaseAuthService.shared.currentUser = previousUser }
        let existing = makePost(userID: fixture.user.id)
        model.posts = [existing]
        model.newPostsAvailable = 3

        await model.refresh()

        #expect(model.posts.map(\.id) == [existing.id])
        #expect(model.newPostsAvailable == 3)
        #expect(model.error != nil)
        #expect(!model.isRefreshing)
    }

    @Test func genuineEmptyServerPageClearsLoadedPosts() async throws {
        let fixture = FeedRequestFixture(mode: .empty)
        let model = makeModel(repository: fixture.repository)
        let previousUser = SupabaseAuthService.shared.currentUser
        SupabaseAuthService.shared.currentUser = fixture.user
        defer { SupabaseAuthService.shared.currentUser = previousUser }
        model.posts = [makePost(userID: fixture.user.id)]

        await model.refresh()

        #expect(model.posts.isEmpty)
        #expect(!model.hasMorePages)
        #expect(model.error == nil)
        #expect(!model.isRefreshing)
    }

    @Test func alreadyCancelledTaskDoesNotReturnCachedOrEmptySuccess() async {
        let fixture = FeedRequestFixture(mode: .empty)
        let request = Task { @MainActor in
            // Cancel before fetch enters the repository, including its cache paths.
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await fixture.repository.fetchFeed(userId: fixture.user.id, cursor: nil)
                return false
            } catch {
                return error is CancellationError || (error as? URLError)?.code == .cancelled
            }
        }
        #expect(await request.value)
    }

    private func makeModel(repository: PostRepository) -> FeedViewModel {
        FeedViewModel(postRepository: repository, authService: .shared,
                      realtimeService: RealtimeService(client: repository.client),
                      notificationCenter: NotificationCenter())
    }

    private func makePost(userID: UUID) -> PostWithAuthor {
        let post = WorkoutPost(userId: userID, workoutData: CompletedWorkout(date: .now, entries: []), visibility: .friends)
        return PostWithAuthor(id: post.id, post: post, author: UserProfile(id: userID, username: "fixture"))
    }
}

@MainActor
private final class FeedRequestFixture {
    let user: AuthUser
    let repository: PostRepository
    private let session: URLSession
    var paths: [String] { FeedRequestProtocol.recordedPaths() }

    init(mode: FeedRequestProtocol.Mode) {
        user = AuthUser(id: UUID(), email: "fixture@example.invalid", profile: nil)
        FeedRequestProtocol.configure(mode: mode)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedRequestProtocol.self]
        session = URLSession(configuration: configuration)
        repository = PostRepository(client: SupabaseClient(
            supabaseURL: URL(string: "https://feed-fixture.invalid")!,
            supabaseKey: "fixture-key",
            options: .init(global: .init(session: session))
        ))
        repository.invalidateFeedCache()
    }

    deinit { session.invalidateAndCancel() }
}

private final class FeedRequestProtocol: URLProtocol, @unchecked Sendable {
    enum Mode { case cancelledRPC, cancelledFallback, failed, empty }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode = Mode.empty
    nonisolated(unsafe) private static var paths: [String] = []

    static func configure(mode: Mode) {
        lock.lock()
        defer { lock.unlock() }
        Self.mode = mode
        paths = []
    }

    static func recordedPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let mode = Self.mode
        Self.paths.append(request.url!.path)
        Self.lock.unlock()
        let isRPC = request.url!.path.hasSuffix("/rpc/get_friend_feed")
        if (isRPC && mode == .cancelledRPC) || (!isRPC && mode == .cancelledFallback) {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let failed = mode == .failed || (isRPC && mode == .cancelledFallback)
        let status = failed ? 404 : 200
        let data = Data((failed ? "{\"message\":\"Fixture request failed\",\"code\":\"fixture\"}" : "[]").utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
