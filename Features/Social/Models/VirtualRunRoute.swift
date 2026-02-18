//
//  VirtualRunRoute.swift
//  WRKT
//
//  Route data model for virtual run map comparison.
//  Includes Douglas-Peucker simplification to keep uploaded JSON compact.
//

import Foundation
import CoreLocation

// MARK: - Route Data (uploaded to Supabase Storage)

struct VirtualRunRouteData: Codable, Sendable {
    let userId: String
    let runId: String
    let points: [CompactRoutePoint]
    let uploadedAt: Date

    struct CompactRoutePoint: Codable, Sendable {
        let lat: Double
        let lon: Double
        let t: TimeInterval  // seconds since run start
        let hr: Int?
    }
}

// MARK: - Conversion from RoutePoint

extension VirtualRunRouteData {
    /// Create from HealthKit route points, downsampled to maxPoints
    static func from(
        routePoints: [RoutePoint],
        userId: UUID,
        runId: UUID,
        runStartDate: Date
    ) -> VirtualRunRouteData {
        let simplified = simplify(routePoints, maxPoints: 500)

        let compactPoints = simplified.map { point in
            CompactRoutePoint(
                lat: point.lat,
                lon: point.lon,
                t: point.t.timeIntervalSince(runStartDate),
                hr: point.hr.map { Int($0) }
            )
        }

        return VirtualRunRouteData(
            userId: userId.uuidString,
            runId: runId.uuidString,
            points: compactPoints,
            uploadedAt: Date()
        )
    }

    /// Extract CLLocationCoordinate2D array for map rendering
    var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Extract heart rate values (NaN for missing) for gradient coloring
    var heartRates: [Double] {
        points.map { $0.hr.map { Double($0) } ?? .nan }
    }
}

// MARK: - Douglas-Peucker Simplification

extension VirtualRunRouteData {
    /// Downsample route points using Douglas-Peucker algorithm
    /// Keeps visual shape intact while reducing point count
    static func simplify(_ points: [RoutePoint], maxPoints: Int = 500) -> [RoutePoint] {
        guard points.count > maxPoints else { return points }

        // Binary search for the right epsilon that yields ~maxPoints
        var lo: Double = 0
        var hi: Double = 0.001 // ~111m in degrees
        var result = points

        // Find upper bound
        while douglasPeucker(points, epsilon: hi).count > maxPoints {
            hi *= 2
        }

        // Binary search for optimal epsilon
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            let simplified = douglasPeucker(points, epsilon: mid)
            if simplified.count > maxPoints {
                lo = mid
            } else {
                hi = mid
                result = simplified
            }
        }

        return result
    }

    private static func douglasPeucker(_ points: [RoutePoint], epsilon: Double) -> [RoutePoint] {
        guard points.count > 2 else { return points }

        // Find the point with maximum distance from the line between first and last
        var maxDist: Double = 0
        var maxIndex = 0

        let start = CLLocationCoordinate2D(latitude: points.first!.lat, longitude: points.first!.lon)
        let end = CLLocationCoordinate2D(latitude: points.last!.lat, longitude: points.last!.lon)

        for i in 1..<(points.count - 1) {
            let point = CLLocationCoordinate2D(latitude: points[i].lat, longitude: points[i].lon)
            let dist = perpendicularDistance(point: point, lineStart: start, lineEnd: end)
            if dist > maxDist {
                maxDist = dist
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = douglasPeucker(Array(points[...maxIndex]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[maxIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [points.first!, points.last!]
        }
    }

    /// Perpendicular distance from a point to a line (in degrees, approximate)
    private static func perpendicularDistance(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude

        if dx == 0 && dy == 0 {
            // Line start and end are the same point
            let pdx = point.longitude - lineStart.longitude
            let pdy = point.latitude - lineStart.latitude
            return sqrt(pdx * pdx + pdy * pdy)
        }

        let t = ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)
        let clampedT = max(0, min(1, t))

        let nearestX = lineStart.longitude + clampedT * dx
        let nearestY = lineStart.latitude + clampedT * dy

        let distX = point.longitude - nearestX
        let distY = point.latitude - nearestY

        return sqrt(distX * distX + distY * distY)
    }
}
