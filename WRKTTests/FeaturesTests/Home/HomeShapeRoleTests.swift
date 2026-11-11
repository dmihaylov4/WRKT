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

    @Test func weeklyChipsPreserveMicroChamfersAndStayControlsAtEverySize() {
        let card = UnifiedWeeklyStatsCard(strengthCompleted: 2, strengthTarget: 2,
                                         cardioMinutes: 150, cardioTarget: 150, daysRemaining: 3)
        for rect in [CGRect(x: 3, y: 7, width: 60, height: 18),
                     CGRect(x: 3, y: 7, width: 28, height: 36),
                     CGRect(x: 3, y: 7, width: 180, height: 60)] {
            let shape = card.chipShape
            #expect(shape.path(in: rect, rounded: false).cgPath == MainChamferedRectangleAlt(.micro).path(in: rect).cgPath)
            let radius = min(rect.width, rect.height) / 2
            #expect(shape.path(in: rect, rounded: true).cgPath == RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
        }
    }

    @Test func heroKeepsItsLegacyChamferAndRoundedBorderContour() {
        let hero = HeroStartWorkoutButton(
            content: HeroButtonContent(icon: "", mainText: "Start Workout", secondaryText: "", hasPlan: false),
            onTap: {}
        )
        let rect = CGRect(x: 3, y: 7, width: 340, height: 210)
        #expect(hero.surfaceShape.path(in: rect, rounded: false).cgPath == MainChamferedRectangle(.hero).path(in: rect).cgPath)
        #expect(hero.surfaceShape.path(in: rect, rounded: true).cgPath == DS.Radius.roundedChamferPath(DS.Chamfer.hero.size, in: rect).cgPath)
    }

    @Test func liveWorkoutControlPreservesNativeCornersAndUsesCapsule() {
        let content = LiveWorkoutHeroContent(exercises: 2, completedSets: 3, startDate: .now,
                                             onAddExercise: {}, onViewWorkout: {})
        for height in [40, 60] as [CGFloat] {
            let rect = CGRect(x: 3, y: 7, width: 240, height: height)
            #expect(content.viewWorkoutShape.path(in: rect, rounded: false).cgPath == RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect).cgPath)
            #expect(content.viewWorkoutShape.path(in: rect, rounded: true).cgPath == RoundedRectangle(cornerRadius: height / 2, style: .continuous).path(in: rect).cgPath)
        }
    }
    #endif
}
