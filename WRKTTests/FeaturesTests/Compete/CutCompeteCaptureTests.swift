import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering: no hosts, accounts, repositories or server operations.
/// Opt in with TEST_RUNNER_VOLIA_CAPTURE_BATCH7=1 (and TEST_RUNNER_VOLIA_CAPTURE_STATE for one state).
/// Sheets are presented over the loaded Compete tab so their surface shows against the app; the
/// all-friends sheet is stacked on the new battle sheet.
@MainActor
@Suite(.serialized)
struct CutCompeteCaptureTests {
    nonisolated static let names = [
        "compete-loaded", "compete-loaded-bottom", "compete-invitations", "compete-empty", "compete-loading", "compete-error", "compete-ax", "compete-ax-mid", "compete-ax-bottom",
        "create-empty", "create-selected", "create-sending", "create-error", "create-rewards", "create-ax",
        "opponent-loaded", "opponent-loading", "opponent-empty", "opponent-error", "opponent-no-results",
        "battle-active", "battle-incoming", "battle-pending", "battle-won", "battle-lost", "battle-tied", "battle-expired", "battle-declined", "battle-cancelled", "battle-processing", "battle-leave-confirmation", "battle-ax",
        "challenge-joined", "challenge-not-joined", "challenge-completed", "challenge-leave-confirmation", "challenge-ax",
        "battles-active", "battles-pending", "battles-completed", "battles-empty", "battles-error",
        "challenges-active", "challenges-browse", "challenges-completed", "challenges-empty"
    ]
    nonisolated static var selectedNames: [String] {
        guard let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"] else { return names }
        precondition(names.contains(selected)); return [selected]
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_BATCH7"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-batch7")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let size: DynamicTypeSize = name.hasSuffix("-ax") || name.contains("-ax-") ? .accessibility5 : .large
        window.rootViewController = UIHostingController(rootView: makeScene(name, size: size).preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(name.hasPrefix("opponent-") ? 3 : 2))
        if name.hasSuffix("-mid") || name.hasSuffix("-bottom"), let scroll = verticalScroll(in: window) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: name.hasSuffix("-mid") ? bottom / 2 : bottom), animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }

    // MARK: - Scenes

    private func makeScene(_ name: String, size: DynamicTypeSize) -> AnyView {
        if name.hasPrefix("compete-") {
            return AnyView(CutCompeteCaptureTab { CutCompeteView(model: competeModel(name), processing: []) }.environment(\.dynamicTypeSize, size))
        }
        if name.hasPrefix("battles-") || name.hasPrefix("challenges-") {
            return AnyView(CutCompeteCapturePushed(title: name.hasPrefix("battles-") ? "Battles" : "Challenges") { pushed(name) }.environment(\.dynamicTypeSize, size))
        }
        let tab = CutCompeteView(model: competeModel("compete-loaded"))
        if name.hasPrefix("opponent-") {
            return AnyView(CutCompeteCaptureTab { tab }
                .sheet(isPresented: .constant(true)) {
                    create("create-selected")
                        .sheet(isPresented: .constant(true)) { opponent(name).environment(\.dynamicTypeSize, size) }
                })
        }
        return AnyView(CutCompeteCaptureTab { tab }
            .sheet(isPresented: .constant(true)) { sheet(name).environment(\.dynamicTypeSize, size) })
    }

    @ViewBuilder private func sheet(_ name: String) -> some View {
        if name.hasPrefix("create-") { create(name) }
        else if name.hasPrefix("battle-") { battle(name) }
        else { challenge(name) }
    }

    private func competeModel(_ name: String) -> CutCompeteModel {
        let empty = ["compete-empty", "compete-loading", "compete-error"].contains(name)
        let fixtures = CutCompeteFixtures.self
        var invite = fixtures.battle; invite.id = UUID(); invite.opponent = "Fixture Rival"; invite.status = .pending
        invite.isChallenger = false; invite.isOpponent = true; invite.type = .workoutCount; invite.ownScore = 0; invite.otherScore = 0
        let inviteRow = fixtures.battleRow(invite)
        let invitations = name == "compete-invitations" ? (0..<5).map { index -> CutCompeteItem in
            var f = invite; f.id = UUID(); f.opponent = ["Fixture Rival", "Fixture Partner", "Fixture Coach", "Fixture Friend", "Fixture Mate"][index]
            return fixtures.battleRow(f)
        } : [inviteRow]
        var trailing = fixtures.battle; trailing.id = UUID(); trailing.opponent = "Fixture Partner"; trailing.type = .workoutCount; trailing.ownScore = 3; trailing.otherScore = 5
        var finished = fixtures.battle; finished.id = UUID(); finished.opponent = "Fixture Coach"; finished.status = .completed
        var done = fixtures.challenge; done.id = UUID(); done.title = "Fixture Finished Challenge"; done.completed = true; done.current = 10; done.percentage = 100
        return CutCompeteLogic.model(pending: empty ? [] : invitations, battles: empty ? [] : [fixtures.row, fixtures.battleRow(trailing)],
            challenges: empty ? [] : [fixtures.challengeRow], available: empty ? [] : [fixtures.available],
            completedBattles: empty ? [] : [fixtures.battleRow(finished)], completedChallenges: empty ? [] : [fixtures.challengeRow(done)],
            loading: name == "compete-loading", error: name == "compete-error" ? "Fixture connection error. Pull to try again later." : nil)
    }

    private func create(_ name: String) -> some View {
        let fixtures = CutCompeteFixtures.self
        let selected = name == "create-empty" ? nil : fixtures.friends[0]
        let draft = CutCreateBattleDraft(opponentID: selected?.id)
        let view = CutCreateBattleView(model: CutCreateBattleLogic.model(draft, opponent: selected, friends: fixtures.friends, creating: name == "create-sending", unit: .kg),
                                       draft: .constant(draft), showingRewards: name == "create-rewards")
        return view.alert("Fixture error", isPresented: .constant(name == "create-error")) { Button("OK") {} } message: { Text("Fixture invitation could not be sent") }
    }

    private func opponent(_ name: String) -> some View {
        let query = name == "opponent-no-results" ? "absent" : ""
        let m = CutCreateBattleLogic.opponents(name == "opponent-empty" ? [] : CutCompeteFixtures.friends, query: query, selected: CutCompeteFixtures.friends[0].id,
            loading: name == "opponent-loading", error: name == "opponent-error" ? "Failed to load friends: Fixture error" : nil)
        return CutBattleOpponentView(model: m, query: .constant(query))
    }

    private func battle(_ name: String) -> some View {
        var f = CutCompeteFixtures.battle
        switch name {
        case "battle-incoming", "battle-processing": f.status = .pending; f.isChallenger = false; f.isOpponent = true; f.ownScore = 0; f.otherScore = 0
        case "battle-pending": f.status = .pending; f.ownScore = 0; f.otherScore = 0
        case "battle-won": f.status = .completed
        case "battle-lost": f.status = .completed; f.ownScore = 8100
        case "battle-tied": f.status = .completed; f.ownScore = f.otherScore
        case "battle-expired": f.start = CutCompeteFixtures.now.addingTimeInterval(-7 * 86400); f.end = CutCompeteFixtures.now
        case "battle-declined": f.status = .declined
        case "battle-cancelled": f.status = .cancelled
        default: break
        }
        if f.status == .completed { f.start = CutCompeteFixtures.now.addingTimeInterval(-7 * 86400); f.end = CutCompeteFixtures.now }
        return CutBattleDetailView(model: CutBattleDetailLogic.model(f, unit: .kg, locale: CutCompeteFixtures.locale, now: CutCompeteFixtures.now),
                                   operation: name == "battle-processing" ? .accept : nil, confirmingExit: name == "battle-leave-confirmation")
    }

    private func challenge(_ name: String) -> some View {
        var f = CutCompeteFixtures.challenge
        if name == "challenge-not-joined" { f.current = nil; f.percentage = 0; f.participants = f.participants.map { var p = $0; p.isViewer = false; return p } }
        if name == "challenge-completed" {
            f.completed = true; f.current = f.goal; f.percentage = 100; f.reward = .skin(id: 4, name: "VOLIA")
            f.participants = f.participants.map { var p = $0; if p.isViewer { p.progress = f.goal }; return p }.sorted { $0.progress > $1.progress }
        }
        return CutChallengeDetailView(model: CutChallengeDetailLogic.model(f, unit: .kg, locale: CutCompeteFixtures.locale, now: CutCompeteFixtures.now),
                                      confirmingLeave: name == "challenge-leave-confirmation")
    }

    @ViewBuilder private func pushed(_ name: String) -> some View {
        let fixtures = CutCompeteFixtures.self
        if name.hasPrefix("battles-") {
            let tab: CutBattlesListModel.Tab = name == "battles-pending" ? .pending : name == "battles-completed" ? .completed : .active
            let rows: [CutCompeteItem] = {
                switch tab {
                case .active:
                    var trailing = fixtures.battle; trailing.id = UUID(); trailing.opponent = "Fixture Partner"; trailing.ownScore = 7200
                    return [fixtures.row, fixtures.battleRow(trailing)]
                case .pending:
                    var incoming = fixtures.battle; incoming.status = .pending; incoming.isOpponent = true; incoming.isChallenger = false; incoming.opponent = "Fixture Rival"
                    var sent = fixtures.battle; sent.id = UUID(); sent.status = .pending; sent.opponent = "Fixture Coach"; sent.type = .runningDistance
                    return [fixtures.battleRow(incoming), fixtures.battleRow(sent)]
                case .completed:
                    var won = fixtures.battle; won.status = .completed
                    var lost = fixtures.battle; lost.id = UUID(); lost.status = .completed; lost.opponent = "Fixture Partner"; lost.ownScore = 100
                    return [fixtures.battleRow(won), fixtures.battleRow(lost)]
                }
            }()
            let shown = ["battles-empty", "battles-error"].contains(name) ? [] : rows
            CutBattlesListView(model: CutBattlesListLogic.model(tab: tab, active: shown, pending: shown, completed: shown, loading: false,
                                                                error: name == "battles-error" ? "Fixture connection error" : nil))
        } else {
            browse(name)
        }
    }

    private func browse(_ name: String) -> some View {
        let fixtures = CutCompeteFixtures.self
        let tab: CutChallengesBrowseModel.Tab = name == "challenges-browse" ? .browse : name == "challenges-completed" ? .completed : .active
        let empty = name == "challenges-empty"
        var done = fixtures.challenge; done.completed = true; done.current = done.goal; done.percentage = 100
        var second = fixtures.challenge; second.id = UUID(); second.title = "Fixture Streak"; second.type = .streak; second.current = 3; second.percentage = 43; second.goal = 7
        return CutChallengesBrowseView(model: CutChallengesBrowseLogic.model(tab: tab, active: empty ? [] : [fixtures.challengeRow, fixtures.challengeRow(second)],
                available: [fixtures.available], completed: [fixtures.challengeRow(done)],
                presets: tab == .browse || empty ? [fixtures.preset] : [], loading: false, error: nil))
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ v: UIView) { if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height { candidates.append(s) }; v.subviews.forEach(visit) }
        visit(view); return candidates.max { $0.bounds.height < $1.bounds.height }
    }
}

