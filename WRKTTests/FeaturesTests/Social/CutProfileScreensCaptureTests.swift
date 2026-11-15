import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only captures. No hosts, repositories, account data, photo library, or RealityKit.
/// TEST_RUNNER_VOLIA_CAPTURE_BATCH6=1, TEST_RUNNER_VOLIA_CAPTURE_DIR=<directory>.
/// VOLIA_CAPTURE_STATE selects one fixture for a fresh test host when simulator caches omit layers.
@MainActor
@Suite(.serialized)
struct CutProfileScreensCaptureTests {
    nonisolated static let names = [
        "profile-own", "profile-friend", "profile-muted", "profile-not-friend", "profile-request-sent", "profile-request-received",
        "profile-private", "profile-blocked", "profile-empty", "profile-loading", "profile-error", "profile-battle", "profile-posts-loading",
        "profile-own-ax", "profile-own-ax-bottom", "profile-other-ax", "profile-other-ax-mid", "profile-other-ax-bottom",
        "edit-profile", "edit-profile-error",
        "compose-plus", "compose-award", "compose-multi", "compose-weekly", "compose-error", "compose-uploading", "compose-map-generating",
        "compose-loading", "compose-no-workouts", "compose-award-ax", "compose-award-ax-mid", "compose-award-ax-bottom", "compose-plus-ax", "compose-plus-ax-bottom",
        "workout-picker", "partner-picker", "partner-picker-loading", "partner-picker-empty",
        "edit-post", "edit-post-cleared", "edit-post-route", "edit-post-route-error",
        "image-viewer", "image-viewer-loading", "image-viewer-empty"
    ]
    nonisolated static var selectedNames: [String] {
        guard let name = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"] else { return names }
        precondition(names.contains(name), "Unknown capture fixture")
        return [name]
    }
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-batch6")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_BATCH6"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let isAccessibility = name.contains("-ax")
        let isProfile = name.hasPrefix("profile-")
        let isCompose = name.hasPrefix("compose-")
        let isSheet = name.hasPrefix("edit-") || name.contains("picker")
        let tall = !isAccessibility && ((isProfile && !["profile-loading", "profile-error"].contains(name)) || (isCompose && !["compose-loading", "compose-no-workouts", "compose-uploading", "compose-map-generating"].contains(name)))
        if tall { window.frame.size.height = isProfile ? (name.contains("own") || name == "profile-empty" ? 1_500 : 2_400) : 1_800 }
        let content = fixture(name).environment(\.dynamicTypeSize, isAccessibility ? .accessibility5 : .large)
        window.rootViewController = UIHostingController(rootView: Group {
            if isProfile { CutProfileCaptureNavigation { content } }
            else if isSheet { Color.black.sheet(isPresented: .constant(true)) { content } }
            else { content }
        }.preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        try await Task.sleep(for: .seconds(2))
        if name.hasSuffix("-mid") || name.hasSuffix("-bottom"), let scroll = verticalScroll(in: window) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: name.hasSuffix("-mid") ? bottom / 2 : bottom), animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = tall ? 2 : 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent(name + ".png"))
    }

    private func fixture(_ name: String) -> AnyView {
        if name.hasPrefix("profile-") { return AnyView(profile(name)) }
        if name.hasPrefix("edit-profile") {
            return AnyView(CutEditProfileView(model: CutEditProfileLogic.model(isSaving: false,
                error: name.hasSuffix("error") ? CutEditProfileLogic.errorLine(SupabaseError.invalidUsername.localizedDescription) : nil),
                draft: .constant(.init(displayName: "Fixture Athlete", bio: "Synthetic training note for layout checks.", isPrivate: true))))
        }
        if name.hasPrefix("compose-") { return AnyView(compose(name)) }
        if name == "workout-picker" {
            return AnyView(CutPostComposeWorkoutPickerView(workouts: [CutPostComposeFixtures.strength, CutPostComposeFixtures.cardio].map { CutPostComposeLogic.workout($0) }, selectedIDs: [CutPostComposeFixtures.firstID]))
        }
        if name.hasPrefix("partner-picker") {
            return AnyView(CutPostComposePartnerPickerView(friends: name.hasSuffix("empty") ? [] : [CutPostComposeFixtures.partner],
                selectedID: CutPostComposeFixtures.partner.id, isLoading: name.hasSuffix("loading")))
        }
        if name.hasPrefix("edit-post") {
            let draft = CutEditPostDraft(caption: name == "edit-post-cleared" ? "" : "Fixture caption", visibility: .friends)
            return AnyView(CutEditPostView(model: CutEditPostLogic.model(draft: draft, originalCaption: "Fixture caption", originalVisibility: .friends,
                isOwn: true, isCardio: name.contains("route"), healthKitLinked: true, hasImages: false,
                route: name.hasSuffix("error") ? .failed : .unknown), draft: .constant(draft)))
        }
        return AnyView(CutImageViewerView(model: CutImageViewerLogic.model(name.hasSuffix("empty") ? [] : ["fixture-first", "fixture-second"]), selectedIndex: .constant(0)) { item in
            if name.hasSuffix("loading") { ProgressView().tint(.white) }
            else { Image(uiImage: fixtureImage).resizable().scaledToFit().padding(24).accessibilityLabel("Fixture image \(item.id + 1)") }
        })
    }
    private func profile(_ name: String) -> some View {
        var facts = CutProfileFixtures.profile
        facts.name = name.contains("-ax") ? "Fixture Athlete With A Long Display Name" : "Fixture Athlete"
        facts.username = "fixture_athlete"
        facts.bio = "Synthetic profile used only for layout checks. Strength and trail running."
        facts.isOwn = name.contains("own") || name == "profile-empty"
        switch name {
        case "profile-not-friend": facts.friendship = .none
        case "profile-request-sent": facts.friendship = .pendingSent
        case "profile-request-received": facts.friendship = .pendingReceived
        case "profile-muted": facts.isMuted = true
        case "profile-private": facts.isPrivate = true; facts.friendship = .none; facts.posts = []
        case "profile-blocked": facts.isBlocked = true; facts.friendship = .none; facts.posts = []
        case "profile-empty": facts.posts = []
        case "profile-posts-loading": facts.isLoadingPosts = true
        case "profile-battle": facts.battle = .init(type: "Volume", days: 7, start: CutProfileFixtures.now)
        default: break
        }
        let model = CutProfileLogic.model(name == "profile-loading" || name == "profile-error" ? nil : facts,
            error: name == "profile-error" ? "Failed to load profile. Please try again." : nil,
            now: CutProfileFixtures.now, calendar: CutProfileFixtures.calendar, locale: Locale(identifier: "en_US"))
        return CutProfileView(model: model, avatarPicker: {
            if model.isOwn {
                Button("Change profile photo", systemImage: "camera.fill") {}.labelStyle(.iconOnly)
                    .buttonStyle(CutIconButtonStyle(tone: .lime, diameter: 44))
            }
        }, showcase: {
            ZStack {
                Rectangle().fill(DS.Cut.Colors.controlFill)
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell").font(.system(size: 40))
                    Text("Unchanged 3D showcase").cutFont(.body)
                    Text("Fixture placeholder").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                }
            }.frame(height: 240)
        })
    }
    private func compose(_ name: String) -> some View {
        typealias F = CutPostComposeFixtures
        let award = name.contains("award")
        let noSelection = name.contains("plus") || name == "compose-no-workouts" || name == "compose-loading"
        let multi = name == "compose-multi" || name == "compose-weekly"
        var model = CutPostComposeLogic.model(title: award ? "Share Year" : name == "compose-weekly" ? "Share Progress" : "Share Workout",
            selected: noSelection ? [] : multi ? [F.strength, F.cardio] : [F.strength], available: name == "compose-no-workouts" ? [] : [F.strength, F.cardio],
            uploading: name == "compose-uploading", generatingMap: name == "compose-map-generating",
            weekly: name == "compose-weekly" ? F.weekly : nil, partner: name == "compose-multi" ? F.partner : nil,
            attached: award, pickedPrivacy: award || multi ? [false] : [], map: multi,
            errorTitle: name == "compose-error" ? "Sharing failed" : nil,
            errorMessage: name == "compose-error" ? "Fixture connection error. Please try again." : nil, errorIsRetryable: true)
        if name == "compose-loading" { model.isInitializing = true }
        return CutPostComposeView(model: model, caption: .constant(award ? "A synthetic year-award caption, prefilled by the caller." : "Fixture caption"),
            visibility: .constant(.friends), image: { _ in Image(uiImage: fixtureImage) }, photoPicker: {
                Button("Add Photos", systemImage: "photo.on.rectangle.angled") {}.cutFont(.body).frame(minHeight: 44).buttonStyle(.plain)
            })
    }
    private var fixtureImage: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            UIColor(red: 0.8, green: 1, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 35, y: 35, width: 40, height: 110))
            context.fill(CGRect(x: 90, y: 70, width: 40, height: 75))
            ("FIXTURE IMAGE" as NSString).draw(at: CGPoint(x: 150, y: 85), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.white])
        }
    }
    private func verticalScroll(in view: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.bounds.height > 120, scroll.contentSize.height > scroll.bounds.height,
               scroll.contentSize.height - scroll.bounds.height > (best.map { $0.contentSize.height - $0.bounds.height } ?? 0) { best = scroll }
            view.subviews.forEach(visit)
        }
        visit(view)
        return best
    }
}

private struct CutProfileCaptureNavigation<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var path = [1]
    var body: some View {
        NavigationStack(path: $path) {
            Color.black.toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Int.self) { _ in
                    content().navigationTitle(Text(verbatim: "")).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
                }
        }.tint(DS.Cut.Colors.lime)
    }
}
