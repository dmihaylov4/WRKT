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

    // MARK: - Virtual Run Background Session

    /// Activates background location updates for the duration of a virtual run.
    /// Uses 3km accuracy (cell-tower/WiFi only — negligible battery) solely to keep
    /// iOS from suspending the app while the screen is locked, so the Supabase WebSocket
    /// and WCSession relay remain active throughout the run.
    func startVirtualRunBackgroundSession() {
        guard locationPermissionGranted else {
            AppLogger.warning("[VirtualRun] Location permission not granted — background session unavailable", category: AppLogger.health)
            return
        }
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        AppLogger.info("[VirtualRun] Background location session started (3km accuracy)", category: AppLogger.health)
    }

    func stopVirtualRunBackgroundSession() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        AppLogger.info("[VirtualRun] Background location session stopped", category: AppLogger.health)
    }
}
