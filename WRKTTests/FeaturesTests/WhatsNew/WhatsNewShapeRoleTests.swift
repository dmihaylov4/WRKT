import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct WhatsNewShapeRoleTests {
    #if DEBUG
    @Test func whatsNewKeepsLegacyPath() throws {
        let source = try ShapeRoleTestSupport.source("WhatsNew/WhatsNewView.swift")
        #expect(source.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
