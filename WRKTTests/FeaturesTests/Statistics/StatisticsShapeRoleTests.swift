import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct StatisticsShapeRoleTests {
    #if DEBUG
    @Test func exerciseStatisticsKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Statistics/Views/ExerciseStatisticsView.swift")
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.micro))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(source0.contains("DS.RoleShape(.tile, legacy: ChamferedRectangleAlt(.large))"))
        #expect(source0.contains("DS.RoleShape(.tile, legacy: ChamferedRectangle(.large))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangleAlt(.micro), expected: MainChamferedRectangleAlt(.micro).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.tile, legacy: ChamferedRectangleAlt(.large), expected: MainChamferedRectangleAlt(.large).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.tile, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    @Test func trainingTrendsAndBalanceKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Statistics/Views/ProfileStatsSection.swift")
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source0.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 16, style: .continuous))"))
        #expect(source0.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 5, style: .continuous))"))
        let source1 = try ShapeRoleTestSupport.source("Statistics/Views/TrainingBalanceSection.swift")
        #expect(source1.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source1.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(source1.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 6))"))
        #expect(source1.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 8))"))
        #expect(source1.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 12))"))
        #expect(source1.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 10))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 16, style: .continuous), expected: RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 5, style: .continuous), expected: RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 6), expected: RoundedRectangle(cornerRadius: 6).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 8), expected: RoundedRectangle(cornerRadius: 8).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: 10)
        }
    }
    #endif
}
