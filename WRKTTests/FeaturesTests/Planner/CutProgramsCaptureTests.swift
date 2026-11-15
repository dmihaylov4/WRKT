import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering of the Cut Programs screens: no hosts, accounts, repositories or server work.
/// Opt in with TEST_RUNNER_VOLIA_CAPTURE_PROGRAMS=1 (and TEST_RUNNER_VOLIA_CAPTURE_STATE for one state).
@MainActor
@Suite(.serialized)
struct CutProgramsCaptureTests {
    nonisolated static let names = [
        "programs-loaded", "programs-no-active", "programs-empty", "programs-ax", "programs-ax-bottom", "programs-clear",
        "share-none", "share-two", "share-sending", "share-error", "share-all", "sent-invites",
        "preview-loaded", "preview-saved", "preview-unavailable", "preview-ax", "preview-ax-bottom", "preview-day", "preview-exercise-edit",
        "setup-split", "setup-days", "setup-days-warning", "setup-days-ax", "setup-customize", "setup-exercise-edit",
        "setup-review-create", "setup-review-replace", "setup-review-edit", "setup-review-ax", "setup-start-date",
        "custom-split", "custom-name", "custom-exercises", "custom-days", "custom-review"
    ]
    nonisolated static var selectedNames: [String] {
        guard let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"] else { return names }
        precondition(names.contains(selected)); return [selected]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PROGRAMS"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-programs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let size: DynamicTypeSize = name.contains("-ax") ? .accessibility5 : .large
        window.rootViewController = UIHostingController(rootView: makeScene(name).environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(name == "share-all" || name == "preview-exercise-edit" ? 3 : 2))
        if name.hasSuffix("-bottom"), let scroll = verticalScroll(in: window) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }

    // MARK: Scenes

    private func makeScene(_ name: String) -> AnyView {
        switch name {
        case "programs-loaded", "programs-ax", "programs-ax-bottom": return AnyView(pushed { programs(.full) })
        case "programs-no-active": return AnyView(pushed { programs(.noActive) })
        case "programs-empty": return AnyView(pushed { programs(.empty) })
        case "programs-clear": return AnyView(pushed { CutProgramsView(model: programsModel(.full), confirmingClear: .constant(true)) })
        case "share-all":
            return AnyView(pushed { programs(.full) }.sheet(isPresented: .constant(true)) {
                share(selected: 2).sheet(isPresented: .constant(true)) {
                    CutProgramFriendsView(model: CutProgramShareLogic.friends(F.friends, query: "", selected: Array(F.friends.prefix(2)), loading: false, error: nil),
                                          query: .constant(""))
                }
            })
        case _ where name.hasPrefix("share-"):
            return AnyView(pushed { programs(.full) }.sheet(isPresented: .constant(true)) {
                switch name {
                case "share-none": share(selected: 0)
                case "share-two": share(selected: 2)
                case "share-sending": share(selected: 2, sending: true)
                default: share(selected: 2, error: "Fixture network error. Try again.")
                }
            })
        case "sent-invites":
            return AnyView(pushed { programs(.full) }.sheet(isPresented: .constant(true)) {
                CutSentInvitesView(model: CutSentInvitesLogic.model(programName: "Full Body", invites: [
                    .init(id: UUID(), status: .pending, displayName: "Fixture Friend", username: "fixture_friend", avatarURL: nil),
                    .init(id: UUID(), status: .accepted, displayName: "Fixture Coach", username: "fixture_coach", avatarURL: nil),
                    .init(id: UUID(), status: .declined, displayName: nil, username: "fixture_mate", avatarURL: nil)
                ], loading: false))
            })
        case "preview-loaded", "preview-ax", "preview-ax-bottom": return AnyView(pushed { CutProgramPreviewView(model: previewModel(.pending)) })
        case "preview-saved": return AnyView(pushed { CutProgramPreviewView(model: previewModel(.pending, imported: true)) })
        case "preview-unavailable": return AnyView(pushed { CutProgramPreviewView(model: previewModel(.declined)) })
        case "preview-day", "preview-exercise-edit":
            let day = CutProgramPreviewLogic.daySheet(title: "Day 1, Push", exercises: F.push.map { (id: UUID(), name: $0, sets: 3, reps: 8, weight: 60) }, unit: .kg)
            return AnyView(pushed { CutProgramPreviewView(model: previewModel(.pending)) }.sheet(isPresented: .constant(true)) {
                CutProgramDaySheetView(model: day).sheet(isPresented: .constant(name == "preview-exercise-edit")) {
                    CutExerciseEditView(model: CutExerciseEditLogic.model(name: "Bench Press", sets: 3, reps: 8, weight: 60, context: .invite, unitLabel: "kg", weightStep: 2.5),
                                        level: .stacked, save: { _, _, _ in }, close: {})
                }
            })
        case "setup-exercise-edit":
            return AnyView(setup(.customize("full-body-a"), config: predefined()).sheet(isPresented: .constant(true)) {
                CutExerciseEditView(model: CutExerciseEditLogic.model(name: "Back Squat", sets: 3, reps: 5, weight: 100, context: .setup, unitLabel: "kg", weightStep: 2.5),
                                    save: { _, _, _ in }, close: {})
            })
        case "setup-start-date":
            return AnyView(setup(.review, config: predefined()).sheet(isPresented: .constant(true)) {
                CutPlanStartDateView(date: .constant(F.monday))
            })
        default:
            return AnyView(setupScene(name))
        }
    }

