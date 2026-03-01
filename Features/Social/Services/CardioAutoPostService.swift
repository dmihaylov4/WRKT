//
//  CardioAutoPostService.swift
//  WRKT
//
//  Service for automatically posting cardio workouts (runs > 1km) to social feed
//

import Foundation
import UIKit
import CoreLocation

@MainActor
final class CardioAutoPostService {
    static let shared = CardioAutoPostService()

    private let postRepository: PostRepository
    private let authService: SupabaseAuthService
    private let imageUploadService: ImageUploadService
    private let cardioDataExtractor = CardioDataExtractor.shared

    /// Minimum distance in km required for auto-posting
    private let minimumDistanceKm: Double = 1.0

    /// Track recently posted runs to avoid duplicates
    private var recentlyPostedRunIds: Set<UUID> = []

    private init() {
        self.postRepository = PostRepository(client: SupabaseClientWrapper.shared.client)
        self.authService = SupabaseAuthService.shared
        self.imageUploadService = ImageUploadService()
    }

    /// Check if user has auto-posting enabled and create cardio post if needed
    /// - Parameters:
    ///   - run: The imported run from HealthKit
    ///   - route: Optional route data with coordinates
    ///   - routeWithHR: Optional route data with heart rate samples
    func handleRunIfNeeded(run: Run, route: [Coordinate]? = nil, routeWithHR: [RoutePoint]? = nil) async {
        // Check if user has auto-posting enabled
        guard let user = authService.currentUser,
              let profile = user.profile,
              profile.autoPostCardio else {
            AppLogger.info("⏭️ Cardio auto-post disabled or user not logged in", category: AppLogger.social)
            return
        }

        // Check minimum distance (1km)
        guard run.distanceKm >= minimumDistanceKm else {
            AppLogger.info("⏭️ Run too short for auto-post: \(String(format: "%.2f", run.distanceKm))km < \(minimumDistanceKm)km", category: AppLogger.social)
            return
        }

        // Check if we've already posted this run recently (avoid duplicates)
        guard !recentlyPostedRunIds.contains(run.id) else {
            AppLogger.info("⏭️ Run already posted recently: \(run.id)", category: AppLogger.social)
            return
        }

        // Check if this is a running workout (not cycling, swimming, etc.)
        let isRunningWorkout = run.workoutType?.lowercased().contains("run") ?? true
        guard isRunningWorkout else {
            AppLogger.info("⏭️ Not a running workout: \(run.workoutType ?? "unknown")", category: AppLogger.social)
            return
        }

        AppLogger.info("🏃 Creating auto-post for run: \(String(format: "%.2f", run.distanceKm))km", category: AppLogger.social)

        // Mark as posted to avoid duplicates
        recentlyPostedRunIds.insert(run.id)

        // Clean up old entries (keep last 50)
        if recentlyPostedRunIds.count > 50 {
            recentlyPostedRunIds = Set(Array(recentlyPostedRunIds).suffix(50))
        }

        // Create the post
        await createCardioPost(run: run, route: route, routeWithHR: routeWithHR, userId: user.id)
    }

