//
//  LocationManager.swift
//  WRKT
//
//  Created by Claude Code on 09.11.25.
//

import CoreLocation
import MapKit
import SwiftUI
import Combine
@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var locationPermissionGranted = false
    @Published var currentLocation: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        self.manager.delegate = self
        checkLocationPermission()
    }

    func checkLocationPermission() {
        let status = manager.authorizationStatus
        locationPermissionGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)

        if status == .notDetermined {
            AppLogger.info("Requesting location permission", category: AppLogger.health)
            manager.requestWhenInUseAuthorization()
        } else if status == .denied {
            AppLogger.warning("Location permission denied", category: AppLogger.health)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.locationPermissionGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)
            AppLogger.debug("Location authorization changed: \(status.rawValue)", category: AppLogger.health)
        }
    }
}
