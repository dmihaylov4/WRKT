import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in native presentations using invented fixtures and inert actions only.
/// No production hosts, photo library, server calls or HealthKit writes.
@MainActor
@Suite(.serialized)
struct CutSheets3CaptureTests {
    nonisolated static let names = [
        "P164",
        "P164-ax",
        "P166",
        "P166-ax",
        "P046",
        "P046-ax",
        "P055",
        "P055-ax",
        "P208",
        "P208-ax",
        "P228",
        "P228-ax",
        "P155",
        "P155-ax",
        "P156",
        "P156-ax",
        "P157",
        "P157-ax",
        "P168",
        "P168-ax",
        "P158",
        "P158-ax",
        "P167",
        "P167-ax",
        "P159",
        "P159-ax",
        "P162",
        "P162-ax",
        "P165",
        "P165-ax",
        "P169",
        "P169-ax",
        "P170",
        "P170-ax",
        "P059",
        "P059-ax",
        "P214",
        "P214-ax",
        "P215",
        "P215-ax",
        "stack",
        "stack-ax",
        "P164-ax-bottom",
        "P166-ax-bottom",
        "P055-ax-bottom",
        "P155-ax-bottom",
        "P156-ax-bottom",
        "P158-ax-bottom",
        "P162-ax-bottom",
        "P059-ax-bottom",
        "P214-ax-bottom",
        "stack-ax-bottom",
        "P164-empty",
        "P164-loading",
        "P164-error",
        "P164-error-ax-bottom",
        "P164-uploading",
        "P164-map-progress",
        "P156-empty",
        "P156-loading",
        "P157-empty",
        "P157-loading",
        "P157-error",
        "P157-long",
        "P157-long-ax-bottom",
        "P158-cleared",
        "P158-saving",
        "P162-error",
        "P162-saving",
        "P059-push"
    ]
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHEETS3"] == "1"), arguments: names)
    func capture(_ name: String) async throws {
        if let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHEETS3_CASE"],
           !selected.split(separator: ",").contains(Substring(name)) { return }
        let foreground = try await CutSheetsSceneWait.foregroundScene()
        let scene = try #require(foreground, "No foreground scene connected within ten seconds")
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/claude-501/-Users-dimitarmihaylov-dev-WRKT/48713954-6fde-43a2-bf59heets-3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let size: DynamicTypeSize = name.contains("-ax") ? .accessibility5 : .large
        window.rootViewController = UIHostingController(rootView: sceneView(name).environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        window.traitOverrides.preferredContentSizeCategory = name.contains("-ax") ? .accessibilityExtraExtraExtraLarge : .large
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(3))
        if name.hasSuffix("-bottom"), let scroll = largestScroll(window) {
            // Native List estimates offscreen row heights. Settle those estimates before
            // recording the footer, especially when accessibility rows become much taller.
            for _ in 0..<4 {
                let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
        if let path = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SIGNALS"] {
            let signals = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: signals, withIntermediateDirectories: true)
            try Data().write(to: signals.appendingPathComponent(name + ".ready"))
            let acknowledgement = signals.appendingPathComponent(name + ".ack")
            let deadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: acknowledgement.path), Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(FileManager.default.fileExists(atPath: acknowledgement.path))
        }
    }

    private func size(_ name: String) -> DynamicTypeSize { name.contains("-ax") ? .accessibility5 : .large }

    private func sceneView(_ name: String) -> AnyView {
        if name == "P059-push" {
            return AnyView(NavigationStack { cardio(inSheet: false).navigationTitle("Cardio").navigationBarTitleDisplayMode(.inline) })
        }
        if name.hasPrefix("stack") {
            return AnyView(train.sheet(isPresented: .constant(true)) {
                cardio(inSheet: true).sheet(isPresented: .constant(true)) {
                    compose("P046").environment(\.cutSheetDepth, 1).sheet(isPresented: .constant(true)) {
                        destination("P155").environment(\.cutSheetDepth, 2).environment(\.dynamicTypeSize, size(name))
                    }
                }
            })
        }
        if name.hasPrefix("P155") || name.hasPrefix("P156") {
            return AnyView(social.sheet(isPresented: .constant(true)) {
                compose("P164").sheet(isPresented: .constant(true)) {
                    destination(name).environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        if name.hasPrefix("P046") {
            return AnyView(train.sheet(isPresented: .constant(true)) {
                cardio(inSheet: true).sheet(isPresented: .constant(true)) {
                    compose(name).environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        let parent: AnyView
        if name.hasPrefix("P059") { parent = AnyView(train) }
        else if name.hasPrefix("P214") || name.hasPrefix("P215") {
            parent = AnyView(NavigationStack { CutHealthStrengthView(model: CutWorkoutDetailFixtures.strength()) })
        } else if name.hasPrefix("P162") { parent = AnyView(profile) }
        else if name.hasPrefix("P055") {
            parent = AnyView(NavigationStack {
                CutYearAwardPlaque(content: .init(year: 2026, headlineLines: ["YOU BUILT", "SOMETHING."], rows: [], footer: "Fixture year"), band: 0.5, highlight: .zero)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(DS.Cut.Colors.background)
            })
        } else if name.hasPrefix("P208") { parent = AnyView(NavigationStack { CutWinView(model: CutWinFixtures.plain) }) }
        else if name.hasPrefix("P228") {
            parent = AnyView(NavigationStack {
                CutLiveOverviewView(model: .init(title: "Fixture workout", startDate: CutWorkoutDetailFixtures.now,
                    summaryLine: "7 sets, 4260 kg", segments: [.current, .toDo], now: nil, nowPartners: [],
                    allDone: false, sections: [], canFinish: false), rest: .none, fixedElapsed: 120)
            })
        } else if ["P157", "P158", "P159", "P169", "P170"].contains(where: name.hasPrefix) { parent = AnyView(detail) }
        else { parent = AnyView(social) }
        if name.hasPrefix("P170") {
            return AnyView(parent.fullScreenCover(isPresented: .constant(true)) { destination(name).environment(\.dynamicTypeSize, size(name)) })
        }
        return AnyView(parent.sheet(isPresented: .constant(true)) { destination(name).environment(\.dynamicTypeSize, size(name)) })
    }

    private var train: some View {
        NavigationStack { CutTrainView(model: CutTrainFixtures.model(.planned(name: "Fixture workout", exerciseCount: 3))) }
    }
    private var social: some View {
        NavigationStack {
            CutSocialShell(header: .init(initials: "FA"), section: .feed) {
                CutSocialFeedView(model: .init(content: .posts(CutSocialFixtures.rows([CutSocialFixtures.strength(author: "Fixture Athlete")])))) { _ in EmptyView() }
            }
        }
    }
    private var detail: some View {
        var facts = CutPostDetailFixtures.strength(comments: [])
        facts.post.author.name = "Fixture Athlete"
        return NavigationStack {
            CutPostDetailView(model: CutPostDetailLogic.model(facts, now: CutSocialFixtures.now, weightUnit: .kg), commentText: .constant("")) { EmptyView() }
        }
    }
    private var profile: some View {
        var facts = CutProfileFixtures.profile
        facts.name = "Fixture Athlete"; facts.username = "fixture_athlete"; facts.bio = "Synthetic profile for layout checks."; facts.isOwn = true
        return NavigationStack {
            CutProfileView(model: CutProfileLogic.model(facts, now: CutProfileFixtures.now, calendar: CutProfileFixtures.calendar, locale: Locale(identifier: "en_US")),
                avatarPicker: { Button("Change profile photo", systemImage: "camera.fill") {}.labelStyle(.iconOnly).buttonStyle(CutIconButtonStyle(tone: .lime, diameter: 44)) }, showcase: { EmptyView() })
        }
    }
    private func cardio(inSheet: Bool) -> some View {
        CutCardioDetailView(model: CutCardioFixtures.detail(), inSheet: inSheet, tools: AnyView(Menu("More", systemImage: "ellipsis") {
            Button("Share workout") {}; Button("Refresh details") {}; Button("Delete workout", role: .destructive) {}
        }.labelStyle(.iconOnly).buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 44)))) { route.frame(height: 200) }
    }
    private var route: some View {
        ZStack {
            DS.Cut.Colors.controlFill
            Path { p in
                p.move(to: CGPoint(x: 45, y: 90)); p.addLines([.init(x: 90, y: 40), .init(x: 230, y: 80), .init(x: 280, y: 160), .init(x: 90, y: 190), .init(x: 45, y: 90)])
            }.stroke(DS.Cut.Colors.lime, lineWidth: 5)
        }
    }
    @ViewBuilder private func destination(_ name: String) -> some View {
        if ["P164", "P166", "P046", "P055", "P208", "P228"].contains(where: name.hasPrefix) { compose(name) }
        else if name.hasPrefix("P155") {
            CutPostComposeWorkoutPickerView(workouts: [CutPostComposeFixtures.strength, CutPostComposeFixtures.cardio].map { CutPostComposeLogic.workout($0) }, selectedIDs: [CutPostComposeFixtures.firstID])
        } else if name.hasPrefix("P156") {
            CutPostComposePartnerPickerView(friends: name.contains("empty") ? [] : [CutPostComposeFixtures.partner], selectedID: CutPostComposeFixtures.partner.id, isLoading: name.contains("loading"))
        } else if name.hasPrefix("P157") || name.hasPrefix("P168") {
            let count = name.contains("long") ? 24 : 3
            let people = (0..<count).map { index in CutLikesListModel.Person(id: UUID(), name: "Fixture Athlete \(index + 1)", handle: "@fixture_\(index + 1)", initials: "FA", avatarURL: nil) }
            CutLikesListView(model: .init(content: name.contains("empty") ? .empty : name.contains("loading") ? .loading : name.contains("error") ? .failed("Could not load likes. Please try again.") : .people(people)))
        } else if name.hasPrefix("P158") || name.hasPrefix("P167") {
            let draft = CutEditPostDraft(caption: name.contains("cleared") ? "" : "Fixture caption edited", visibility: .friends)
            CutEditPostView(model: CutEditPostLogic.model(draft: draft, originalCaption: "Fixture caption", originalVisibility: .friends,
                isOwn: true, isCardio: true, healthKitLinked: true, hasImages: false, saving: name.contains("saving")), draft: .constant(draft))
        } else if name.hasPrefix("P159") {
            CutSheetConfirm(CutPostDetailLogic.deleteTitle, message: CutPostDetailLogic.deleteMessage, primaryTitle: CutPostDetailLogic.deleteButton,
                cancelTitle: CutPostDetailLogic.deleteCancel, confirm: {}, cancel: {})
        } else if name.hasPrefix("P162") {
            CutEditProfileView(model: CutEditProfileLogic.model(isSaving: name.contains("saving"), error: name.contains("error") ? "Failed to save profile: Fixture connection error." : nil),
                draft: .constant(.init(displayName: "Fixture Athlete", bio: "Synthetic profile biography for layout checks.", isPrivate: true)))
        } else if name.hasPrefix("P165") {
            let person = CutBattleOpponent(id: CutPostComposeFixtures.firstID, name: "Fixture Friend", username: "fixture_friend", avatarURL: nil)
            let draft = CutCreateBattleDraft(opponentID: person.id)
            CutCreateBattleView(model: CutCreateBattleLogic.model(draft, opponent: person, friends: [person], creating: false, unit: .kg), draft: .constant(draft))
        } else if name.hasPrefix("P169") {
            CutImageViewerView(model: CutImageViewerLogic.model(["fixture-image"]), selectedIndex: .constant(0)) { _ in Image(uiImage: fixtureImage).resizable().scaledToFit().padding(24) }
        } else if name.hasPrefix("P170") {
            CutPostDetailMapView(close: {}) { route.frame(maxHeight: .infinity) }
        } else if name.hasPrefix("P059") { cardio(inSheet: true) }
        else if name.hasPrefix("P214") {
            CutWorkoutEditorView(model: .init(dateLine: "Friday 13 Nov", isSyncedWithWatch: false, rows: [], canSave: true), name: .constant("Fixture workout"))
        } else {
            CutSheetConfirm("Delete workout?", message: "Your logged workout will be deleted. You can undo this.", primaryTitle: "Delete workout", cancelTitle: "Keep workout", confirm: {}, cancel: {})
        }
    }
    private func compose(_ name: String) -> some View {
        typealias F = CutPostComposeFixtures
        let award = name.hasPrefix("P055")
        let weekly = name.hasPrefix("P166")
        var model = CutPostComposeLogic.model(title: award ? "Share Year" : weekly ? "Share Progress" : "Share Workout",
            selected: name.contains("empty") || name.hasSuffix("-loading") ? [] : weekly ? [F.strength, F.cardio] : [F.strength],
            available: name.contains("empty") ? [] : [F.strength, F.cardio], uploading: name.contains("uploading"), generatingMap: name.contains("map-progress"),
            weekly: weekly ? F.weekly : nil, partner: weekly ? F.partner : nil, attached: award, pickedPrivacy: award ? [false] : [], map: weekly,
            errorTitle: name.contains("error") ? "Sharing failed" : nil, errorMessage: name.contains("error") ? "Fixture connection error. Please try again." : nil, errorIsRetryable: true)
        if name.hasSuffix("-loading") { model.isInitializing = true }
        return CutPostComposeView(model: model, caption: .constant(award ? "A synthetic year-award caption, prefilled by the caller." : "Fixture caption"), visibility: .constant(.friends),
            image: { _ in Image(uiImage: fixtureImage) }, photoPicker: {
                Button("Add Photos", systemImage: "photo.on.rectangle.angled") {}.cutFont(.body).frame(minHeight: 44).buttonStyle(.plain)
            })
    }
    private var fixtureImage: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            UIColor.white.setFill(); context.fill(CGRect(x: 35, y: 35, width: 40, height: 110))
            ("FIXTURE IMAGE" as NSString).draw(at: CGPoint(x: 110, y: 85), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.white])
        }
    }
    private func largestScroll(_ view: UIView, requiringOverflow: Bool = true) -> UIScrollView? {
        var result: [UIScrollView] = []
        func visit(_ v: UIView) {
            if let scroll = v as? UIScrollView, !requiringOverflow || scroll.contentSize.height > scroll.bounds.height { result.append(scroll) }
            v.subviews.forEach(visit)
        }
        var controller = view.window?.rootViewController ?? (view as? UIWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        visit(controller?.view ?? view)
        return result.max { $0.bounds.height < $1.bounds.height }
    }
}
