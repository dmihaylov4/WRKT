import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct NotificationShapeRoleTests {
    #if DEBUG
    @Test func inAppNotificationSurfacesAreCardsWithLegacyPaths() throws {
        let source = try ShapeRoleTestSupport.source("../Core/Utilities/NotificationSystem/NotificationView.swift")
        #expect(source.components(separatedBy: "DS.RoleShape(.card, legacy: ChamferedRectangle(.large))").count - 1 == 4)
        #expect(!source.contains("            ChamferedRectangle(.large)\n"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
        }
    }
    #endif
}
