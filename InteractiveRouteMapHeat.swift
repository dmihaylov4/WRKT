//
//  InteractiveRouteMapHeat.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 08.10.25.
//


// InteractiveRouteMapHeat.swift
import SwiftUI
import MapKit
import UIKit


private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}

struct InteractiveRouteMapHeat: UIViewRepresentable {
    // Either raw coords (+ optional HR aligned 1:1)...
    private let coords: [CLLocationCoordinate2D]
    private let hrPerPoint: [Double]?
    // ...or typed points with timestamps & HR
    private let points: [RoutePoint]?

    init(coords: [Coordinate], hrPerPoint: [Double]?) {
        self.coords = coords.map { .init(latitude: $0.lat, longitude: $0.lon) }
        self.hrPerPoint = hrPerPoint
        self.points = nil
    }

    init(points: [RoutePoint]) {
        self.points = points
        self.coords = points.map { .init(latitude: $0.lat, longitude: $0.lon) }
        self.hrPerPoint = points.map { $0.hr ?? .nan }
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.overrideUserInterfaceStyle = .dark
        render(on: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        render(on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Render
    private func render(on map: MKMapView) {
        guard coords.count > 1 else { return }

        // Fit route
        let poly = MKPolyline(coordinates: coords, count: coords.count)
        map.setVisibleMapRect(poly.boundingMapRect, edgePadding: .init(top: 40, left: 30, bottom: 40, right: 30), animated: false)

        // If we have HR per point (even partial), draw colored segments. Else draw single accent line.
        if let hr = hrPerPoint, hr.count == coords.count, hr.contains(where: { !$0.isNaN }) {
            let clean = zip(coords, hr).filter { !$0.1.isNaN }
            guard clean.count > 1 else {
                map.addOverlay(poly) // fallback
                return
            }
            let values = clean.map { $0.1 }
            guard let minV = values.min(), let maxV = values.max(), maxV > minV else {
                map.addOverlay(poly) // flat color
                return
            }

            // Reduce overlay count (performance): segment every ~10–20 points
            let strideBy = max(1, clean.count / 200) // cap around ~200 segments
            var segCoords: [CLLocationCoordinate2D] = []
            var segColors: [UIColor] = []

            // inside color(for:)
            func color(for x: Double) -> UIColor {
                let t = CGFloat((x - minV) / (maxV - minV))
                if t < 0.5 {
                    let k = t / 0.5
                    let c1 = UIColor.systemBlue
                    let c2 = UIColor.fromColor(Theme.accent)   // ← use helper, not UIColor(Theme.accent)
                    return c1.interpolate(to: c2, alpha: k)
                } else {
                    let k = (t - 0.5) / 0.5
                    let c1 = UIColor.fromColor(Theme.accent)   // ← use helper
                    let c2 = UIColor.systemRed
                    return c1.interpolate(to: c2, alpha: k)
                }
            }

            let cleanedCoords = clean.map { $0.0 }
            let cleanedHR = clean.map { $0.1 }

            for i in stride(from: 0, to: cleanedCoords.count - 1, by: strideBy) {
                let a = cleanedCoords[i]
                let b = cleanedCoords[min(i + strideBy, cleanedCoords.count - 1)]
                let midHR = cleanedHR[min(i + strideBy/2, cleanedHR.count - 1)]
                segCoords.append(contentsOf: [a, b])
                segColors.append(color(for: midHR))
            }

            // add colored segments
            for i in stride(from: 0, to: segCoords.count - 1, by: 2) {
                let pl = MKPolyline(coordinates: [segCoords[i], segCoords[i+1]], count: 2)
                // Store color in title → looked up in renderer
                pl.title = segColors[i/2].toRGBAString()
                map.addOverlay(pl)
            }
        } else {
            // Single accent line
            map.addOverlay(poly)
        }
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: polyline)
            // in Coordinator.rendererFor overlay:
            if let rgba = polyline.title, let c = UIColor.fromRGBAString(rgba) {
                r.strokeColor = c                           // ← use the decoded per-segment color
            } else {
                r.strokeColor = UIColor.fromColor(Theme.accent)  // ← fallback single-color route
            }
            r.lineWidth = 6
            r.lineJoin = .round
            r.lineCap  = .round
            return r
        }
    }
}

// MARK: - Helpers (UIKit color glue)

   // ensure UIKit is available for UIColor extensions

private extension UIColor {
    /// Safe bridge from SwiftUI `Color` to `UIColor` (avoids your previous recursive init).
    static func fromColor(_ swiftUIColor: Color) -> UIColor {
        UIColor(swiftUIColor)
    }

    /// Linear interpolation between two UIColors.
    func interpolate(to: UIColor, alpha tRaw: CGFloat) -> UIColor {
        let t = max(0, min(1, tRaw))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red:   r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue:  b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }

    /// Serialize to "r,g,b,a" (0...1) string so we can stash it in MKPolyline.title.
    func toRGBAString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(r),\(g),\(b),\(a)"
    }

    /// Parse "r,g,b,a" back into a UIColor.
    static func fromRGBAString(_ s: String) -> UIColor? {
        let parts = s.split(separator: ",")
        guard parts.count == 4,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]),
              let a = Double(parts[3]) else { return nil }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
