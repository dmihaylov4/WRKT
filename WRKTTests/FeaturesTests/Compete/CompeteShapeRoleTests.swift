import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct CompeteShapeRoleTests {
    #if DEBUG
    @Test func pairedAndSingleCardContoursAndIconTilesKeepLegacyGeometry() throws {
        let compete = try ShapeRoleTestSupport.source("Compete/UnifiedCompeteView.swift")
        #expect(compete.contains("DS.RoleShape(.card, legacy: PairedChamferedRectangle(pair: tilePair, .xl))"))
        #expect(compete.contains("DS.RoleShape(.card, legacy: SingleChamferedRectangle(corner: gridPosition.chamferCorner, .large))"))
        #expect(compete.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangleAlt(.small))"))
        for file in ["BattleRewardPreviewBlock.swift", "ChallengeRewardPreviewBlock.swift"] {
            #expect(try ShapeRoleTestSupport.source("Compete/Views/" + file).contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        }
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: PairedChamferedRectangle(pair: .leadingTile, .xl), expected: MainPairedChamferedRectangle(pair: .leadingTile, chamferSize: 20).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: PairedChamferedRectangle(pair: .trailingTile, .xl), expected: MainPairedChamferedRectangle(pair: .trailingTile, chamferSize: 20).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: SingleChamferedRectangle(corner: .topLeading, .large), expected: MainSingleChamferedRectangle(corner: .topLeading, chamferSize: 16).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: SingleChamferedRectangle(corner: .topTrailing, .large), expected: MainSingleChamferedRectangle(corner: .topTrailing, chamferSize: 16).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangleAlt(.small), expected: MainChamferedRectangleAlt(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
        }
    }
    #endif
}