    private enum Library { case full, noActive, empty }

    private func programsModel(_ library: Library) -> CutProgramsModel {
        let active = CutProgramFacts(id: UUID(), name: "Full Body", isActive: true, days: [6, nil, 6, nil, 6, nil, nil], creatorName: nil, hasBeenShared: true)
        let upper = CutProgramFacts(id: UUID(), name: "Upper/Lower", isActive: false, days: [5, 6, nil, 5, 6, nil, nil], creatorName: nil, hasBeenShared: false)
        let strength = CutProgramFacts(id: UUID(), name: "Fixture Strength Base", isActive: false, days: [4, nil, 4, nil, 4, nil, nil], creatorName: "Fixture Coach", hasBeenShared: true)
        let invite = CutProgramInviteFacts(id: UUID(), programName: "Push/Pull/Legs", senderDisplayName: "Fixture Friend", senderUsername: "fixture_friend")
        switch library {
        case .full: return CutProgramsLogic.model(library: [active, upper, strength], invites: [invite])
        case .noActive: return CutProgramsLogic.model(library: [upper, strength], invites: [invite])
        case .empty: return CutProgramsLogic.model(library: [], invites: [])
        }
    }

    private func programs(_ library: Library) -> some View { CutProgramsView(model: programsModel(library)) }

    private func share(selected: Int, sending: Bool = false, error: String? = nil) -> some View {
        CutProgramShareView(model: CutProgramShareLogic.model(programName: "Full Body", friends: F.friends, selected: Array(F.friends.prefix(selected)),
                                                              loading: false, loadError: nil, sending: sending, sendError: error),
                            note: .constant(selected > 0 ? "Try this for the next 8 weeks" : ""))
    }

