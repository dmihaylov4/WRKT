//
//  CutShapes.swift
//  WRKT
//
//  The Cut geometry: every diagonal is 45 degrees, taken from the V mark.
//  These shapes do not follow DS.Redesign.roundedShapesEnabled; the cut is the point.
//

import SwiftUI

// MARK: - Cut corner

public extension DS.Cut {
    enum Corner: CaseIterable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    /// How deep a corner cut goes along each edge.
    enum CutSize: Equatable, Sendable {
        /// A fixed length in points.
        case points(CGFloat)
        /// A fraction of the shape's shorter side.
        case fraction(CGFloat)

        func resolved(in rect: CGRect) -> CGFloat {
            let limit = max(0, min(rect.width, rect.height))
            switch self {
            case .points(let value): return min(max(0, value), limit)
            case .fraction(let value): return min(max(0, value), 1) * limit
            }
        }
    }
}

/// A rectangle with one corner cut at 45 degrees.
/// Used for the lime field (large cut), the action bar (top leading cut) and tiles (fractional cut).
public struct CutCornerShape: InsettableShape {
    public var corner: DS.Cut.Corner
    public var cut: DS.Cut.CutSize
    private var insetAmount: CGFloat = 0

    public init(corner: DS.Cut.Corner = .bottomTrailing, cut: DS.Cut.CutSize = .points(DS.Cut.Metrics.fieldCut)) {
        self.corner = corner
        self.cut = cut
    }

    /// The lime field: bottom trailing cut of 112 pt.
    public static var field: CutCornerShape { CutCornerShape() }

    /// The action bar: top leading cut of 72 pt.
    public static var actionBar: CutCornerShape {
        CutCornerShape(corner: .topLeading, cut: .points(DS.Cut.Metrics.actionBarCut))
    }

    /// A small tile: bottom trailing cut of 38 percent of its side.
    public static var tile: CutCornerShape {
        CutCornerShape(corner: .bottomTrailing, cut: .fraction(DS.Cut.Metrics.tileCutFraction))
    }

    public func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        // Insetting a 45 degree edge by d moves it d * sqrt(2) along the diagonal,
        // which shortens the cut along each edge by d * (2 - sqrt(2)).
        let base = cut.resolved(in: rect)
        let c = min(max(0, base - insetAmount * (2 - 2.squareRoot())), bounds.width, bounds.height)
        let (minX, minY, maxX, maxY) = (bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)

        let points: [CGPoint]
        switch corner {
        case .topLeading:
            points = [CGPoint(x: minX + c, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY),
                      CGPoint(x: minX, y: maxY), CGPoint(x: minX, y: minY + c)]
        case .topTrailing:
            points = [CGPoint(x: minX, y: minY), CGPoint(x: maxX - c, y: minY), CGPoint(x: maxX, y: minY + c),
                      CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
        case .bottomLeading:
            points = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY),
                      CGPoint(x: minX + c, y: maxY), CGPoint(x: minX, y: maxY - c)]
        case .bottomTrailing:
            points = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY - c),
                      CGPoint(x: maxX - c, y: maxY), CGPoint(x: minX, y: maxY)]
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    public func inset(by amount: CGFloat) -> CutCornerShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

// MARK: - Slanted segment

/// A parallelogram leaning at the mark's angle: top edge shifted right by the slant.
/// With the default slant (equal to the height) both sides are exactly 45 degrees.
public struct SlantedSegmentShape: InsettableShape {
    /// Horizontal offset of the top edge. `nil` means equal to the height (45 degrees).
    public var slant: CGFloat?
    private var insetAmount: CGFloat = 0

