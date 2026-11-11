import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct HealthShapeRoleTests {
    #if DEBUG
    @Test func cardioOverviewKeepsLegacyPaths() throws {
        let source = try ShapeRoleTestSupport.source("Health/Views/CardioView.swift")
        #expect(source.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        #expect(source.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(source.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(source.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        // Odometer digit cells and route map clips stay untouched by decision.
        #expect(source.contains("                RoundedRectangle(cornerRadius: 4, style: .continuous)\n                    .fill(Color(red: 0.05, green: 0.05, blue: 0.08))"))
        #expect(source.contains(".clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous), expected: RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect), rect: rect, radius: 10)
        }
    }
    @Test func cardioDetailAndChartsKeepLegacyPaths() throws {
        let detail = try ShapeRoleTestSupport.source("Health/Views/CardioDetailView.swift")
        #expect(detail.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        #expect(detail.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 16))"))
        #expect(detail.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        #expect(detail.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 20, style: .continuous))"))
        #expect(detail.contains("DS.RoleShape(.tile, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        // Route map clips stay untouched by decision.
        #expect(detail.contains(".clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))"))
        let charts = try ShapeRoleTestSupport.source("Health/Views/CardioCharts.swift")
        #expect(charts.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 14))"))
        #expect(charts.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 10))"))
        #expect(charts.contains("DS.RoleShape(.card, legacy: ChamferedRectangleAlt(.large))"))
        #expect(charts.contains("DS.RoleShape(.nested, legacy: ChamferedRectangleAlt(.medium))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous), expected: RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 16), expected: RoundedRectangle(cornerRadius: 16).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous), expected: RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 20, style: .continuous), expected: RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.tile, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 14), expected: RoundedRectangle(cornerRadius: 14).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangleAlt(.large), expected: MainChamferedRectangleAlt(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: ChamferedRectangleAlt(.medium), expected: MainChamferedRectangleAlt(.medium).path(in: rect), rect: rect, radius: 10)
        }
    }
    @Test func strengthDetailSyncAndAuthKeepLegacyPaths() throws {
        let strength = try ShapeRoleTestSupport.source("Health/Views/HealthKitStrengthDetailView.swift")
        #expect(strength.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 20, style: .continuous))"))
        #expect(strength.contains("DS.RoleShape(.tile, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        #expect(strength.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        let sync = try ShapeRoleTestSupport.source("Health/Views/HealthKitSyncProgress.swift")
        #expect(sync.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 16, style: .continuous))"))
        // The sync progress bar stays untouched.
        #expect(sync.contains("                            RoundedRectangle(cornerRadius: 4, style: .continuous)\n                                .fill(Theme.surface2)"))
        let auth = try ShapeRoleTestSupport.source("Health/Views/HealthAuthSheet.swift")
        #expect(auth.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(auth.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 16, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 20, style: .continuous), expected: RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.tile, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous), expected: RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 14, style: .continuous), expected: RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 16, style: .continuous), expected: RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 16, style: .continuous), expected: RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