    private func previewModel(_ status: ProgramInviteStatus, imported: Bool = false) -> CutProgramPreviewModel {
        let pending = status == .pending
        return CutProgramPreviewLogic.model(.init(
            loaded: true, inviteStatus: status, hasProgram: pending, programName: "Push/Pull/Legs", note: "Try this for the next 8 weeks.",
            senderDisplayName: "Fixture Friend", senderUsername: "fixture_friend", senderAvatarURL: nil,
            blocks: pending ? [
                .init(id: UUID(), name: "Push", isRest: false, exerciseNames: F.push),
                .init(id: UUID(), name: "Pull", isRest: false, exerciseNames: ["Deadlift", "Pull-Up", "Barbell Row", "Biceps Curl"]),
                .init(id: UUID(), name: "Legs", isRest: false, exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Calf Raise"]),
                .init(id: UUID(), name: "Rest", isRest: true, exerciseNames: [])
            ] : nil,
            imported: imported, acting: false, availability: pending ? nil : "This invite was declined.", error: nil))
    }

    // MARK: Setup

    private func predefined(_ template: SplitTemplate = SplitTemplates.fullBody, weekdays: Set<Int> = [0, 2, 4], weeks: Int = 8) -> PlanConfig {
        let config = PlanConfig()
        config.selectedTemplate = template
        config.startDate = F.monday
        config.programWeeks = weeks
        var draft = CutPlanSetupDraft()
        CutPlanSetupLogic.setWeekdays(weekdays, config: config, draft: &draft, calendar: .current)
        CutPlanSetupLogic.prepareForReview(config)
        return config
    }

    private func custom(withDays: Bool) -> PlanConfig {
        let config = PlanConfig()
        CutPlanSetupLogic.chooseBuildOwn(config)
        config.startDate = F.monday
        config.customSplitName = "Fixture Split"
        CutPlanSetupLogic.setPartCount(3, config: config)
        CutPlanSetupLogic.quickFill(config)
        let list = { (names: [String]) in names.map { ExerciseTemplate(exerciseID: $0, exerciseName: $0, sets: 3, reps: 10) } }
        config.partExercises = ["Push": list(F.push), "Pull": list(["Deadlift", "Pull-Up", "Barbell Row"]), "Legs": list(["Back Squat"])]
        if withDays {
            config.partExercises["Legs"] = list(["Back Squat", "Leg Press", "Calf Raise"])
            config.programWeeks = 12
            var draft = CutPlanSetupDraft()
            CutPlanSetupLogic.setWeekdays([0, 1, 3, 4], config: config, draft: &draft, calendar: .current)
        }
        return config
    }

    private func setupScene(_ name: String) -> some View {
        switch name {
        case "setup-split":
            let config = PlanConfig(); CutPlanSetupLogic.choose(SplitTemplates.fullBody, config: config)
            return setup(.split, config: config)
        case "setup-days", "setup-days-ax": return setup(.days, config: predefined(), touched: true)
        case "setup-days-warning": return setup(.days, config: predefined(SplitTemplates.ppl, weekdays: [0, 1, 2, 3]), touched: true)
        case "setup-customize": return setup(.customize("full-body-a"), config: predefined())
        case "setup-review-create": return setup(.review, config: predefined())
        case "setup-review-replace", "setup-review-ax": return setup(.review, config: predefined(), replaces: true)
        case "setup-review-edit": return setup(.review, config: predefined(SplitTemplates.upperLower, weekdays: [0, 1, 3, 4], weeks: 12), purpose: .edit, replaces: true)
        case "custom-split":
            let config = PlanConfig(); CutPlanSetupLogic.chooseBuildOwn(config)
            return setup(.split, config: config)
        case "custom-name": return setup(.customName, config: custom(withDays: false))
        case "custom-exercises": return setup(.customExercises, config: custom(withDays: false))
        case "custom-days": return setup(.days, config: custom(withDays: true), touched: true)
        default: return setup(.review, config: custom(withDays: true))
        }
    }

    private func setup(_ screen: CutPlanSetupScreen, config: PlanConfig, touched: Bool = false, purpose: CutPlanSetupPurpose = .create, replaces: Bool = false) -> AnyView {
        var draft = CutPlanSetupDraft()
        if touched {
            draft.weekdays = CutPlanSetupLogic.weekdays(config, draft: .init(), calendar: .current)
            draft.baseStart = config.startDate
        }
        let saved = SplitTemplate(id: "fixture-mine", name: "Fixture Split", shortName: "FIX", description: "", days: SplitTemplates.ppl.days,
                                  recommendedFrequency: 3, difficulty: .intermediate, focus: "", icon: "", isCustom: true)
        let content: CutPlanSetupContent
        switch screen {
        case .split: content = .split(CutPlanSetupLogic.splitModel(config, saved: [saved]))
        case .customName: content = .customName(CutPlanSetupLogic.customNameModel(config))
        case .customExercises: content = .customExercises(CutPlanSetupLogic.customExercisesModel(config))
        case .days: content = .days(CutPlanSetupLogic.daysModel(config, draft: draft, calendar: .current))
        case .customize(let id): content = .customize(CutPlanSetupLogic.customizeModel(dayID: id, config: config, unit: .kg))
        case .review: content = .review(CutPlanSetupLogic.reviewModel(config, purpose: purpose, replacesPlan: replaces, calendar: .current, locale: Locale(identifier: "en_GB")))
        }
        let step = CutPlanSetupLogic.step(screen, isCustom: config.isCreatingCustom)
        return AnyView(NavigationStack {
            CutPlanSetupView(content: content, step: step.number, total: step.total, isFirst: screen == .split)
                .toolbar(.hidden, for: .navigationBar)
        })
    }

    /// A pushed screen with the navigation bar hidden, as the hosts show it.
    private func pushed<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack { content().toolbar(.hidden, for: .navigationBar) }
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ v: UIView) { if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height { candidates.append(s) }; v.subviews.forEach(visit) }
        visit(view); return candidates.max { $0.bounds.height < $1.bounds.height }
    }

    private enum F {
        static var monday: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16))! }
        static let push = ["Bench Press", "Overhead Press", "Incline Press", "Triceps Pushdown"]
        static let friends: [CutBattleOpponent] = ["Ana Fixture", "Bo Fixture", "Cleo Fixture", "Dan Fixture", "Eli Fixture", "Fay Fixture"].map {
            CutBattleOpponent(id: UUID(), name: $0, username: $0.lowercased().replacingOccurrences(of: " ", with: "_"), avatarURL: nil)
        }
    }
}
