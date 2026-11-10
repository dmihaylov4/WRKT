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

    private func check<L: SwiftUI.Shape>(_ shape: DS.RoleShape<L>, in rect: CGRect,
                                        radius: CGFloat, legacy: Path) {
        let rounded = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        #expect(shape.path(in: rect, rounded: true).cgPath == rounded.cgPath)
        #expect(shape.path(in: rect, rounded: false).cgPath == legacy.cgPath)
    }
    #endif
}
