import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering: no hosts, accounts, repositories or server operations.
/// Opt in with TEST_RUNNER_VOLIA_CAPTURE_BATCH7=1 and TEST_RUNNER_VOLIA_CAPTURE_STATE.
@MainActor
@Suite(.serialized)
struct CutCompeteCaptureTests {
    nonisolated static let names = [
        "compete-shell", "compete-shell-ax", "compete-loaded", "compete-loaded-mid", "compete-loaded-bottom", "compete-many-invites", "compete-many-invites-mid", "compete-many-invites-bottom", "compete-empty", "compete-loading", "compete-error", "compete-ax", "compete-ax-mid", "compete-ax-bottom",
        "battle-sheet", "battle-active", "battle-incoming", "battle-pending", "battle-won", "battle-lost", "battle-tied", "battle-expired", "battle-declined", "battle-cancelled", "battle-processing", "battle-exiting", "battle-leave-confirmation", "battle-expanded", "battle-expanded-bottom", "battle-ax", "battle-ax-bottom",
        "battles-active", "battles-pending", "battles-completed", "battles-empty", "battles-loading", "battles-error",
        "create-empty", "create-selected", "create-sending", "create-error",
        "opponent-loaded", "opponent-loading", "opponent-empty", "opponent-error", "opponent-no-results",
        "challenge-sheet", "challenge-not-joined", "challenge-joining", "challenge-joined", "challenge-leaving", "challenge-completed", "challenge-ended", "challenge-leave-confirmation", "challenge-expanded", "challenge-expanded-bottom",
        "challenges-active", "challenges-recommended", "challenges-browse", "challenges-browse-empty", "challenges-completed", "challenges-empty", "challenges-loading", "challenges-error"
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
        let accessibility = name.contains("-ax")
        let content = fixture(name).environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
        window.rootViewController = UIHostingController(rootView: CutCompeteCaptureNavigation(title: title(name), asSheet: name.hasPrefix("opponent-") || name.hasPrefix("create-") || name.hasSuffix("-sheet"), doneSheet: name.hasSuffix("-sheet"), asRootPane: name.hasPrefix("compete-shell")) { content }.preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(2))
        if name.hasSuffix("-mid") || name.hasSuffix("-bottom"), let scroll = verticalScroll(in: window) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: name.hasSuffix("-mid") ? bottom / 2 : bottom), animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
        if let signalPath = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SIGNALS"] {
            // Hold the fixture while simctl records the composited native navigation bar.
            // drawHierarchy can omit glass-backed buttons even when the UI is correct.
            let signals = URL(fileURLWithPath: signalPath)
            try FileManager.default.createDirectory(at: signals, withIntermediateDirectories: true)
            let ready = signals.appendingPathComponent(name + ".ready")
            let acknowledgement = signals.appendingPathComponent(name + ".ack")
            try Data().write(to: ready)
            let deadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: acknowledgement.path), Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(FileManager.default.fileExists(atPath: acknowledgement.path), "Simulator capture acknowledgement timed out")
        }
    }
    private func title(_ name: String) -> String {
        if name.hasPrefix("battle-") { return "Fixture Opponent" }
        if name.hasPrefix("battles-") { return "Battles" }
        if name.hasPrefix("create-") { return "Create Battle" }
        if name.hasPrefix("opponent-") { return "Choose Opponent" }
        if name.hasPrefix("challenge-") { return "Fixture Challenge" }
        if name.hasPrefix("challenges-") { return "Challenges" }
        return "Compete"
    }
    private func fixture(_ name: String) -> AnyView {
        if name.hasPrefix("compete-") {
            let empty = name == "compete-empty" || name == "compete-loading" || name == "compete-error"
            let row = CutCompeteFixtures.row
            var invite = row; invite.id = .battle(UUID()); invite.incoming = true; invite.value = "Invitation"; invite.fraction = nil; invite.trailing = "7 days"
            let invitations = name.hasPrefix("compete-many-invites") ? (0..<5).map { _ in var value = invite; value.id = .battle(UUID()); return value } : [invite]
            var completedBattle = row; completedBattle.id = .battle(UUID()); completedBattle.title = "Fixture Finished Opponent"; completedBattle.trailing = "You won"; completedBattle.fraction = nil
            var completedChallenge = CutCompeteFixtures.challengeRow; completedChallenge.id = .challenge(UUID()); completedChallenge.title = "Fixture Finished Challenge"; completedChallenge.value = "10 / 10 workouts"; completedChallenge.trailing = "Completed · 12 competing"; completedChallenge.fraction = 1
            let m = CutCompeteLogic.model(pending: empty ? [] : invitations, battles: empty ? [] : [row], challenges: empty ? [] : [CutCompeteFixtures.challengeRow],
                available: empty ? [] : [CutCompeteFixtures.available], completedBattles: empty ? [] : [completedBattle], completedChallenges: empty ? [] : [completedChallenge], loading: name == "compete-loading", error: name == "compete-error" ? "Fixture connection error" : nil)
            if name.hasPrefix("compete-shell") {
                return AnyView(CutSocialShell(header: .init(avatarURL: nil, initials: "FX"), section: .compete) { CutCompeteView(model: m) })
            }
            return AnyView(CutCompeteView(model: m))
        }
        if name.hasPrefix("battle-") {
            var f = CutCompeteFixtures.battle
            switch name {
            case "battle-incoming", "battle-processing": f.status = .pending; f.isChallenger = false; f.isOpponent = true; f.ownScore = 0; f.otherScore = 0
            case "battle-pending": f.status = .pending; f.ownScore = 0; f.otherScore = 0
            case "battle-won": f.status = .completed
            case "battle-lost": f.status = .completed; f.ownScore = 500
            case "battle-tied": f.status = .completed; f.ownScore = f.otherScore
            case "battle-expired": f.start = CutCompeteFixtures.now.addingTimeInterval(-7 * 86400); f.end = CutCompeteFixtures.now
            case "battle-declined": f.status = .declined
            case "battle-cancelled": f.status = .cancelled
            default: break
            }
            if f.status == .completed { f.start = CutCompeteFixtures.now.addingTimeInterval(-7 * 86400); f.end = CutCompeteFixtures.now }
            return AnyView(CutBattleDetailView(model: CutBattleDetailLogic.model(f, unit: .kg, locale: CutCompeteFixtures.locale, now: CutCompeteFixtures.now), operation: name == "battle-processing" ? .accept : name == "battle-exiting" ? .exit : nil, expanded: name.hasPrefix("battle-expanded"), confirmingExit: name == "battle-leave-confirmation"))
        }
        if name.hasPrefix("battles-") {
            let tab: CutBattlesListModel.Tab = name == "battles-pending" ? .pending : name == "battles-completed" ? .completed : .active
            var facts = CutCompeteFixtures.battle
            if tab == .pending { facts.status = .pending; facts.isOpponent = true; facts.isChallenger = false; facts.ownScore = 0; facts.otherScore = 0 }
            if tab == .completed { facts.status = .completed }
            let row = CutCompeteLogic.battle(facts, unit: .kg, locale: CutCompeteFixtures.locale, now: CutCompeteFixtures.now)
            let rows = ["battles-empty", "battles-loading", "battles-error"].contains(name) ? [] : [row]
            let m = CutBattlesListLogic.model(tab: tab, active: rows, pending: rows, completed: rows, loading: name == "battles-loading", error: name == "battles-error" ? "Fixture connection error" : nil)
            return AnyView(CutBattlesListView(model: m))
        }
        if name.hasPrefix("create-") {
            let draft = CutCreateBattleDraft(opponentID: name == "create-empty" ? nil : CutCompeteFixtures.opponent.id)
            let view = CutCreateBattleView(model: CutCreateBattleLogic.model(draft, opponent: name == "create-empty" ? nil : CutCompeteFixtures.opponent, creating: name == "create-sending", unit: .kg), draft: .constant(draft))
            return AnyView(view.alert("Fixture error", isPresented: .constant(name == "create-error")) { Button("OK") {} } message: { Text("Fixture invitation could not be sent") })
        }
        if name.hasPrefix("opponent-") {
            let query = name == "opponent-no-results" ? "absent" : ""
            let m = CutCreateBattleLogic.opponents(name == "opponent-empty" ? [] : [CutCompeteFixtures.opponent], query: query, selected: CutCompeteFixtures.opponent.id, loading: name == "opponent-loading", error: name == "opponent-error" ? "Failed to load friends: Fixture error" : nil)
            return AnyView(CutBattleOpponentView(model: m, query: .constant(query)))
        }
        if name.hasPrefix("challenge-") {
            var f = CutCompeteFixtures.challenge
            if name == "challenge-not-joined" || name == "challenge-joining" { f.current = nil; f.percentage = 0; f.participants = f.participants.map { var p = $0; p.isViewer = false; return p } }
            if name == "challenge-completed" {
                f.completed = true; f.current = f.goal; f.percentage = 100
                f.participants = f.participants.map { var p = $0; if p.isViewer { p.progress = f.goal }; return p }.sorted { $0.progress > $1.progress }
            }
            if name == "challenge-ended" { f.start = CutCompeteFixtures.now.addingTimeInterval(-15 * 86400); f.end = CutCompeteFixtures.now.addingTimeInterval(-86400) }
            if name.hasPrefix("challenge-expanded") {
                f.goal = 1; f.current = 0; f.percentage = 0; f.reward = .skin(id: 4, name: "VOLIA")
                f.description = "Complete one workout in this fixture challenge."
                f.participants = f.participants.map { var p = $0; p.progress = p.isViewer ? 0 : 1; return p }
            }
            return AnyView(CutChallengeDetailView(model: CutChallengeDetailLogic.model(f, unit: .kg, locale: CutCompeteFixtures.locale, now: CutCompeteFixtures.now), processing: name == "challenge-joining" || name == "challenge-leaving", expanded: name.hasPrefix("challenge-expanded"), confirmingLeave: name == "challenge-leave-confirmation"))
        }
        let tab: CutChallengesBrowseModel.Tab = name.hasPrefix("challenges-browse") ? .browse : name == "challenges-completed" ? .completed : .active
        let empty = ["challenges-empty", "challenges-browse-empty", "challenges-recommended", "challenges-loading", "challenges-error"].contains(name)
        var completed = CutCompeteFixtures.challenge
        completed.completed = true; completed.current = completed.goal; completed.percentage = 100
        let completedRow = CutCompeteLogic.challenge(completed, unit: .kg, locale: CutCompeteFixtures.locale, now: CutCompeteFixtures.now)
        let m = CutChallengesBrowseLogic.model(tab: tab, active: empty ? [] : [CutCompeteFixtures.challengeRow], available: empty ? [] : [CutCompeteFixtures.available], completed: empty ? [] : [completedRow],
            presets: (tab == .browse && name != "challenges-browse-empty") || name == "challenges-recommended" ? [CutCompeteFixtures.preset] : [], loading: name == "challenges-loading", error: name == "challenges-error" ? "Fixture connection error" : nil)
        return AnyView(CutChallengesBrowseView(model: m))
    }
    private func verticalScroll(in view: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ v: UIView) { if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height { candidates.append(s) }; v.subviews.forEach(visit) }
        visit(view); return candidates.max { $0.bounds.height < $1.bounds.height }
    }
}
@MainActor
private struct CutCompeteCaptureNavigation<Content: View>: View {
    let title: String
    var asSheet = false
    var doneSheet = false
    var asRootPane = false
    @ViewBuilder var content: () -> Content
    @State private var path: [String] = []
    var body: some View {
        if asRootPane {
            NavigationStack { content().toolbar(.hidden, for: .navigationBar) }
        } else if asSheet {
            Color.black.sheet(isPresented: .constant(true)) {
                NavigationStack {
                    content().navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
                        .toolbar {
                            if doneSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") {}.tint(DS.Cut.Colors.lime) } }
                            else { ToolbarItem(placement: .cancellationAction) { Button("Cancel") {}.tint(DS.Cut.Colors.lime) } }
                        }
                }
            }
        } else {
            NavigationStack(path: $path) {
                Color.black.navigationTitle("Social")
                    .onAppear {
                        // Push after the root mounts so UIKit installs the real back item.
                        DispatchQueue.main.async { if path.isEmpty { path.append("fixture") } }
                    }
                    .navigationDestination(for: String.self) { _ in content().navigationTitle(title).navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(false).toolbar(.visible, for: .navigationBar)
                        .toolbar {
                            if title == "Battles" {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Create battle", systemImage: "plus") {}.tint(DS.Cut.Colors.lime)
                                }
                            }
                        }
                    }
            }
        }
    }
}
@MainActor
enum CutCompeteFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let locale = Locale(identifier: "en_US")
    static var battle: CutBattleFacts { .init(id: UUID(), type: .volume, status: .active, opponent: "Fixture Opponent", ownScore: 12400, otherScore: 9800, isChallenger: true, isOpponent: false, start: now, end: now.addingTimeInterval(7 * 86400)) }
    static var row: CutCompeteItem { CutCompeteLogic.battle(battle, unit: .kg, locale: locale, now: now) }
    static let opponent = CutBattleOpponent(id: UUID(), name: "Fixture Opponent", username: "fixture_opponent", avatarURL: nil)
    static var challenge: CutChallengeFacts { .init(id: UUID(), title: "Fixture Challenge", description: "Complete ten workouts in this fixture challenge.", type: .workoutCount, metric: "workouts", goal: 10, start: now, end: now.addingTimeInterval(14 * 86400), evergreen: false, difficulty: "Beginner", participantCount: 12, current: 6, percentage: 60, completed: false,
        participants: [.init(id: UUID(), name: "fixture_leader", progress: 8, isViewer: false), .init(id: UUID(), name: "fixture_viewer", progress: 6, isViewer: true)], reward: nil) }
    static var challengeRow: CutCompeteItem { CutCompeteLogic.challenge(challenge, unit: .kg, locale: locale, now: now) }
    static var available: CutCompeteItem {
        var facts = challenge; facts.title = "Fixture Community Challenge"; facts.current = nil; facts.participantCount = 8
        return CutCompeteLogic.challenge(facts, unit: .kg, locale: locale, now: now, showsDescription: true)
    }
    static var preset: CutChallengesBrowseModel.Preset { .init(title: "Fixture Featured Challenge", description: "Complete ten workouts in fourteen days.", duration: "14 days", difficulty: "Beginner") }
}
