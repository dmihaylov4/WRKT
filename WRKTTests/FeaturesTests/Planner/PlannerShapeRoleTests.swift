import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct PlannerShapeRoleTests {
    #if DEBUG
    @Test func calendarSurfacesKeepLegacyPathsAndNestedDayCells() throws {
        #expect(try ShapeRoleTestSupport.source("Planner/Components/CalendarGrid.swift").contains("DS.RoleShape(.nested, legacy: TopLeftChamferedRectangle(.small, cornerRadius: 10))"))
        #expect(try ShapeRoleTestSupport.source("Planner/CalendarMonthView.swift").contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        let banners = try ShapeRoleTestSupport.source("Planner/Components/CalendarBanners.swift")
        #expect(banners.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects + [CGRect(x: 3, y: 7, width: 42, height: 52)] {
            ShapeRoleTestSupport.check(.nested, legacy: TopLeftChamferedRectangle(.small, cornerRadius: 10), expected: MainTopLeftChamferedRectangle(chamferSize: 8, cornerRadius: 10).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangleAlt(.large), expected: MainChamferedRectangleAlt(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous), expected: RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func dayDetailsAndPlannedCardsKeepLegacyContours() throws {
        let detail = try ShapeRoleTestSupport.source("Planner/Components/DayDetailView.swift")
        #expect(detail.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.medium))"))
        #expect(detail.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        #expect(try ShapeRoleTestSupport.source("Planner/Components/DayActionCard.swift").contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10))"))
        #expect(try ShapeRoleTestSupport.source("Planner/Components/PlannedWorkoutComponents.swift").contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous), expected: RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func plannedEditorAlertAndSearchKeepLegacyPaths() throws {
        let editor = try ShapeRoleTestSupport.source("Planner/Views/PlannedWorkoutEditor.swift")
        #expect(editor.contains("DS.RoleShape(.alert, legacy: ChamferedRectangle(.xl))"))
        #expect(editor.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))"))
        #expect(try ShapeRoleTestSupport.source("Planner/Components/ExercisePickerView.swift").contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.alert, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 36)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func predefinedOptionCardsAndNavigationKeepLegacyPaths() throws {
        #expect(try ShapeRoleTestSupport.source("Planner/Views/PredefinedSplit/Step2TrainingFrequency.swift").contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        let length = try ShapeRoleTestSupport.source("Planner/Views/PredefinedSplit/Step5ProgramLength.swift")
        #expect(length.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 16))"))
        #expect(length.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12))"))
        #expect(try ShapeRoleTestSupport.source("Planner/PlannerSetupCarouselView.swift").contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 12))"))
        #expect(try ShapeRoleTestSupport.source("Planner/Views/PredefinedSplit/Step4CustomizeExercises.swift").contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 16), expected: RoundedRectangle(cornerRadius: 16).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func customSplitFieldsOptionCardsAndSearchPreserveLegacyPaths() throws {
        let custom = try ShapeRoleTestSupport.source("Planner/Views/CustomSplit/CustomSplitSteps.swift")
        #expect(custom.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(custom.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12))"))
        #expect(custom.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10))"))
        #expect(try ShapeRoleTestSupport.source("Planner/Views/CustomSplit/CustomSplitExercisePicker.swift").contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func libraryShareCardsAndHeaderControlsPreserveLegacyPaths() throws {
        let library = try ShapeRoleTestSupport.source("Planner/Views/Library/ProgramLibraryView.swift")
        #expect(library.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        let header = try #require(library.range(of: "private struct ProgramSheetHeaderButtonStyle"))
        let end = try #require(library.range(of: "private struct ProgramShareHeroCard"))
        #expect(library[header.lowerBound..<end.lowerBound].contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        for rect in ShapeRoleTestSupport.rects + [CGRect(x: 3, y: 7, width: 92, height: 46)] {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func inviteNestedFieldsStandaloneSteppersAndFootersPreserveLegacyPaths() throws {
        let library = try ShapeRoleTestSupport.source("Planner/Views/Library/ProgramLibraryView.swift")
        let start = try #require(library.range(of: "private struct ProgramExerciseStepperRow"))
        let end = try #require(library.range(of: "private struct ProgramInviteUnavailableCard"))
        #expect(library[start.lowerBound..<end.lowerBound].contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(library.contains("DS.RoleShape(.nested, legacy: ChamferedRectangle(.medium))"))
        let footer = try #require(library.range(of: "private struct ProgramFooterButton"))
        #expect(library[footer.lowerBound...].contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.nested, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
