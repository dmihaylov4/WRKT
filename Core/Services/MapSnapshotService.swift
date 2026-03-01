//
//  MapSnapshotService.swift
//  WRKT
//
//  Generates static map snapshots with route overlays for social sharing
//

import SwiftUI
import MapKit
import UIKit

/// Service to generate static map snapshot images with route overlays
@MainActor
final class MapSnapshotService {
    static let shared = MapSnapshotService()

    private init() {}

    /// Generate a map snapshot with route and optional HR-colored overlay
    /// - Parameters:
    ///   - coordinates: Array of route coordinates
    ///   - hrValues: Optional heart rate values per coordinate (for color gradient)
    ///   - size: Output image size (default 600x400)
    /// - Returns: UIImage of the map snapshot with route overlay
    func generateRouteSnapshot(
        coordinates: [CLLocationCoordinate2D],
        hrValues: [Double]? = nil,
        size: CGSize = CGSize(width: 600, height: 400)
    ) async throws -> UIImage {
        guard coordinates.count > 1 else {
            throw MapSnapshotError.insufficientCoordinates
        }

        // Create polyline to calculate bounds
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        let mapRect = polyline.boundingMapRect

        // Add padding — 30% on each axis so the route never touches the edges.
        // Then equalise the axes so the route is centred in the 600×400 frame
        // without being stretched: pad the short axis to match the long one.
        let paddedW = mapRect.size.width  * 1.60   // 30% each side → ×1.6 total
        let paddedH = mapRect.size.height * 1.60
        let aspectTarget = size.width / size.height  // e.g. 1.5 for 600×400
        let rectAspect   = paddedW / paddedH

        let finalW: Double
        let finalH: Double
        if rectAspect > aspectTarget {
            // Route is wider than the output frame — expand height to match
            finalW = paddedW
            finalH = paddedW / aspectTarget
        } else {
            // Route is taller — expand width to match
            finalH = paddedH
            finalW = paddedH * aspectTarget
        }

        let paddedRect = MKMapRect(
            x: mapRect.midX - finalW / 2,
            y: mapRect.midY - finalH / 2,
            width: finalW,
            height: finalH
        )

        // Configure snapshot options
        let options = MKMapSnapshotter.Options()
        options.mapRect = paddedRect
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        // Take snapshot
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await snapshotter.start()

        // Draw route on snapshot
        let image = drawRoute(
            on: snapshot,
            coordinates: coordinates,
            hrValues: hrValues,
            size: size
        )

        return image
    }

    /// Draw route polyline on snapshot image
    private func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        coordinates: [CLLocationCoordinate2D],
        hrValues: [Double]?,
        size: CGSize
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Draw the map snapshot
            snapshot.image.draw(at: .zero)

            let cgContext = context.cgContext
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)

            // Convert coordinates to points
            let points = coordinates.map { snapshot.point(for: $0) }

            // Check if we have valid HR data for gradient coloring
            let validHR = hrValues?.filter { !$0.isNaN }
            let hasValidHR = validHR != nil && (validHR?.count ?? 0) > 1

            if hasValidHR, let hr = hrValues,
               let minHR = validHR?.min(),
               let maxHR = validHR?.max(),
               maxHR > minHR {
                // Draw HR-colored segments
                drawGradientRoute(
                    context: cgContext,
                    points: points,
                    hrValues: hr,
                    minHR: minHR,
                    maxHR: maxHR
                )
            } else {
                // Draw solid color route
                drawSolidRoute(context: cgContext, points: points)
            }

            // Draw start/end markers
            drawMarkers(context: cgContext, points: points)
        }
    }

    /// Draw route with HR-based color gradient
    private func drawGradientRoute(
        context: CGContext,
        points: [CGPoint],
        hrValues: [Double],
        minHR: Double,
        maxHR: Double
    ) {
        context.setLineWidth(4.0)

        for i in 0..<(points.count - 1) {
            let startPoint = points[i]
            let endPoint = points[i + 1]

            // Get HR value (or use midpoint if NaN)
            var hrValue = hrValues[i]
            if hrValue.isNaN {
                hrValue = (minHR + maxHR) / 2
            }

            // Calculate color based on HR
            let color = colorForHeartRate(hrValue, min: minHR, max: maxHR)

            context.setStrokeColor(color.cgColor)
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
        }
    }

    /// Draw solid color route
    private func drawSolidRoute(context: CGContext, points: [CGPoint]) {
        // Use app accent color
        let accentColor = UIColor(Color(hex: "#CCFF00"))

        context.setStrokeColor(accentColor.cgColor)
        context.setLineWidth(4.0)

        context.move(to: points[0])
        for i in 1..<points.count {
            context.addLine(to: points[i])
        }
        context.strokePath()
    }

    /// Draw start and end markers
    private func drawMarkers(context: CGContext, points: [CGPoint]) {
        guard let first = points.first, let last = points.last else { return }

        // Start marker (green)
        context.setFillColor(UIColor.systemGreen.cgColor)
        context.fillEllipse(in: CGRect(x: first.x - 6, y: first.y - 6, width: 12, height: 12))
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6))

        // End marker (red)
        context.setFillColor(UIColor.systemRed.cgColor)
        context.fillEllipse(in: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12))
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
    }

    /// Calculate color for heart rate value (blue -> green/yellow -> red)
    private func colorForHeartRate(_ hr: Double, min: Double, max: Double) -> UIColor {
        let t = CGFloat((hr - min) / (max - min))

        if t < 0.5 {
            // Blue to Green/Yellow (accent)
            let k = t / 0.5
            return UIColor.systemBlue.interpolate(to: UIColor(Color(hex: "#CCFF00")), alpha: k)
        } else {
            // Green/Yellow (accent) to Red
            let k = (t - 0.5) / 0.5
            return UIColor(Color(hex: "#CCFF00")).interpolate(to: UIColor.systemRed, alpha: k)
        }
    }
}

// MARK: - Errors

enum MapSnapshotError: LocalizedError {
    case insufficientCoordinates
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .insufficientCoordinates:
            return "Not enough coordinates to generate map"
        case .snapshotFailed:
            return "Failed to generate map snapshot"
        }
    }
}

// MARK: - UIColor Extension

private extension UIColor {
    /// Interpolate between two colors
    func interpolate(to color: UIColor, alpha: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let r = r1 + (r2 - r1) * alpha
        let g = g1 + (g2 - g1) * alpha
        let b = b1 + (b2 - b1) * alpha
        let a = a1 + (a2 - a1) * alpha

        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