/// The Compete tab inside the Social shell, as the app shows it.
@MainActor
private struct CutCompeteCaptureTab<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationStack {
            CutSocialShell(header: .init(avatarURL: nil, initials: "FX"), section: .compete) { content() }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// A screen pushed from Compete with the system back button.
@MainActor
private struct CutCompeteCapturePushed<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var path: [String] = []
    var body: some View {
        NavigationStack(path: $path) {
            Color.black.navigationTitle("Social")
                .onAppear { DispatchQueue.main.async { if path.isEmpty { path.append("fixture") } } }
                .navigationDestination(for: String.self) { _ in
                    content().navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
                }
        }
    }
}

@MainActor
enum CutCompeteFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let locale = Locale(identifier: "en_US")
    static var battle: CutBattleFacts { .init(id: UUID(), type: .volume, status: .active, opponent: "Fixture Opponent", ownScore: 12400, otherScore: 9800, isChallenger: true, isOpponent: false, start: now.addingTimeInterval(-2 * 86400), end: now.addingTimeInterval(5 * 86400), ownName: "Fixture Viewer") }
    static func battleRow(_ facts: CutBattleFacts) -> CutCompeteItem { CutCompeteLogic.battle(facts, unit: .kg, locale: locale, now: now) }
    static var row: CutCompeteItem { battleRow(battle) }
    static let friends: [CutBattleOpponent] = ["Fixture Opponent", "Fixture Rival", "fixture_partner", "Fixture Coach", "Fixture Friend", "Fixture Mate"].map {
        CutBattleOpponent(id: UUID(), name: $0, username: $0.lowercased().replacingOccurrences(of: " ", with: "_"), avatarURL: nil)
    }
    static let opponent = friends[0]
    static var challenge: CutChallengeFacts { .init(id: UUID(), title: "Fixture Challenge", description: "Complete ten workouts in this fixture challenge.", type: .workoutCount, metric: "workouts", goal: 10, start: now, end: now.addingTimeInterval(14 * 86400), evergreen: false, difficulty: "Beginner", participantCount: 12, current: 6, percentage: 60, completed: false,
        participants: [.init(id: UUID(), name: "fixture_leader", progress: 8, isViewer: false), .init(id: UUID(), name: "fixture_viewer", progress: 6, isViewer: true)], reward: nil) }
    static func challengeRow(_ facts: CutChallengeFacts) -> CutCompeteItem { CutCompeteLogic.challenge(facts, unit: .kg, locale: locale, now: now) }
    static var challengeRow: CutCompeteItem { challengeRow(challenge) }
    static var available: CutCompeteItem {
        var facts = challenge; facts.id = UUID(); facts.title = "Fixture Community Challenge"; facts.current = nil; facts.participantCount = 8; facts.goal = 6
        return challengeRow(facts)
    }
    static var preset: CutChallengesBrowseModel.Preset { .init(title: "Fixture Featured Challenge", description: "Complete ten workouts in fourteen days.", duration: "14 days", difficulty: "Beginner") }
}
