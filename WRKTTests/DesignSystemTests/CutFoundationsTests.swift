import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
struct CutFoundationsTests {
    // MARK: Gate

    @Test func gateFollowsBuildDefaultAndOverride() {
        #expect(DS.Redesign.cutDefault == true)
        let stored = UserDefaults.standard.object(forKey: DS.Redesign.cutPreferenceKey)
        let expected = stored == nil ? DS.Redesign.cutDefault : UserDefaults.standard.bool(forKey: DS.Redesign.cutPreferenceKey)
        #expect(DS.Redesign.cutEnabled == expected)
    }

    // MARK: Fonts

    @Test func condensedFacesAreRegistered() {
        #expect(UIFont(name: DS.Cut.Typography.condensedBold, size: 17) != nil)
        #expect(UIFont(name: DS.Cut.Typography.condensedExtraBold, size: 17) != nil)
    }

    @Test func noCutTextStyleIsBelow15Points() {
        for style in DS.Cut.Typography.Style.allCases {
            #expect(style.size >= 15)
        }
        for hero in DS.Cut.Typography.Hero.allCases {
            #expect(hero.size >= 34)
        }
    }

    @Test func heroLinesSplitOnNewlines() {
        #expect(CutHeroText.lines(of: "Upper\nBody") == ["Upper", "Body"])
        #expect(CutHeroText.lines(of: "Done.") == ["Done."])
        #expect(CutHeroText.lines(of: "No plan\n\nyet\n") == ["No plan", "yet"])
    }

    @Test func balancedHeroLinesBreakAtWordsOnly() {
        #expect(CutHeroText.balancedLines("Upper Body") == "Upper\nBody")
        #expect(CutHeroText.balancedLines("No plan yet") == "No plan\nyet")
        #expect(CutHeroText.balancedLines("Rest day") == "Rest\nday")
        #expect(CutHeroText.balancedLines("Push") == "Push")
        #expect(CutHeroText.balancedLines("  Leg   day ") == "Leg\nday")
        #expect(CutHeroText.balancedLines("Already\nset") == "Already\nset")
        #expect(CutHeroText.balancedLines("") == "")
        let long = CutHeroText.balancedLines("Posterior Chain and Conditioning Superset")
        #expect(CutHeroText.lines(of: long).count == 2)
        #expect(long.replacingOccurrences(of: "\n", with: " ") == "Posterior Chain and Conditioning Superset")
    }

    @Test func heroLinesAreSetTighterThanNatural() {
        for hero in DS.Cut.Typography.Hero.allCases {
            #expect(DS.Cut.Typography.heroLineGap(hero, scaledSize: hero.size) < 0)
        }
    }

    // MARK: Fractions

    @Test(arguments: [
        (-0.5, 0.0), (0.0, 0.0), (0.25, 0.25), (1.0, 1.0), (1.7, 1.0),
        (Double.nan, 0.0), (Double.infinity, 1.0), (-Double.infinity, 0.0)
    ])
    func fractionIsClamped(input: Double, expected: Double) {
        #expect(DS.Cut.clampedFraction(input) == expected)
    }

    @Test func vMarkProgressClampsBothArms() {
        let view = VMarkProgress(left: -1, right: 2, accessibilityLabel: "Weekly goal")
        #expect(view.fractions.left == 0)
        #expect(view.fractions.right == 1)
        let half = VMarkProgress(left: 0.5, right: 95.0 / 150.0, accessibilityLabel: "Weekly goal")
        #expect(half.fractions.left == 0.5)
        #expect(abs(half.fractions.right - 0.6333) < 0.001)
    }

    // MARK: Segments

    @Test func segmentStatesCountAndOrder() {
        let states = CutSegmentProgress.states(total: 6, filled: 2, current: 2)
        #expect(states == [.filled, .filled, .current, .empty, .empty, .empty])
    }

    @Test func segmentStatesClampOutOfRangeInput() {
        #expect(CutSegmentProgress.states(total: 4, filled: 9, current: nil) == Array(repeating: .filled, count: 4))
        #expect(CutSegmentProgress.states(total: 3, filled: -2, current: nil) == Array(repeating: .empty, count: 3))
        #expect(CutSegmentProgress.states(total: -1, filled: 1, current: 0).isEmpty)
        // A current index outside the row or on a filled segment is ignored.
        #expect(CutSegmentProgress.states(total: 3, filled: 1, current: 7) == [.filled, .empty, .empty])
        #expect(CutSegmentProgress.states(total: 3, filled: 2, current: 0) == [.filled, .filled, .empty])
    }

    // MARK: Shapes

    static let rects: [CGRect] = [
        CGRect(x: 0, y: 0, width: 393, height: 430),
        CGRect(x: 10, y: 20, width: 60, height: 60),
        CGRect(x: 0, y: 0, width: 300, height: 10),
        CGRect(x: 0, y: 0, width: 50, height: 168),
        CGRect(x: 0, y: 0, width: 4, height: 4)
    ]

