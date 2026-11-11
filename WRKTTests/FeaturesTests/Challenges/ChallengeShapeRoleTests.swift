import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct ChallengeShapeRoleTests {
    #if DEBUG
    @Test func cardsBadgesAndNestedLeaderboardRowsPreserveLegacyPaths() throws {
        let browse = try ShapeRoleTestSupport.source("Challenges/Views/ChallengesBrowseView.swift")
        #expect(browse.contains("DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.large))"))
        #expect(browse.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        let detail = try ShapeRoleTestSupport.source("Challenges/Views/ChallengeDetailView.swift")
        #expect(detail.contains("DS.RoleShape(.nested, legacy: ChamferedRectangle(.large))"))
        #expect(detail.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.micro))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangleAlt(.large), expected: MainChamferedRectangleAlt(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.micro), expected: MainChamferedRectangle(.micro).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
