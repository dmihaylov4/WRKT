import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct OnboardingShapeRoleTests {
    #if DEBUG
    @Test func onboardingAndGoalSetupKeepLegacyPaths() throws {
        let carousel = try ShapeRoleTestSupport.source("Onboarding/OnboardingCarousel.swift")
        #expect(carousel.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        #expect(carousel.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(carousel.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangle(.xl))"))
        let goal = try ShapeRoleTestSupport.source("Onboarding/WeeklyGoalSetupView.swift")
        #expect(goal.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        #expect(goal.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(goal.contains("DS.RoleShape(.nested, legacy: ChamferedRectangle(.small))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
            ShapeRoleTestSupport.check(.nested, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: 10)
        }
    }
    #endif
}
