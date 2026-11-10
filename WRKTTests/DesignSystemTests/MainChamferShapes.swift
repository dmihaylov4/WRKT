// Frozen shape implementations from main at 512e016.
import SwiftUI
@testable import WRKT

public struct MainChamferedRectangle: Shape {
    /// Size of the diagonal chamfer cut
    public var chamferSize: CGFloat

    /// Initialize with a design token (recommended)
    public init(_ chamfer: DS.Chamfer = .large) {
        self.chamferSize = chamfer.size
    }

    /// Initialize with explicit size (for edge cases)
    public init(chamferSize: CGFloat) {
        self.chamferSize = chamferSize
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left (square corner)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top edge to chamfer start
        path.addLine(to: CGPoint(x: rect.maxX - chamferSize, y: rect.minY))

        // Top-right chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + chamferSize))

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Bottom-right (square corner)
        // Already at bottom-right from previous line

        // Bottom edge to chamfer start
        path.addLine(to: CGPoint(x: rect.minX + chamferSize, y: rect.maxY))

        // Bottom-left chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - chamferSize))

        // Left edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()

        return path
    }
}

/// Alternate chamfered rectangle with chamfers on top-left and bottom-right,
/// and square corners on top-right and bottom-left - opposite of MainChamferedRectangle.
public struct MainChamferedRectangleAlt: Shape {
    /// Size of the diagonal chamfer cut
    public var chamferSize: CGFloat

    /// Initialize with a design token (recommended)
    public init(_ chamfer: DS.Chamfer = .large) {
        self.chamferSize = chamfer.size
    }

    /// Initialize with explicit size (for edge cases)
    public init(chamferSize: CGFloat) {
        self.chamferSize = chamferSize
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left chamfer start point
        path.move(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        // Top edge (top-right is square)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right edge to chamfer start
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - chamferSize))

        // Bottom-right chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.maxX - chamferSize, y: rect.maxY))

        // Bottom edge (bottom-left is square)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        // Left edge to chamfer start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamferSize))

        // Top-left chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        path.closeSubpath()

        return path
    }
}

/// Rectangle with only the top-left corner chamfered, and all other corners rounded.
/// Useful for small cells like calendar day cells where full chamfering would be too much.
public struct MainTopLeftChamferedRectangle: Shape {
    public var chamferSize: CGFloat
    public var cornerRadius: CGFloat

    /// Initialize with a design token (recommended)
    public init(_ chamfer: DS.Chamfer = .small, cornerRadius: CGFloat = 10) {
        self.chamferSize = chamfer.size
        self.cornerRadius = cornerRadius
    }

    /// Initialize with explicit size (for edge cases)
    public init(chamferSize: CGFloat, cornerRadius: CGFloat = 10) {
        self.chamferSize = chamferSize
        self.cornerRadius = cornerRadius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start after top-left chamfer
        path.move(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        // Top edge to top-right rounded corner
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        // Right edge to bottom-right rounded corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        // Bottom edge to bottom-left rounded corner
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Left edge to top-left chamfer
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamferSize))

        // Top-left chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        path.closeSubpath()

        return path
    }
}

// MARK: - Single-corner chamfered rectangle

/// Rectangle with exactly one chamfered corner and three square corners.
/// Use with `DS.GridChamferPosition` to automatically orient the cut toward the center of a grid group.
public struct MainSingleChamferedRectangle: Shape {
    public enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    public var corner: Corner
    public var chamferSize: CGFloat

    public init(corner: Corner, _ chamfer: DS.Chamfer = .large) {
        self.corner = corner
        self.chamferSize = chamfer.size
    }

    public init(corner: Corner, chamferSize: CGFloat) {
        self.corner = corner
        self.chamferSize = chamferSize
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = chamferSize

        switch corner {
        case .topLeading:
            path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
            path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))

        case .topTrailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        case .bottomLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        case .bottomTrailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Paired-corner chamfered rectangle

/// Rectangle with two diagonal chamfers. Use for paired action tiles where each tile
/// needs one outer cut plus one inward cut toward its sibling.
public struct MainPairedChamferedRectangle: Shape {
    public enum Pair {
        case leadingTile, trailingTile
    }

    public var pair: Pair
    public var chamferSize: CGFloat

    public init(pair: Pair, _ chamfer: DS.Chamfer = .large) {
        self.pair = pair
        self.chamferSize = chamfer.size
    }

    public init(pair: Pair, chamferSize: CGFloat) {
        self.pair = pair
        self.chamferSize = chamferSize
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = chamferSize

        switch pair {
        case .leadingTile:
            path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
            path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))

        case .trailingTile:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}
