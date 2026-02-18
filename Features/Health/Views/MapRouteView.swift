//
//  MapRouteView 2.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//


import SwiftUI
import MapKit

/// Reusable route map. Defaults to non-interactive (ideal for list rows).
struct MapRouteView: UIViewRepresentable {
    let coords: [Coordinate]
    var interactive: Bool = false
    var lineWidth: CGFloat = 3

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = interactive
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Clear old overlays/annotations
        if !map.overlays.isEmpty { map.removeOverlays(map.overlays) }

        let points = coords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard points.count > 1 else { return }

        let polyline = MKPolyline(coordinates: points, count: points.count)
        map.addOverlay(polyline)

        // Fit the route with padding
        let rect = polyline.boundingMapRect
        let inset: Double = 1000 // map points (~meters); tweak if needed
        let padded = rect.insetBy(dx: -inset, dy: -inset)
        map.setVisibleMapRect(padded,
                              edgePadding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                              animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.lineWidth = 3
            r.strokeColor = .systemBlue
            return r
        }
    }
}