    public init(slant: CGFloat? = nil) {
        self.slant = slant
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let h = rect.height
        let s = min(max(0, slant ?? h), rect.width)
        let d = insetAmount
        guard h - 2 * d > 0 else { return Path() }
        // Each slanted edge moves inward by d, which is a horizontal shift of d * hypot(s, h) / h.
        let shift = s == 0 ? d : d * (s * s + h * h).squareRoot() / h
        let top = rect.minY + d
        let bottom = rect.maxY - d
        // x on the leading edge at height y: minX + s * (1 - (y - minY) / h)
        func leading(_ y: CGFloat) -> CGFloat { rect.minX + s * (1 - (y - rect.minY) / h) + shift }
        func trailing(_ y: CGFloat) -> CGFloat { rect.maxX - s * ((y - rect.minY) / h) - shift }
        guard trailing(top) > leading(top), trailing(bottom) > leading(bottom) else { return Path() }

        var path = Path()
        path.addLines([
            CGPoint(x: leading(top), y: top),
            CGPoint(x: trailing(top), y: top),
            CGPoint(x: trailing(bottom), y: bottom),
            CGPoint(x: leading(bottom), y: bottom)
        ])
        path.closeSubpath()
        return path
    }

    public func inset(by amount: CGFloat) -> SlantedSegmentShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

// MARK: - V mark

/// The VOLIA mark: two chamfered arms, from the logo polygons in viewBox `132 285 758 457`.
/// The mark is fitted into the rect keeping its proportions, centred.
public struct VMarkShape: Shape {
    public enum Arm: CaseIterable, Sendable {
        case left, right, both
    }

    /// Width over height of the mark.
    public static let aspectRatio: CGFloat = viewBox.width / viewBox.height

    static let viewBox = CGRect(x: 132, y: 285, width: 758, height: 457)
    static let leftArm: [CGPoint] = [
        CGPoint(x: 132, y: 290), CGPoint(x: 290, y: 290), CGPoint(x: 582, y: 582),
        CGPoint(x: 582, y: 742), CGPoint(x: 438, y: 742), CGPoint(x: 132, y: 438)
    ]
    static let rightArm: [CGPoint] = [
        CGPoint(x: 735, y: 285), CGPoint(x: 890, y: 285), CGPoint(x: 890, y: 437),
        CGPoint(x: 735, y: 592), CGPoint(x: 582, y: 592), CGPoint(x: 582, y: 437)
    ]

    public var arm: Arm

    public init(arm: Arm = .both) {
        self.arm = arm
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        if arm != .right { path.addPath(Self.armPath(Self.leftArm, in: rect)) }
        if arm != .left { path.addPath(Self.armPath(Self.rightArm, in: rect)) }
        return path
    }

    /// Maps a point from the logo's viewBox into `rect`.
    static func transform(for rect: CGRect) -> CGAffineTransform {
        guard rect.width > 0, rect.height > 0 else { return .identity }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * scale) / 2
        let dy = rect.minY + (rect.height - viewBox.height * scale) / 2
        return CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
    }

    static func armPath(_ points: [CGPoint], in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path.applying(transform(for: rect))
    }
}

/// One arm of the V mark filled from the bottom up to `fraction` of the arm's height.
/// Animatable: the fill rises when the fraction changes.
public struct VMarkArmFillShape: Shape {
    public enum Arm: Sendable { case left, right }

    public var arm: Arm
    public var fraction: Double

    public init(arm: Arm, fraction: Double) {
        self.arm = arm
        self.fraction = fraction
    }

    public var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let f = DS.Cut.clampedFraction(fraction)
        guard f > 0, rect.width > 0, rect.height > 0 else { return Path() }
        let points = arm == .left ? VMarkShape.leftArm : VMarkShape.rightArm
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let fillHeight = (maxY - minY) * f
        let clip = Path(CGRect(x: minX, y: maxY - fillHeight, width: maxX - minX, height: fillHeight))
            .applying(VMarkShape.transform(for: rect))
        let armPath = VMarkShape.armPath(points, in: rect)
        if f >= 1 { return armPath }
        return armPath.intersection(clip)
    }
}

public extension DS.Cut {
    /// Clamps a progress value to 0...1; NaN and negative values become 0.
    static func clampedFraction(_ value: Double) -> Double {
        guard value.isFinite else { return value == .infinity ? 1 : 0 }
        return min(max(value, 0), 1)
    }
}
