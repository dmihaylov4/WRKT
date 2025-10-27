//
//  MapRouteView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import SwiftUI
import MapKit

struct InteractiveRouteMap: UIViewRepresentable {
    let coords: [Coordinate]

    func makeCoordinator() -> Coord {
        Coord()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let points = coords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard points.count > 1 else { return }

        let poly = MKPolyline(coordinates: points, count: points.count)
        map.addOverlay(poly)

        // fit region
        let rect = poly.boundingMapRect
        map.setVisibleMapRect(rect,
                              edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                              animated: false)
    }

    final class Coord: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.lineWidth = 3
            r.strokeColor = .systemBlue
            return r
        }
    }
}
