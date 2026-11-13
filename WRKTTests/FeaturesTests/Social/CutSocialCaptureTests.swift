import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut Social tab. Writes to /private/tmp/volia-cut-social, or VOLIA_CAPTURE_DIR.
///
/// VOLIA_CAPTURE_CUT_SOCIAL=1 (pass TEST_RUNNER_VOLIA_CAPTURE_CUT_SOCIAL=1 to xcodebuild) renders
/// the Cut Social shell from fixtures, one file per state: social-<state>.png. Feed states,
/// one post of each kind on its own, the Friends pane, and accessibility Dynamic Type.
@MainActor
struct CutSocialCaptureTests {
    private typealias F = CutSocialFixtures

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-social")
    }

    private static let header = CutSocialHeaderModel(notifications: 3, friendRequests: 2, initials: "DM")

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT_SOCIAL"] == "1"))
    func captureFixtureStates() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let feed = F.rows([F.strength(), F.cardio(), F.shared(), F.weekly(), F.battle()])
        let feedStates: [(String, CutSocialFeedModel)] = [
            ("feed-posts", CutSocialFeedModel(content: .posts(feed), newPosts: 3, arena: F.arena, reachedEnd: true)),
            ("feed-empty", CutSocialFeedModel(content: .empty)),
            ("feed-loading", CutSocialFeedModel(content: .loading)),
            ("feed-error", CutSocialFeedModel(content: .failed(title: "Connection Error",
                                                                  message: "Unable to connect to the server. Check your internet connection.",
                                                                  canRetry: true))),
            ("feed-offline-error", CutSocialFeedModel(content: .posts(F.rows([F.strength(), F.cardio()])), offlineQueue: 2,
                                                      inlineError: "Could not refresh the feed.", isLoadingMore: true)),
            ("post-workout", CutSocialFeedModel(content: .posts(F.rows([F.strength()])), reachedEnd: true)),
            ("post-cardio", CutSocialFeedModel(content: .posts(F.rows([F.cardio()])), reachedEnd: true)),
            ("post-shared", CutSocialFeedModel(content: .posts(F.rows([F.shared()])), reachedEnd: true)),
            ("post-weekly-battle", CutSocialFeedModel(content: .posts(F.rows([F.weekly(), F.battle()])), reachedEnd: true)),
            ("post-long", CutSocialFeedModel(content: .posts(F.rows([F.longPost()])), reachedEnd: true))
        ]
        for (name, model) in feedStates {
            try await capture(.feed(model), to: root.appendingPathComponent("social-\(name).png"))
        }
        try await capture(.feed(CutSocialFeedModel(content: .posts(feed), newPosts: 3, arena: F.arena)), dynamicType: .xxxLarge,
                          to: root.appendingPathComponent("social-feed-xxxl.png"))
        try await capture(.feed(CutSocialFeedModel(content: .posts(F.rows([F.longPost()])))), dynamicType: .xxxLarge,
                          to: root.appendingPathComponent("social-post-long-xxxl.png"))

        let friends = CutSocialLogic.friends(F.friendFacts, requests: 2, now: F.now, locale: F.locale)
        try await capture(.friends(friends), to: root.appendingPathComponent("social-friends.png"))
        try await capture(.friends(CutSocialLogic.friends([], requests: 0, now: F.now)), to: root.appendingPathComponent("social-friends-empty.png"))
        try await capture(.friends(friends), dynamicType: .xxxLarge, to: root.appendingPathComponent("social-friends-xxxl.png"))
    }

    // MARK: Helpers

    private func capture(_ pane: CutSocialCaptureShell.Pane, dynamicType: DynamicTypeSize = .large, to url: URL) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: CutSocialCaptureShell(header: Self.header, pane: pane).environment(\.dynamicTypeSize, dynamicType)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }
}

/// The Social tab as the app shell hosts it: inside a NavigationStack in the third tab of a
/// system tab bar.
private struct CutSocialCaptureShell: View {
    enum Pane {
        case feed(CutSocialFeedModel)
        case friends(CutSocialFriendsModel)
    }

    let header: CutSocialHeaderModel
    let pane: Pane
    @State private var tab = 2

    var body: some View {
        TabView(selection: $tab) {
            Tab("Train", image: "tab-train-inactive", value: 0) { Color.black }
            Tab("Plan", image: "tab-plan-inactive", value: 1) { Color.black }
            Tab("Social", image: "tab-social", value: 2) {
                NavigationStack {
                    content
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            Tab("Cardio", image: "tab-cardio-inactive", value: 3) { Color.black }
            Tab("Me", image: "tab-profile-inactive", value: 4) { Color.black }
        }
        .tint(DS.Palette.marone)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .feed(let model):
            CutSocialShell(header: header, section: .feed) {
                CutSocialFeedView(model: model) { row in
                    // Stands in for a route map: the host loads the real images.
                    if row.title == "Morning Run" {
                        Rectangle()
                            .fill(DS.Cut.Colors.darkField)
                            .frame(height: 200)
                            .overlay(Image(systemName: "map").font(.system(size: 34)).foregroundStyle(DS.Cut.Colors.textSecondary))
                    }
                }
            }
        case .friends(let model):
            CutSocialShell(header: header, section: .friends) {
                CutSocialFriendsView(model: model)
            }
        }
    }
}
