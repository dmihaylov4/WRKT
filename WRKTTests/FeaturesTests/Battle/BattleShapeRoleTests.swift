import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct BattleShapeRoleTests {
    #if DEBUG
    @Test func cardsControlsNestedStatsAndInsetBordersPreserveLegacyPaths() throws {
        let list = try ShapeRoleTestSupport.source("Battles/Views/BattlesListView.swift")
        #expect(list.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 16))"))
        #expect(list.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 12))"))
        #expect(list.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(list.contains(".strokeBorder(DS.Semantic.border.opacity(0.3), lineWidth: 1)"))
        let detail = try ShapeRoleTestSupport.source("Battles/Views/BattleDetailView.swift")
        #expect(detail.contains("DS.RoleShape(.control, legacy: SingleChamferedRectangle(corner: .topTrailing, .large))"))
        #expect(detail.contains("DS.RoleShape(.nested, legacy: ChamferedRectangleAlt(.medium))"))
        let create = try ShapeRoleTestSupport.source("Battles/Views/CreateBattleView.swift")
        #expect(create.contains("DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.medium))"))
        #expect(create.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangleAlt(.small))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 16), expected: RoundedRectangle(cornerRadius: 16).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.control, legacy: SingleChamferedRectangle(corner: .topTrailing, .large), expected: MainSingleChamferedRectangle(corner: .topTrailing, chamferSize: 16).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangleAlt(.medium), expected: MainChamferedRectangleAlt(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.nested, legacy: ChamferedRectangleAlt(.medium), expected: MainChamferedRectangleAlt(.medium).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangleAlt(.small), expected: MainChamferedRectangleAlt(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
            let legacy = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let inset = DS.RoleShape(.control, legacy: legacy).inset(by: 0.5)
            #expect(inset.path(in: rect, rounded: false).cgPath == legacy.inset(by: 0.5).path(in: rect).cgPath)
            #expect(inset.path(in: rect, rounded: true).cgPath == RoundedRectangle(cornerRadius: min(rect.width, rect.height) / 2 - 0.5, style: .continuous).path(in: rect.insetBy(dx: 0.5, dy: 0.5)).cgPath)
        }
    }
    #endif
}
