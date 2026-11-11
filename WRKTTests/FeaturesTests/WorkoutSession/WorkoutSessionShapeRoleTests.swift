import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct WorkoutSessionShapeRoleTests {
    #if DEBUG
    private func source(_ path: String, from start: String, until end: String? = nil) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("CLAUDE.md").path) {
            directory.deleteLastPathComponent()
        }
        let text = try String(contentsOf: directory.appendingPathComponent("Features/WorkoutSession/Views/" + path), encoding: .utf8)
        let range = try #require(text.range(of: start))
        let tail = text[range.lowerBound...]
        if let end, let ending = tail.range(of: end) { return String(tail[..<ending.lowerBound]) }
        return String(tail)
    }

    private func check<S: SwiftUI.Shape>(_ shape: DS.RoleShape<S>, rect: CGRect,
                                         radius: CGFloat, legacy: Path) {
        #expect(shape.path(in: rect, rounded: false).cgPath == legacy.cgPath)
        let clamped = min(radius, rect.width / 2, rect.height / 2)
        #expect(shape.path(in: rect, rounded: true).cgPath == RoundedRectangle(cornerRadius: clamped, style: .continuous).path(in: rect).cgPath)
    }
    @Test func liveOverlayRolesKeepLegacyPaths() throws {
        let hero = try source("LiveWorkout/LiveWorkoutOverlayCard.swift", from: "private struct CurrentExerciseHeroCard", until: "private struct SupersetGroupSection")
        #expect(hero.contains("DS.RoleShape(.nested, legacy: ChamferedRectangle(.large))"))
        let dialog = try source("LiveWorkout/LiveWorkoutOverlayCard.swift", from: "private struct DiscardConfirmationDialog", until: "private struct LiveWorkoutRow")
        #expect(dialog.contains("DS.RoleShape(.alert, legacy: ChamferedRectangle(.xl))"))
        #expect(dialog.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        for rect in [CGRect(x: 3, y: 7, width: 340, height: 180), CGRect(x: 3, y: 7, width: 40, height: 30)] {
            check(DS.RoleShape(.card, legacy: ChamferedRectangle(.hero)), rect: rect, radius: 26,
                  legacy: MainChamferedRectangle(.hero).path(in: rect))
            check(DS.RoleShape(.nested, legacy: ChamferedRectangle(.large)), rect: rect, radius: 10,
                  legacy: MainChamferedRectangle(.large).path(in: rect))
            check(DS.RoleShape(.alert, legacy: ChamferedRectangle(.xl)), rect: rect, radius: 36,
                  legacy: MainChamferedRectangle(.xl).path(in: rect))
            check(DS.RoleShape(.control, legacy: ChamferedRectangle(.large)), rect: rect,
                  radius: min(rect.width, rect.height) / 2, legacy: MainChamferedRectangle(.large).path(in: rect))
        }
    }
    @Test func exerciseSessionControlsAndCardsKeepLegacyPaths() throws {
        let quickTime = try source("ExerciseSession/TimedSetRow.swift", from: "private struct QuickTimeButton")
        #expect(quickTime.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 8, style: .continuous))"))
        let swipe = try source("ExerciseSession/ExcerciseSessionView.swift", from: "private struct CustomLeadingSwipeAction", until: "private func")
        #expect(swipe.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        let tips = try source("ExerciseSession/OverviewComponents.swift", from: "struct OverviewCard", until: "struct ChipItem")
        #expect(tips.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12))"))
        let button = CGRect(x: 3, y: 7, width: 90, height: 36)
        check(DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 8, style: .continuous)),
              rect: button, radius: 18, legacy: RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: button))
        let card = CGRect(x: 3, y: 7, width: 320, height: 160)
        check(DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12)),
              rect: card, radius: 26, legacy: RoundedRectangle(cornerRadius: 12).path(in: card))
        let toggle = CGRect(x: 3, y: 7, width: 90, height: 60)
        check(DS.RoleShape(.control, legacy: ChamferedRectangle(.medium)), rect: toggle, radius: 30,
              legacy: MainChamferedRectangle(.medium).path(in: toggle))
    }
    @Test func restTimerSettingsAndResetKeepLegacyPaths() throws {
        let settings = try source("RestTimer/RestTimerComponents.swift", from: "struct RestTimerSettingsCard", until: "struct CustomTimerEditorView")
        #expect(settings.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.medium))"))
        let editor = try source("RestTimer/RestTimerComponents.swift", from: "struct CustomTimerEditorView")
        #expect(editor.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))"))
        let rect = CGRect(x: 3, y: 7, width: 320, height: 70)
        check(DS.RoleShape(.card, legacy: ChamferedRectangle(.medium)), rect: rect, radius: 26,
              legacy: MainChamferedRectangle(.medium).path(in: rect))
        let button = CGRect(x: 3, y: 7, width: 300, height: 44)
        check(DS.RoleShape(.control, legacy: ChamferedRectangle(.medium)), rect: button, radius: 22,
              legacy: MainChamferedRectangle(.medium).path(in: button))
    }
    #endif
}
