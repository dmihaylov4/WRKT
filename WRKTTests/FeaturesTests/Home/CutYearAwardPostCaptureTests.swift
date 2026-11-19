import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the year award's shared picture in every frame a post's picture is shown
/// in, from fixtures: nothing is posted. Writes to /private/tmp/volia-award-post, or
/// VOLIA_CAPTURE_DIR.
///
/// VOLIA_CAPTURE_AWARD_POST=1 and VOLIA_AWARD_PICTURES=<folder of .png pictures> (pass both with
/// the TEST_RUNNER_ prefix to xcodebuild) render, for each picture: the feed card, the post
/// detail and the full screen viewer at the widths of an iPhone 14 Pro and a Pro Max, and the
/// composer. The media views stand in for the hosts' image loaders with the same frames: the
/// card's width (or the screen's) by 200 points, filled and clipped; the viewer fits.
@MainActor
@Suite(.serialized)
struct CutYearAwardPostCaptureTests {
    private typealias F = CutSocialFixtures
    private typealias D = CutPostDetailFixtures

    static let enabled = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_AWARD_POST"] == "1"

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-award-post")
    }

    private static let caption = "My 2026 in Volia\n430,000 kg\n1,284 km\n31 weeks"
    /// The phones the frames are checked on: the owner's 14 Pro and the widest current phone.
    private static let screens = [CGSize(width: 393, height: 852), CGSize(width: 440, height: 956)]

    @Test(.enabled(if: enabled))
    func capturePictureInPostFrames() async throws {
        let folder = try #require(ProcessInfo.processInfo.environment["VOLIA_AWARD_PICTURES"])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".png") }.sorted()
        for file in files {
            let picture = try #require(UIImage(contentsOfFile: (folder as NSString).appendingPathComponent(file)))
            let name = (file as NSString).deletingPathExtension
            for screen in Self.screens {
                let width = Int(screen.width)
                try await capture(feed(picture), size: screen, name: "\(name)-feed-\(width)")
                try await capture(detail(picture), size: screen, name: "\(name)-detail-\(width)")
                try await capture(viewer(picture), size: screen, name: "\(name)-viewer-\(width)")
            }
            try await capture(composer(picture), size: CGSize(width: 393, height: 1_500), name: "\(name)-composer-393-full")
        }
    }

    // MARK: Frames

    /// As `CutSocialPostMedia` draws a picture: one page of a paged TabView, 200 points tall.
    private func media(_ picture: UIImage) -> some View {
        TabView {
            Image(uiImage: picture)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .tag(0)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 200)
    }

    private var awardPost: CutSocialPostFacts {
        CutSocialPostFacts(id: UUID(), author: .init(id: D.me, name: "Dimitar M."), createdAt: F.now.addingTimeInterval(-600),
                           caption: Self.caption,
                           kind: .cardio(name: "Running", distanceMeters: 6_200, durationSeconds: 2_400, calories: 326,
                                         averageHeartRate: 148),
                           likes: 4, comments: 1, isOwn: true)
    }

    private func feed(_ picture: UIImage) -> some View {
        let model = CutSocialFeedModel(content: .posts(F.rows([awardPost, F.strength()])), reachedEnd: true)
        return TabView(selection: .constant(2)) {
            Tab("Social", image: "tab-social", value: 2) {
                NavigationStack {
                    CutSocialShell(header: CutSocialHeaderModel(notifications: 0, friendRequests: 0, initials: "DM"),
                                   section: .feed) {
                        CutSocialFeedView(model: model) { row in
                            if row.title == "Running" { media(picture) }
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }

    private func detail(_ picture: UIImage) -> some View {
        var facts = D.cardio()
        facts.post = awardPost
        facts.workouts[0].name = "Running"
        return CutPushedCaptureShell {
            CutPostDetailView(model: CutPostDetailLogic.model(facts, now: F.now, weightUnit: .kg, locale: F.locale),
                              commentText: .constant("")) { media(picture) }
        }
    }

    private func viewer(_ picture: UIImage) -> some View {
        CutImageViewerView(model: CutImageViewerLogic.model(["award"]), selectedIndex: .constant(0), close: {}) { _ in
            Image(uiImage: picture).resizable().scaledToFit()
        }
    }

    private func composer(_ picture: UIImage) -> some View {
        let run = CutPostComposeWorkoutFacts(id: UUID(), title: "Running", date: F.now, icon: "figure.run", isCardio: true,
                                             durationSeconds: 2_400, calories: 326)
        let model = CutPostComposeLogic.model(title: "Share Award", selected: [run], available: [run], attached: true,
                                              locale: F.locale)
        return CutPostComposeView(model: model, caption: .constant(Self.caption), visibility: .constant(.friends),
                                  image: { _ in Image(uiImage: picture) }, photoPicker: {
            Label("Add Photos", systemImage: "photo.on.rectangle.angled").cutFont(.body).frame(minHeight: 44)
        })
    }

    // MARK: Capture

    private func capture<V: View>(_ view: V, size: CGSize, name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        try await Task.sleep(for: .seconds(1.5))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent("\(name).png"))
    }
}
