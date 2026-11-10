import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct RoleShapeTests {
    @Test func productionPathCannotBypassTheLaunchSwitch() {
        let rect = CGRect(x: 11, y: 7, width: 100, height: 50)
        let shape = DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))
        let expected = DS.Redesign.roundedShapesEnabled
            ? DS.Shape(.control).path(in: rect)
            : MainChamferedRectangle(chamferSize: 12).path(in: rect)
        #expect(shape.path(in: rect).cgPath == expected.cgPath)
        #if !DEBUG
        #expect(!DS.Redesign.roundedShapesEnabled)
        #endif
    }

    #if DEBUG
    @Test func disabledBranchPreservesEveryChamferVariant() {
        let rect = CGRect(x: 11, y: 7, width: 100, height: 50)
        check(DS.RoleShape(.control, legacy: ChamferedRectangle(.medium)), in: rect,
              radius: 25, legacy: MainChamferedRectangle(chamferSize: 12).path(in: rect))
        check(DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.medium)), in: rect,
              radius: 25, legacy: MainChamferedRectangleAlt(chamferSize: 12).path(in: rect))
        check(DS.RoleShape(.tile, legacy: TopLeftChamferedRectangle(.small, cornerRadius: 7)), in: rect,
              radius: 16, legacy: MainTopLeftChamferedRectangle(chamferSize: 8, cornerRadius: 7).path(in: rect))
        check(DS.RoleShape(.nested, legacy: SingleChamferedRectangle(corner: .bottomTrailing, .large)), in: rect,
              radius: 10, legacy: MainSingleChamferedRectangle(corner: .bottomTrailing, chamferSize: 16).path(in: rect))
        check(DS.RoleShape(.card, legacy: PairedChamferedRectangle(pair: .trailingTile, .large)), in: rect,
              radius: 25, legacy: MainPairedChamferedRectangle(pair: .trailingTile, chamferSize: 16).path(in: rect))
    }

    @Test func nativeLegacyStylesAndRepeatedInsetsAreExact() {
        let rect = CGRect(x: 11, y: 7, width: 200, height: 100)
        for style in [RoundedCornerStyle.circular, .continuous] {
            let legacy = RoundedRectangle(cornerRadius: 20, style: style)
            let shape = DS.RoleShape(.popover, legacy: legacy).inset(by: 1).inset(by: 2)
            #expect(shape.path(in: rect, rounded: false).cgPath == legacy.inset(by: 1).inset(by: 2).path(in: rect).cgPath)
            #expect(shape.path(in: rect, rounded: true).cgPath == DS.Shape(.popover).inset(by: 3).path(in: rect).cgPath)
        }
        check(DS.RoleShape(.control, legacy: Capsule()), in: rect, radius: 50, legacy: Capsule().path(in: rect))
    }

    @Test func buttonSizesAndFloatingControlsUseCapsules() {
        for size in [DS.ButtonSize.compact, .regular, .large] {
            for width in [20, 60, 240] as [CGFloat] {
                let rect = CGRect(x: 3, y: 5, width: width, height: size.height)
                let legacy = RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: rect)
                check(DS.PrimaryButtonStyle(size: size).surfaceShape, in: rect,
                      radius: min(width, size.height) / 2, legacy: legacy)
                check(DS.SecondaryButtonStyle(size: size).surfaceShape, in: rect,
                      radius: min(width, size.height) / 2, legacy: legacy)
            }
        }
        for side in [48, 56] as [CGFloat] {
            let rect = CGRect(x: 3, y: 5, width: side, height: side)
            check(DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.large)), in: rect,
                  radius: side / 2, legacy: MainChamferedRectangleAlt(chamferSize: 16).path(in: rect))
        }
    }

    @Test func chipsAndBadgesRemainControlsAtNarrowAndLargeSizes() {
        for rect in [CGRect(x: 0, y: 0, width: 28, height: 36), CGRect(x: 4, y: 7, width: 180, height: 60)] {
            let radius = min(rect.width, rect.height) / 2
            check(DS.Chip(title: "All").surfaceShape, in: rect, radius: radius, legacy: Capsule().path(in: rect))
            check(PremiumChip(title: "All", icon: "star", color: .blue).surfaceShape,
                  in: rect, radius: radius, legacy: Capsule().path(in: rect))
            check(DataQualityBadge(quality: .estimated).surfaceShape, in: rect, radius: radius,
                  legacy: RoundedRectangle(cornerRadius: 4).path(in: rect))
        }
    }

    @Test func cardsAndInputRolesPreserveNativeLegacyContours() {
        let rect = CGRect(x: 5, y: 9, width: 240, height: 80)
        check(DS.Card().surfaceShape, in: rect, radius: 26,
              legacy: RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect))
        for (role, radius) in [(DS.Shape.Role.control, CGFloat(40)), (.card, 26), (.nested, 10)] {
            for style in [RoundedCornerStyle.circular, .continuous] {
                let legacy = RoundedRectangle(cornerRadius: 16, style: style)
                check(DS.RoleShape(role, legacy: legacy), in: rect, radius: radius, legacy: legacy.path(in: rect))
            }
        }
    }

    @Test func feedbackSurfacesRespectPlacementAndKeepTheirLegacyShapes() {
        let rect = CGRect(x: 3, y: 5, width: 240, height: 100)
        let error = UserFriendlyError(title: "Offline", message: "Retry", isRetryable: true)
        for (role, radius) in [(DS.Shape.Role.card, CGFloat(26)), (.nested, 10)] {
            check(InlineErrorView(error: error, role: role).surfaceShape, in: rect, radius: radius,
                  legacy: RoundedRectangle(cornerRadius: 12).path(in: rect))
            var compact = CompactErrorView(message: "Retry", onRetry: nil)
            compact.role = role
            check(compact.surfaceShape, in: rect, radius: radius,
                  legacy: RoundedRectangle(cornerRadius: 8).path(in: rect))
        }
        #expect(InlineErrorView(error: error).surfaceShape.roundedShape.role == .card)
        #expect(CompactErrorView(message: "Retry", onRetry: nil).surfaceShape.roundedShape.role == .card)
        check(UndoToast(message: "Undo", onUndo: {}, isShowing: .constant(true)).surfaceShape,
              in: rect, radius: 26, legacy: MainChamferedRectangle(chamferSize: 16).path(in: rect))
        check(WorkoutToast(message: "Saved", isShowing: .constant(true)).surfaceShape,
              in: rect, radius: 26, legacy: MainChamferedRectangle(chamferSize: 16).path(in: rect))
        check(ErrorView(error: error).retryShape, in: rect, radius: 50, legacy: Capsule().path(in: rect))
        check(OfflineBanner(queueCount: 1, onSync: {}).syncShape,
              in: rect, radius: 50, legacy: Capsule().path(in: rect))
    }

    @Test func swipeTrackAndKnobUseControlContours() {
        let control = SwipeToConfirm(text: "Confirm", systemImage: "checkmark", onConfirm: {})
        for height in [48, 64, 80] as [CGFloat] {
            let rect = CGRect(x: 3, y: 5, width: 280, height: height)
            check(control.trackShape(height: height), in: rect, radius: height / 2,
                  legacy: RoundedRectangle(cornerRadius: height / 2, style: .continuous).path(in: rect))
            let square = CGRect(x: 3, y: 5, width: height, height: height)
            check(control.knobShape, in: square, radius: height / 2, legacy: Circle().path(in: square))
        }
    }

    @Test func tutorialUsesPopoverAndControlWithExactLegacyInsets() {
        let rect = CGRect(x: 3, y: 5, width: 300, height: 160)
        let legacy = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let tooltip = DS.RoleShape(.popover, legacy: legacy)
        check(tooltip, in: rect, radius: 32, legacy: legacy.path(in: rect))
        #expect(tooltip.inset(by: 0.5).path(in: rect, rounded: false).cgPath == legacy.inset(by: 0.5).path(in: rect).cgPath)
        #expect(tooltip.inset(by: 0.5).path(in: rect, rounded: true).cgPath == DS.Shape(.popover).inset(by: 0.5).path(in: rect).cgPath)
        let button = CGRect(x: 0, y: 0, width: 120, height: 56)
        check(DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous)),
              in: button, radius: 28, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: button))
    }

    @Test func narrowAllChipsAndFiftyPointSteppersIgnoreTheHeuristic() {
        for rect in [CGRect(x: 0, y: 0, width: 44, height: 36), CGRect(x: 3, y: 7, width: 70, height: 60)] {
            check(DS.RoleShape(.control, legacy: ChamferedRectangle(.small)), in: rect,
                  radius: min(rect.width, rect.height) / 2, legacy: MainChamferedRectangle(chamferSize: 8).path(in: rect))
        }
        let rect = CGRect(x: 0, y: 0, width: 50, height: 50)
        check(DS.RoleShape(.control, legacy: ChamferedRectangle(.medium)), in: rect,
              radius: 25, legacy: MainChamferedRectangle(chamferSize: 12).path(in: rect))
    }

    private func check<L: SwiftUI.Shape>(_ shape: DS.RoleShape<L>, in rect: CGRect,
                                        radius: CGFloat, legacy: Path) {
        let rounded = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        #expect(shape.path(in: rect, rounded: true).cgPath == rounded.cgPath)
        #expect(shape.path(in: rect, rounded: false).cgPath == legacy.cgPath)
    }
    #endif
}
