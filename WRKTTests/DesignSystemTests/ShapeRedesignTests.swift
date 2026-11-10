import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct ShapeRedesignTests {
    @Test func tokenMapping() {
        let cases: [(DS.Chamfer, CGFloat)] = [
            (.micro, 6), (.small, 10), (.medium, 16),
            (.large, 26), (.xl, 26), (.hero, 26)
        ]
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        for (token, expected) in cases {
            #expect(DS.Radius.roundedChamferRadius(token.size, in: rect) == expected)
        }
    }

    @Test func explicitCutsInterpolateBetweenAnchors() {
        let cases: [(CGFloat, CGFloat)] = [
            (-1, 0), (0, 0), (2, 3), (5, 7), (7, 9),
            (10, 13), (14, 21), (18, 26), (28, 26)
        ]
        for (cut, radius) in cases {
            #expect(DS.Radius.mappedChamferRadius(cut) == radius)
        }
    }

    @Test func widthAndHeightClampIndependently() {
        #expect(DS.Radius.roundedChamferRadius(16, in: CGRect(x: 0, y: 0, width: 20, height: 100)) == 10)
        #expect(DS.Radius.roundedChamferRadius(16, in: CGRect(x: 0, y: 0, width: 55, height: 42)) == 21)
        #expect(DS.Radius.roundedChamferRadius(16, in: CGRect(x: 0, y: 0, width: 0, height: 100)) == 0)
        #expect(DS.Radius.roundedChamferRadius(16, in: CGRect(x: 0, y: 0, width: 100, height: 0)) == 0)
    }

    @Test func capsuleHeightThresholdIncludesForty() {
        for height in [39.99, 40] as [CGFloat] {
            #expect(DS.Radius.roundedChamferRadius(4, in: CGRect(x: 0, y: 0, width: 100, height: height)) == height / 2)
        }
        #expect(DS.Radius.roundedChamferRadius(4, in: CGRect(x: 0, y: 0, width: 100, height: 40.01)) == 6)
    }

    @Test func capsuleAspectThresholdIncludesOnePointFive() {
        #expect(DS.Radius.roundedChamferRadius(4, in: CGRect(x: 0, y: 0, width: 29.99, height: 20)) == 6)
        for width in [30, 30.01] as [CGFloat] {
            #expect(DS.Radius.roundedChamferRadius(4, in: CGRect(x: 0, y: 0, width: width, height: 20)) == 10)
        }
    }

    @Test func squareIconsAndCalendarCellsAvoidCapsuleRule() {
        #expect(DS.Radius.roundedChamferRadius(8, in: CGRect(x: 0, y: 0, width: 36, height: 36)) == 10)
        #expect(DS.Radius.roundedChamferRadius(8, in: CGRect(x: 0, y: 0, width: 44, height: 52)) == 10)
        #expect(DS.Radius.roundedChamferRadius(16, in: CGRect(x: 0, y: 0, width: 100, height: 50)) == 25)
        #expect(DS.Radius.roundedChamferRadius(12, in: CGRect(x: 0, y: 0, width: 100, height: 50)) == 16)
    }

    @Test func roundedVariantsHaveIdenticalContinuousPaths() {
        for rect in bounds {
            for cut in [4, 8, 12, 16, 20, 24, 5, 7, 28] as [CGFloat] {
                let radius = DS.Radius.roundedChamferRadius(cut, in: rect)
                let expected = bytes(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect))
                for path in paths(cut: cut, rect: rect, rounded: true) {
                    #expect(bytes(path) == expected)
                }
            }
        }
    }

    @Test func disabledVariantsMatchMainPathBytes() {
        for rect in bounds {
            for cut in [-3, 0, 4, 5, 7, 8, 10, 12, 16, 20, 24, 28, 100] as [CGFloat] {
                let actual = paths(cut: cut, rect: rect, rounded: false)
                let expected = mainPaths(cut: cut, rect: rect)
                for (path, baseline) in zip(actual, expected) {
                    #expect(bytes(path) == bytes(baseline))
                }
            }
        }
    }

    @Test func publicPathsFollowTheCachedLaunchSwitch() {
        let rect = CGRect(x: 13, y: 27, width: 320, height: 120)
        let expected = paths(cut: 16, rect: rect, rounded: DS.Redesign.roundedShapesEnabled)
        let actual: [Path] = [
            ChamferedRectangle(.large).path(in: rect),
            ChamferedRectangleAlt(.large).path(in: rect),
            TopLeftChamferedRectangle(.large, cornerRadius: 7.25).path(in: rect),
            SingleChamferedRectangle(corner: .topLeading, .large).path(in: rect),
            SingleChamferedRectangle(corner: .topTrailing, .large).path(in: rect),
            SingleChamferedRectangle(corner: .bottomLeading, .large).path(in: rect),
            SingleChamferedRectangle(corner: .bottomTrailing, .large).path(in: rect),
            PairedChamferedRectangle(pair: .leadingTile, .large).path(in: rect),
            PairedChamferedRectangle(pair: .trailingTile, .large).path(in: rect)
        ]
        for (path, baseline) in zip(actual, expected) {
            #expect(bytes(path) == bytes(baseline))
        }
        #if DEBUG
        #expect(DS.Redesign.roundedShapesDefault)
        #else
        #expect(!DS.Redesign.roundedShapesDefault)
        #expect(!DS.Redesign.roundedShapesEnabled)
        for (path, baseline) in zip(actual, mainPaths(cut: 16, rect: rect)) {
            #expect(bytes(path) == bytes(baseline))
        }
        #endif
    }

    @Test func publicChamferSizeMutationStillDeterminesRoundedRadius() {
        var shape = ChamferedRectangle(.large)
        shape.chamferSize = 5
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(bytes(shape.path(in: rect, rounded: true)) == bytes(RoundedRectangle(cornerRadius: 7, style: .continuous).path(in: rect)))
    }

    @Test func roleTokensPreserveExistingValues() {
        #expect([DS.Radius.s, DS.Radius.m, DS.Radius.l, DS.Radius.xl, DS.Radius.pill] == [8, 12, 16, 24, 999])
        #expect([DS.Radius.card, DS.Radius.nested, DS.Radius.tile, DS.Radius.popover, DS.Radius.alert, DS.Radius.sheet] == [26, 10, 16, 32, 36, 36])
        #expect(DS.Radius.nested(parentRadius: 26, padding: 16) == 10)
        #expect(DS.Radius.nested(parentRadius: 16, padding: 16) == 8)
        #expect(DS.Radius.iconTile(side: 40) == 9)
    }

    @Test func roleShapesUseContinuousPathsWithoutCompatibilityCapsules() {
        let rect = CGRect(x: 7, y: 11, width: 100, height: 40)
        let cases: [(DS.Shape.Role, CGFloat)] = [
            (.card, 20), (.nested, 10), (.tile, 16), (.popover, 20),
            (.alert, 20), (.sheet, 20), (.control, 20), (.iconTile, 9)
        ]
        for (role, radius) in cases {
            #expect(bytes(DS.Shape(role).path(in: rect)) == bytes(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)))
        }
    }

    @Test func roleShapeInsetsPreserveTheOuterContour() {
        let rect = CGRect(x: 7, y: 11, width: 200, height: 100)
        let actual = DS.Shape(.card).inset(by: 2).inset(by: 3).path(in: rect)
        let expected = RoundedRectangle(cornerRadius: 21, style: .continuous).path(in: rect.insetBy(dx: 5, dy: 5))
        #expect(bytes(actual) == bytes(expected))
        #expect(DS.Shape(.card).inset(by: 100).path(in: rect).isEmpty)
    }

    private var bounds: [CGRect] {
        [
            CGRect(x: 0, y: 0, width: 320, height: 120),
            CGRect(x: 19.5, y: 7.25, width: 100, height: 40),
            CGRect(x: -13, y: 6, width: 28, height: 28),
            CGRect(x: 0, y: 0, width: 8, height: 80),
            CGRect(x: 3, y: 5, width: 0, height: 0)
        ]
    }

    private func paths(cut: CGFloat, rect: CGRect, rounded: Bool) -> [Path] {
        [
            ChamferedRectangle(chamferSize: cut).path(in: rect, rounded: rounded),
            ChamferedRectangleAlt(chamferSize: cut).path(in: rect, rounded: rounded),
            TopLeftChamferedRectangle(chamferSize: cut, cornerRadius: 7.25).path(in: rect, rounded: rounded),
            SingleChamferedRectangle(corner: .topLeading, chamferSize: cut).path(in: rect, rounded: rounded),
            SingleChamferedRectangle(corner: .topTrailing, chamferSize: cut).path(in: rect, rounded: rounded),
            SingleChamferedRectangle(corner: .bottomLeading, chamferSize: cut).path(in: rect, rounded: rounded),
            SingleChamferedRectangle(corner: .bottomTrailing, chamferSize: cut).path(in: rect, rounded: rounded),
            PairedChamferedRectangle(pair: .leadingTile, chamferSize: cut).path(in: rect, rounded: rounded),
            PairedChamferedRectangle(pair: .trailingTile, chamferSize: cut).path(in: rect, rounded: rounded)
        ]
    }

    private func mainPaths(cut: CGFloat, rect: CGRect) -> [Path] {
        [
            MainChamferedRectangle(chamferSize: cut).path(in: rect),
            MainChamferedRectangleAlt(chamferSize: cut).path(in: rect),
            MainTopLeftChamferedRectangle(chamferSize: cut, cornerRadius: 7.25).path(in: rect),
            MainSingleChamferedRectangle(corner: .topLeading, chamferSize: cut).path(in: rect),
            MainSingleChamferedRectangle(corner: .topTrailing, chamferSize: cut).path(in: rect),
            MainSingleChamferedRectangle(corner: .bottomLeading, chamferSize: cut).path(in: rect),
            MainSingleChamferedRectangle(corner: .bottomTrailing, chamferSize: cut).path(in: rect),
            MainPairedChamferedRectangle(pair: .leadingTile, chamferSize: cut).path(in: rect),
            MainPairedChamferedRectangle(pair: .trailingTile, chamferSize: cut).path(in: rect)
        ]
    }

    // Serialize element tags and coordinate bits, excluding opaque CGPath storage.
    private func bytes(_ path: Path) -> Data {
        var result = Data()
        path.cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            var tag = element.type.rawValue.littleEndian
            withUnsafeBytes(of: &tag) { result.append(contentsOf: $0) }
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for index in 0..<count {
                for coordinate in [element.points[index].x, element.points[index].y] {
                    var bits = Double(coordinate).bitPattern.littleEndian
                    withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
                }
            }
        }
        return result
    }
}
