//
//  WatchHealthKitManager.swift
//  WRKT Watch
//
//  Manages HKWorkoutSession for tracking workout metrics on Apple Watch
//  Auto-starts when iPhone begins a workout, auto-ends when workout finishes
//

import Foundation
import HealthKit
import CoreLocation
import OSLog

@Observable
@MainActor
final class WatchHealthKitManager: NSObject {
    static let shared = WatchHealthKitManager()

    // MARK: - Published State
    var isWorkoutActive = false
    var elapsedTime: TimeInterval = 0
    var activeCalories: Double = 0
    var heartRate: Double = 0
    var distance: Double = 0  // meters

    // MARK: - GPS / Route
    private(set) var lastLocation: CLLocation?
    private var locationManager: CLLocationManager?
    private var routeBuilder: HKWorkoutRouteBuilder?

    // MARK: - Private Properties
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var elapsedTimer: Timer?

    private let logger = Logger(subsystem: "com.wrkt.watch", category: "healthkit")

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Request HealthKit authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit not available on this device")
            return
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        logger.info("HealthKit authorization granted")
    }

    /// Start a workout session
    func startWorkout() async throws {
        try await startWorkout(activityType: .traditionalStrengthTraining, locationType: .indoor)
    }

    /// Start a running workout session (for virtual runs)
    func startRunningWorkout() async throws {
        try await startWorkout(activityType: .running, locationType: .outdoor)
    }

    /// Start a workout session with specified activity type
    private func startWorkout(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) async throws {
        guard !isWorkoutActive else {
            logger.warning("Workout already active, ignoring start request")
            return
        }

        // Request authorization if needed
        try await requestAuthorization()

        // Configure workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType

        do {
            // Create session
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            guard let session = session, let builder = builder else {
                throw WorkoutError.failedToCreateSession
            }

            // Set delegates
            session.delegate = self
            builder.delegate = self

            // Set data source
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            // Start session and builder
            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            self.startDate = startDate
            isWorkoutActive = true
            elapsedTime = 0
            activeCalories = 0
            heartRate = 0
            distance = 0

            // Start GPS location tracking for outdoor workouts
            if locationType == .outdoor {
                startLocationUpdates()
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
            }

            // Start elapsed time timer
            startElapsedTimer()

            logger.info("✅ Workout session started - isWorkoutActive: \(self.isWorkoutActive), startDate: \(startDate)")
            VirtualRunFileLogger.shared.log(category: .healthkit, message: "Workout started", data: [
                "activityType": configuration.activityType.rawValue,
                "locationType": configuration.locationType.rawValue
            ])

        } catch {
            logger.error("Failed to start workout: \(error.localizedDescription)")
            throw error
        }
    }

    /// End the workout session
    /// - Parameter discard: If true, discards the workout without saving to HealthKit
    func endWorkout(discard: Bool = false) async throws {
        guard isWorkoutActive, let session = session, let builder = builder else {
            logger.warning("No active workout to end (already ended or not started)")
            return
        }

        // Mark as inactive immediately to prevent duplicate calls
        isWorkoutActive = false

        // Stop elapsed timer
        stopElapsedTimer()

        // Check session state before ending
        guard session.state != .ended else {
            logger.info("Session already ended, just cleaning up")
            resetState()
            return
        }

        // End session
        session.end()

        if discard {
            // Discard the workout - don't save to HealthKit
            do {
                try await builder.discardWorkout()
                logger.info("🗑️ Workout discarded - not saved to HealthKit")
                VirtualRunFileLogger.shared.log(category: .healthkit, message: "Workout discarded")
            } catch {
                logger.error("Failed to discard workout: \(error.localizedDescription)")
            }
        } else {
            // Save the workout to HealthKit
            do {
                try await builder.endCollection(at: Date())
                let workout = try await builder.finishWorkout()

                // Attach GPS route if we recorded one
                if let routeBuilder = routeBuilder, let workout = workout {
                    do {
                        try await routeBuilder.finishRoute(with: workout, metadata: nil)
                        logger.info("✅ Route saved to workout")
                    } catch {
                        logger.error("Failed to save route: \(error.localizedDescription)")
                    }
                }

                logger.info("✅ Workout saved - Duration: \(self.elapsedTime)s, Calories: \(self.activeCalories)")
                VirtualRunFileLogger.shared.log(category: .healthkit, message: "Workout saved", data: [
                    "duration": Int(self.elapsedTime),
                    "calories": Int(self.activeCalories),
                    "distance": Int(self.distance)
                ])
            } catch {
                logger.error("Failed to save workout: \(error.localizedDescription)")
            }
        }

        resetState()
    }

    /// Pause the workout session
    func pauseWorkout() {
        guard isWorkoutActive, let session = session else { return }
        session.pause()
        stopElapsedTimer()
        logger.info("Workout paused")
    }

    /// Resume the workout session
    func resumeWorkout() {
        guard isWorkoutActive, let session = session else { return }
        session.resume()
        startElapsedTimer()
        logger.info("Workout resumed")
    }

    // MARK: - Private Methods

    private func resetState() {
        session = nil
        builder = nil
        startDate = nil
        isWorkoutActive = false
        elapsedTime = 0
        activeCalories = 0
        heartRate = 0
        distance = 0
        stopElapsedTimer()
        stopLocationUpdates()
    }

    // MARK: - Location

    private func startLocationUpdates() {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.delegate = self
        locationManager = manager

        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            logger.info("Started GPS location updates")
        } else {
            manager.requestWhenInUseAuthorization()
            logger.info("Requesting location authorization before starting updates")
        }
    }

    private func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
        routeBuilder = nil
        lastLocation = nil
    }

    private func startElapsedTimer() {
        stopElapsedTimer()

        // Create timer and add to main run loop explicitly
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startDate = self.startDate else { return }
                self.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer

        logger.info("Started elapsed timer")
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateMetrics(from statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            if let heartRateValue = statistics.mostRecentQuantity() {
                heartRate = heartRateValue.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                VirtualRunFileLogger.shared.log(category: .healthkit, message: "HR update", data: [
                    "bpm": Int(heartRate)
                ])
            }

        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            if let energyValue = statistics.sumQuantity() {
                activeCalories = energyValue.doubleValue(for: .kilocalorie())
            }

        case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
            if let distanceValue = statistics.sumQuantity() {
                distance = distanceValue.doubleValue(for: .meter())
                VirtualRunFileLogger.shared.log(category: .healthkit, message: "Distance update", data: [
                    "meters": Int(distance)
                ])
            }

        default:
            break
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthKitManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            logger.info("Workout state changed: \(fromState.rawValue) -> \(toState.rawValue)")

            switch toState {
            case .ended:
                isWorkoutActive = false
            case .paused:
                stopElapsedTimer()
            case .running:
                if fromState == .paused {
                    startElapsedTimer()
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            logger.error("Workout session failed: \(error.localizedDescription)")
            resetState()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }

                if let statistics = workoutBuilder.statistics(for: quantityType) {
                    updateMetrics(from: statistics)
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchHealthKitManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let filtered = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy < VirtualRunConstants.gpsMinAccuracyMeters }
        guard !filtered.isEmpty else { return }

        Task { @MainActor in
            lastLocation = filtered.last

            guard let routeBuilder = routeBuilder else { return }
            do {
                try await routeBuilder.insertRouteData(filtered)
            } catch {
                logger.error("Failed to insert route data: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
                logger.info("Location authorized — started GPS updates")
            } else if status == .denied || status == .restricted {
                logger.warning("Location authorization denied/restricted")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("Location error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum WorkoutError: Error, LocalizedError {
    case failedToCreateSession
    case healthKitNotAvailable

    var errorDescription: String? {
        switch self {
        case .failedToCreateSession:
            return "Failed to create workout session"
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device"
        }
    }
}
