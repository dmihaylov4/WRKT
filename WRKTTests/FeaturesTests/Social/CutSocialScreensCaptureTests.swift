import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the pushed Cut Social screens. Writes to /private/tmp/volia-cut-social-screens,
/// or VOLIA_CAPTURE_DIR.
///
/// VOLIA_CAPTURE_CUT_SOCIAL_SCREENS=1 (pass TEST_RUNNER_VOLIA_CAPTURE_CUT_SOCIAL_SCREENS=1 to
/// xcodebuild) renders each screen from fixtures as it is pushed in the Social tab: one file per
/// state. Tall captures (-full) show the whole scroll content in one image.
@MainActor
@Suite(.serialized)
struct CutSocialScreensCaptureTests {
    private typealias D = CutPostDetailFixtures
    private typealias F = CutSocialFixtures

    static let enabled = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT_SOCIAL_SCREENS"] == "1"

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-social-screens")
    }

    // MARK: Post detail

    @Test(.enabled(if: enabled))
    func capturePostDetail() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        func detail(_ facts: CutPostDetailFacts, open: Set<Int> = [], text: String = "", map: Bool = false) -> some View {
            CutPostDetailView(model: CutPostDetailLogic.model(facts, now: F.now, weightUnit: .kg, locale: F.locale),
                              commentText: .constant(text), openExercises: open) {
                if map {
                    Rectangle()
                        .fill(DS.Cut.Colors.darkField)
                        .frame(height: 200)
                        .overlay(Image(systemName: "map").font(.system(size: 34)).foregroundStyle(DS.Cut.Colors.textSecondary))
                }
            }
        }

        try await capture(detail(D.strength(), open: [0]), name: "post-strength")
        try await capture(detail(D.strength(), open: [0]), name: "post-strength-full", height: 2_400)
        try await capture(detail(D.cardio(), map: true), name: "post-cardio-full", height: 2_600)
        try await capture(detail(D.multi(), open: [1]), name: "post-multi-full", height: 2_800)
        try await capture(detail(D.strength(comments: [], loading: true)), name: "post-comments-loading-full", height: 2_000)
        try await capture(detail(D.strength(comments: [])), name: "post-comments-empty-full", height: 2_000)
        try await capture(detail(D.strength(comments: [], error: "The Internet connection appears to be offline.")),
                          name: "post-comments-error-full", height: 2_000)

        var weekly = D.strength()
        weekly.post = F.weekly()
        try await capture(detail(weekly), name: "post-weekly")
        var battle = D.strength(comments: [])
        battle.post = F.battle()
        try await capture(detail(battle), name: "post-battle")

        var composing = D.strength()
        composing.commentText = "@ma"
        composing.replyingTo = .init(id: D.alex, username: "alex", name: "Alex J.")
        composing.suggestions = [.init(id: UUID(), username: "maria", name: "Maria K."), .init(id: UUID(), username: "marco", name: "Marco T.")]
        try await capture(detail(composing, text: "@ma"), name: "post-composer-reply")
        var failed = D.strength(error: "Failed to delete comment")
        failed.commentText = ""
        try await capture(detail(failed), name: "post-composer-error")

        try await capture(detail(D.long(), open: [0]), name: "post-long")
        try await capture(detail(D.long(), open: [0]), name: "post-long-full", height: 2_400)
        try await capture(detail(D.strength(), open: [0]), name: "post-strength-xxxl", dynamicType: .xxxLarge)
        try await capture(detail(D.long(), open: [0]), name: "post-long-xxxl", dynamicType: .xxxLarge)

        try await capture(CutPostLoaderStateView(state: .loading), name: "post-loader-loading")
        try await capture(CutPostLoaderStateView(state: .failed(CutPostDetailLogic.notFoundMessage)), name: "post-loader-failed")
    }

    // MARK: People

    @Test(.enabled(if: enabled))
    func capturePeople() async throws {
        typealias P = CutSocialPeopleFixtures
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        func activity(_ facts: [CutActivityFacts]?, loading: Bool = false, error: String? = nil) -> CutActivityView {
            CutActivityView(model: CutSocialPeopleLogic.activity(facts, isLoading: loading, error: error, now: F.now,
                                                                 calendar: P.calendar, locale: F.locale))
        }
        try await capture(activity(P.activity), name: "activity")
        try await capture(activity(nil), name: "activity-loading")
        try await capture(activity([]), name: "activity-empty")
        try await capture(activity([], error: "Unable to connect to the server. Check your internet connection."), name: "activity-error")
        try await capture(activity(P.activity, error: "Could not delete the notification."), name: "activity-inline-error")
        try await capture(activity(P.longActivity), name: "activity-long")
        try await capture(activity(P.longActivity), name: "activity-xxxl", dynamicType: .xxxLarge)

        func requests(_ tab: CutFriendRequestsModel.Tab, incoming: [CutFriendRequestFacts]? = P.incoming,
                      outgoing: [CutFriendRequestFacts]? = P.outgoing, loading: Bool = false, error: String? = nil) -> CutFriendRequestsView {
            CutFriendRequestsView(model: CutSocialPeopleLogic.requests(incoming: incoming, outgoing: outgoing, tab: tab,
                                                                        isLoading: loading, error: error))
        }
        try await capture(requests(.incoming), name: "requests")
        try await capture(requests(.outgoing), name: "requests-sent")
        try await capture(requests(.incoming, incoming: nil, outgoing: nil, loading: true), name: "requests-loading")
        try await capture(requests(.incoming, incoming: [], outgoing: []), name: "requests-empty")
        try await capture(requests(.outgoing, incoming: [], outgoing: []), name: "requests-sent-empty")
        try await capture(requests(.incoming, incoming: [], outgoing: [], error: "Failed to load requests: The Internet connection appears to be offline."),
                          name: "requests-error")
        var long = P.incoming
        long[0].person.displayName = "Maximiliana Alexandrova-Fitzgerald Montgomery"
        try await capture(requests(.incoming, incoming: long), name: "requests-long")
        try await capture(requests(.incoming, incoming: long), name: "requests-xxxl", dynamicType: .xxxLarge)

        func friends(_ facts: [CutFriendFacts]?, query: String = "", loading: Bool = false, error: String? = nil) -> CutFriendsListView {
            CutFriendsListView(model: CutSocialPeopleLogic.friends(facts, query: query, isLoading: loading, error: error, locale: F.locale),
                               query: .constant(query))
        }
        try await capture(friends(P.friends), name: "friends")
        try await capture(friends(P.friends, query: "alex"), name: "friends-search")
        try await capture(friends(P.friends, query: "zz"), name: "friends-no-results")
        try await capture(friends(nil), name: "friends-loading")
        try await capture(friends([]), name: "friends-empty")
        try await capture(friends([], error: "Failed to load friends: The Internet connection appears to be offline."), name: "friends-error")
        try await capture(friends(P.friends), name: "friends-xxxl", dynamicType: .xxxLarge)

        func search(_ query: String, results: [CutSocialPersonFacts] = [], searching: Bool = false, error: String? = nil) -> CutUserSearchView {
            CutUserSearchView(model: CutSocialPeopleLogic.search(query: query, results: results, isSearching: searching, error: error),
                              query: .constant(query))
        }
        try await capture(search("nin", results: P.searchResults), name: "search")
        try await capture(search(""), name: "search-idle")
        try await capture(search("nin", searching: true), name: "search-searching")
        try await capture(search("zzz"), name: "search-no-results")
        try await capture(search("nin", error: "Search failed: The Internet connection appears to be offline."), name: "search-error")
        var longResults = P.searchResults
        longResults[0].displayName = "Maximiliana Alexandrova-Fitzgerald Montgomery"
        try await capture(search("maximiliana_the_very_long_handle", results: longResults), name: "search-long")
        try await capture(search("nin", results: longResults), name: "search-xxxl", dynamicType: .xxxLarge)
    }

    // MARK: Helpers

    func capture<V: View>(_ view: V, name: String, height: CGFloat? = nil, dynamicType: DynamicTypeSize = .large) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        if let height {
            window.frame = CGRect(origin: .zero, size: CGSize(width: window.bounds.width, height: height))
        }
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: CutPushedCaptureShell { view }.environment(\.dynamicTypeSize, dynamicType)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        let format = UIGraphicsImageRendererFormat()
        // Windows taller than about 2,800 pt come back blank, so tall captures stay at or under that.
        format.scale = height.map { min(2, 5_400 / $0) } ?? 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent("\(name).png"))
    }
}

/// A screen as the Social tab pushes it: one level deep in a NavigationStack in the third tab
/// of a system tab bar, so the system back button shows.
struct CutPushedCaptureShell<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var tab = 2
    @State private var path: [Int] = [1]

    var body: some View {
        TabView(selection: $tab) {
            Tab("Train", image: "tab-train-inactive", value: 0) { Color.black }
            Tab("Plan", image: "tab-plan-inactive", value: 1) { Color.black }
            Tab("Social", image: "tab-social", value: 2) {
                NavigationStack(path: $path) {
                    Color.black
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Int.self) { _ in content() }
                }
            }
            Tab("Cardio", image: "tab-cardio-inactive", value: 3) { Color.black }
            Tab("Me", image: "tab-profile-inactive", value: 4) { Color.black }
        }
        .tint(DS.Palette.marone)
    }
}
