import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct HomeShapeRoleTests {
    #if DEBUG
    @Test func carouselSurfacePreservesChamfersAndUsesCardRadius() {
        let shape = HomeCarouselCard { Color.clear }.surfaceShape
        for rect in [CGRect(x: 3, y: 7, width: 340, height: 174),
                     CGRect(x: 3, y: 7, width: 40, height: 30)] {
            #expect(shape.path(in: rect, rounded: false).cgPath == MainChamferedRectangle(.large).path(in: rect).cgPath)
            let radius = min(26, rect.width / 2, rect.height / 2)
            #expect(shape.path(in: rect, rounded: true).cgPath == RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
        }
    }

    @Test func clickableCardSectionsKeepTheirNestedContour() {
        let shape = ClickableSectionStyle().surfaceShape
        let rect = CGRect(x: 3, y: 7, width: 320, height: 64)
        let legacy = RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect)
        #expect(shape.path(in: rect, rounded: false).cgPath == legacy.cgPath)
        #expect(shape.path(in: rect, rounded: true).cgPath == legacy.cgPath)
        #expect(shape.roundedShape.role == .nested)
    }
    #endif
}