    private func expectInside(_ path: Path, _ rect: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
        guard !path.isEmpty else { return }
        let bounds = path.boundingRect
        let tolerance: CGFloat = 0.001
        #expect(bounds.minX >= rect.minX - tolerance, sourceLocation: sourceLocation)
        #expect(bounds.minY >= rect.minY - tolerance, sourceLocation: sourceLocation)
        #expect(bounds.maxX <= rect.maxX + tolerance, sourceLocation: sourceLocation)
        #expect(bounds.maxY <= rect.maxY + tolerance, sourceLocation: sourceLocation)
    }

    @Test(arguments: rects)
    func cornerShapeStaysInside(rect: CGRect) {
        for corner in DS.Cut.Corner.allCases {
            for cut in [DS.Cut.CutSize.points(112), .points(0), .fraction(0.38), .fraction(2)] {
                let shape = CutCornerShape(corner: corner, cut: cut)
                expectInside(shape.path(in: rect), rect)
                expectInside(shape.inset(by: 1).path(in: rect), rect.insetBy(dx: 1, dy: 1))
            }
        }
    }

    @Test(arguments: rects)
    func slantedSegmentStaysInside(rect: CGRect) {
        expectInside(SlantedSegmentShape().path(in: rect), rect)
        expectInside(SlantedSegmentShape(slant: 30).path(in: rect), rect)
        expectInside(SlantedSegmentShape().inset(by: 1).path(in: rect), rect.insetBy(dx: 1, dy: 1))
    }

    @Test(arguments: rects)
    func vMarkStaysInside(rect: CGRect) {
        for arm in VMarkShape.Arm.allCases {
            expectInside(VMarkShape(arm: arm).path(in: rect), rect)
        }
        for fraction in [0.0, 0.3, 0.63, 1.0, 1.5] {
            expectInside(VMarkArmFillShape(arm: .left, fraction: fraction).path(in: rect), rect)
            expectInside(VMarkArmFillShape(arm: .right, fraction: fraction).path(in: rect), rect)
        }
    }

    @Test func fieldCutIsExactly45Degrees() {
        let rect = CGRect(x: 0, y: 0, width: 393, height: 430)
        let path = CutCornerShape.field.path(in: rect)
        // The diagonal runs from (393, 318) to (281, 430): equal legs.
        #expect(path.contains(CGPoint(x: 392, y: 317)))
        #expect(!path.contains(CGPoint(x: 392, y: 321)))
        #expect(path.contains(CGPoint(x: 337 - 1, y: 374 - 1)))
        #expect(!path.contains(CGPoint(x: 337 + 1, y: 374 + 1)))
    }

    @Test func slantedSegmentIsExactly45Degrees() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 10)
        let path = SlantedSegmentShape().path(in: rect)
        // Leading edge from (10, 0) to (0, 10); trailing edge from (100, 0) to (90, 10).
        #expect(path.contains(CGPoint(x: 5.5, y: 5)))
        #expect(!path.contains(CGPoint(x: 4.5, y: 5)))
        #expect(path.contains(CGPoint(x: 94.5, y: 5)))
        #expect(!path.contains(CGPoint(x: 95.5, y: 5)))
    }

    @Test func vMarkKeepsLogoProportions() {
        #expect(abs(VMarkShape.aspectRatio - 758.0 / 457.0) < 0.0001)
        let rect = CGRect(x: 0, y: 0, width: 758, height: 457)
        let bounds = VMarkShape().path(in: rect).boundingRect
        #expect(abs(bounds.width - 758) < 0.01)
        #expect(abs(bounds.height - 457) < 0.01)
        // Half-filled left arm covers the lower half of the arm's 452 pt height.
        let fill = VMarkArmFillShape(arm: .left, fraction: 0.5).path(in: rect).boundingRect
        #expect(abs(fill.height - 226) < 0.5)
        #expect(abs(fill.maxY - 457) < 0.5)
    }

    // MARK: Contrast

    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test func limeAndInkContrastPassAA() {
        #expect(contrast(DS.Cut.Colors.lime, DS.Cut.Colors.background) >= 7)
        #expect(contrast(DS.Cut.Colors.ink, DS.Cut.Colors.lime) >= 7)
        #expect(contrast(DS.Cut.Colors.textSecondary, DS.Cut.Colors.background) >= 4.5)
        // Secondary ink is ink at 74 percent over lime.
        let blended = Color(red: 0.8 * 0.26 + 11.0 / 255 * 0.74, green: 0.26 + 13.0 / 255 * 0.74, blue: 0)
        #expect(contrast(blended, DS.Cut.Colors.lime) >= 4.5)
    }
}