    /// Create a post for a cardio workout
    private func createCardioPost(run: Run, route: [Coordinate]?, routeWithHR: [RoutePoint]?, userId: UUID) async {
        do {
            // Create a mutable copy of the run with route data
            var enrichedRun = run
            enrichedRun.route = route
            enrichedRun.routeWithHR = routeWithHR

            // If splits or route are missing but we have a HealthKit UUID, try to fetch on-demand
            if let hkUUID = run.healthKitUUID,
               (enrichedRun.splits == nil || (enrichedRun.routeWithHR == nil && enrichedRun.route == nil)) {
                do {
                    let workouts = try await HealthKitManager.shared.fetchWorkoutByUUID(hkUUID)
                    if let hkWorkout = workouts.first {
                        if enrichedRun.splits == nil {
                            enrichedRun.splits = try await HealthKitManager.shared.fetchKilometerSplits(for: hkWorkout)
                        }
                        let metrics = await HealthKitManager.shared.fetchRunningMetrics(for: hkWorkout)
                        enrichedRun.avgRunningPower = metrics.avgPower
                        enrichedRun.avgCadence = metrics.avgCadence
                        enrichedRun.avgStrideLength = metrics.avgStrideLength
                        enrichedRun.avgGroundContactTime = metrics.avgGroundContactTime
                        enrichedRun.avgVerticalOscillation = metrics.avgVerticalOscillation

                        // Fetch route data if missing (needed for map snapshot)
                        if enrichedRun.routeWithHR == nil && enrichedRun.route == nil {
                            let routeWithHR = try? await HealthKitManager.shared.fetchRouteWithHeartRate(for: hkWorkout)
                            if let routeWithHR = routeWithHR, routeWithHR.count > 1 {
                                enrichedRun.routeWithHR = routeWithHR
                                AppLogger.debug("Fetched route on-demand: \(routeWithHR.count) points", category: AppLogger.social)
                            } else {
                                // fetchRouteWithHeartRate returned empty — try plain route as fallback
                                if let locations = try? await HealthKitManager.shared.fetchRoute(for: hkWorkout),
                                   locations.count > 1 {
                                    enrichedRun.route = locations.map { Coordinate(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
                                    AppLogger.debug("Fetched plain route on-demand: \(locations.count) points", category: AppLogger.social)
                                }
                            }
                        }
                    }
                } catch {
                    AppLogger.debug("Could not fetch on-demand data: \(error)", category: AppLogger.social)
                }
            }

            // Create a CompletedWorkout with cardio data
            var workout = CompletedWorkout(
                id: UUID(),
                date: run.date,
                startedAt: Calendar.current.date(byAdding: .second, value: -run.durationSec, to: run.date),
                entries: [],  // No strength entries for cardio
                workoutName: run.workoutName ?? run.workoutType ?? "Run"
            )

            // Fill in HealthKit data
            workout.matchedHealthKitUUID = run.healthKitUUID
            workout.matchedHealthKitCalories = run.calories
            workout.matchedHealthKitHeartRate = run.avgHeartRate
            workout.matchedHealthKitDuration = run.durationSec
            workout.matchedHealthKitDistance = run.distanceKm * 1000  // Convert to meters

            // Convert route with HR to heart rate samples for the post
            if let routeWithHR = routeWithHR, !routeWithHR.isEmpty {
                workout.matchedHealthKitHeartRateSamples = routeWithHR.compactMap { point in
                    guard let hr = point.hr else { return nil }
                    return HeartRateSample(timestamp: point.t, bpm: hr)
                }

                // Calculate max heart rate from samples
                if let maxHR = routeWithHR.compactMap({ $0.hr }).max() {
                    workout.matchedHealthKitMaxHeartRate = maxHR
                }
                if let minHR = routeWithHR.compactMap({ $0.hr }).min() {
                    workout.matchedHealthKitMinHeartRate = minHR
                }
            }

            // Enrich workout with cardio-specific data (splits, HR zones, running dynamics)
            cardioDataExtractor.enrichWorkout(&workout, from: enrichedRun)

            // Ensure cardioWorkoutType is the actual type, not generic "Cardio"
            if workout.cardioWorkoutType == nil || workout.cardioWorkoutType == "Cardio" {
                workout.cardioWorkoutType = run.workoutType ?? "Running"
            }

            AppLogger.debug("Enriched workout with splits: \(workout.cardioSplits?.count ?? 0), HR zones: \(workout.cardioHRZones?.count ?? 0)", category: AppLogger.social)

            // Generate map snapshot if route data is available
            var postImages: [PostImage]? = nil
            if let mapImage = try? await cardioDataExtractor.generateMapSnapshot(from: enrichedRun) {
                AppLogger.debug("Generated map snapshot for cardio post", category: AppLogger.social)

                // Upload the map image
                let uploadedImages = try await imageUploadService.uploadWorkoutImages(
                    images: [mapImage],
                    userId: userId,
                    isPublic: [true]  // Map snapshots are public
                )

                if !uploadedImages.isEmpty {
                    postImages = uploadedImages
                    AppLogger.debug("Uploaded map snapshot: \(uploadedImages.first?.storagePath ?? "unknown")", category: AppLogger.social)
                }
            }

            // No text caption for cardio posts — the card itself shows all the data
            let post = try await postRepository.createPost(
                workout: workout,
                caption: nil,
                images: postImages,
                visibility: .friends,
                userId: userId
            )

            AppLogger.success("✅ Cardio auto-post created successfully: \(post.id)", category: AppLogger.social)

            // Show success haptic
            Haptics.success()

        } catch {
            AppLogger.error("❌ Failed to create cardio auto-post", error: error, category: AppLogger.social)
        }
    }

}
