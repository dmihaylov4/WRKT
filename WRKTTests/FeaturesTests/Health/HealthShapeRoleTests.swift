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
    #endif
}
