//
//  PostCreationViewModel.swift
//  WRKT
//
//  ViewModel for creating and sharing workout posts
//

import SwiftUI
import PhotosUI
import CoreLocation
import HealthKit


@MainActor
@Observable
final class PostCreationViewModel {
    var caption = ""
    var selectedVisibility: PostVisibility = .friends
    var selectedPhotos: [PhotosPickerItem] = []
    var photoImages: [UIImage] = []
    var imagePrivacySettings: [Bool] = [] // true = public, false = private
    var isUploading = false
    var isLoadingWorkouts = false
    var isGeneratingMap = false
    var error: UserFriendlyError?
    var retryAttempt = 0
    var recentWorkouts: [CompletedWorkout] = []
    var selectedWorkout: CompletedWorkout? {
        didSet {
            // When a workout is selected, generate map if it's cardio
            if let workout = selectedWorkout, workout.isCardioWorkout {
                Task {
                    await generateMapSnapshotForWorkout(workout)
                }
            }
        }
    }

    // Store runs to access route data for map generation
    private var cachedRuns: [Run] = []

    private let postRepository: PostRepository
    private let imageUploadService: ImageUploadService
    private let authService: SupabaseAuthService
    private let workoutStorage: WorkoutStorage
    private let retryManager = RetryManager.shared
    private let errorHandler = ErrorHandler.shared

    init(
        postRepository: PostRepository,
        imageUploadService: ImageUploadService,
        authService: SupabaseAuthService,
        workoutStorage: WorkoutStorage = .shared
    ) {
        self.postRepository = postRepository
        self.imageUploadService = imageUploadService
        self.authService = authService
        self.workoutStorage = workoutStorage
    }

    func createPost(with workout: CompletedWorkout) async throws {
        guard let currentUserId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        isUploading = true
        error = nil
        retryAttempt = 0

        // Step 1: Upload images with privacy settings (if any)
        var postImages: [PostImage] = []
        if !photoImages.isEmpty {
            // Ensure imagePrivacySettings has same length as photoImages
            // Default to public if not set
            let privacySettings = imagePrivacySettings.count == photoImages.count
                ? imagePrivacySettings
                : Array(repeating: true, count: photoImages.count)

            let uploadResult = await retryManager.uploadWithRetry {
                try await self.imageUploadService.uploadWorkoutImages(
                    images: self.photoImages,
                    userId: currentUserId,
                    isPublic: privacySettings
                )
            }

            switch uploadResult {
            case .success(let images):
                postImages = images

            case .failure(let err, let attempts):
                let userError = errorHandler.handleError(err, context: .imageUpload)
                errorHandler.logError(userError, context: .imageUpload)
                self.error = userError
                self.retryAttempt = attempts
                isUploading = false
                Haptics.error()
                throw err
            }
        }

        // Step 2: Create post with retry
        let postResult = await retryManager.fetchWithRetry {
            try await self.postRepository.createPost(
                workout: workout,
                caption: self.caption.isEmpty ? nil : self.caption,
                images: postImages.isEmpty ? nil : postImages,
                visibility: self.selectedVisibility,
                userId: currentUserId
            )
        }

        switch postResult {
        case .success(let newPost):
            isUploading = false
            error = nil
            Haptics.success()

        case .failure(let err, let attempts):
            let userError = errorHandler.handleError(err, context: .post)
            errorHandler.logError(userError, context: .post)
            self.error = userError
            self.retryAttempt = attempts
            isUploading = false
            Haptics.error()
            throw err
        }
    }

    func loadPhotos() async {
        photoImages.removeAll()
        imagePrivacySettings.removeAll()

        for item in selectedPhotos {
            do {
                // Load image data
                guard let imageData = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                // Create UIImage from data
                guard let image = UIImage(data: imageData) else {
                    continue
                }

                // Re-encode as JPEG to ensure compatibility
                guard let jpegData = image.jpegData(compressionQuality: 0.9),
                      let finalImage = UIImage(data: jpegData) else {
                    continue
                }

                photoImages.append(finalImage)
                // Default to public (true) for new images
                imagePrivacySettings.append(true)

            } catch {
                self.error = UserFriendlyError(
                    title: "Photo Load Failed",
                    message: "Failed to load one or more photos",
                    suggestion: "Try selecting different photos",
                    isRetryable: false,
                    originalError: error
                )
            }
        }
    }

    /// Toggle privacy setting for a specific image
    func toggleImagePrivacy(at index: Int) {
        guard index < imagePrivacySettings.count else { return }
        imagePrivacySettings[index].toggle()
    }

    func removePhoto(at index: Int) {
        guard index < photoImages.count else { return }
        photoImages.remove(at: index)
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
        if index < imagePrivacySettings.count {
            imagePrivacySettings.remove(at: index)
        }
    }

    /// Add an initial image (e.g., map snapshot for cardio workouts)
    func addInitialImage(_ image: UIImage) {
        // Re-encode as JPEG to ensure compatibility
        guard let jpegData = image.jpegData(compressionQuality: 0.9),
              let finalImage = UIImage(data: jpegData) else {
            return
        }

        photoImages.insert(finalImage, at: 0) // Insert at beginning
        imagePrivacySettings.insert(true, at: 0) // Default to public
    }

    func loadRecentWorkouts() async {
        isLoadingWorkouts = true
        do {
            // Load both strength workouts and cardio runs
            let (workouts, _) = try await workoutStorage.loadWorkouts()
            let runs = try await workoutStorage.loadRuns()

            // Cache runs for map generation
            self.cachedRuns = runs

            // Only show workouts from the last 3 days
            let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()

            // Filter and convert strength workouts
            let recentStrengthWorkouts = workouts.filter { $0.date >= threeDaysAgo }

            // Filter and convert cardio runs to CompletedWorkout
            let recentCardioWorkouts = runs
                .filter { $0.date >= threeDaysAgo }
                .map { $0.toCompletedWorkout() }

            // Combine both types and sort by date
            recentWorkouts = (recentStrengthWorkouts + recentCardioWorkouts)
                .sorted(by: { $0.date > $1.date })
                .prefix(10)
                .map { $0 }

            isLoadingWorkouts = false
        } catch {
            self.error = UserFriendlyError(
                title: "Workouts Load Failed",
                message: "Failed to load workouts",
                suggestion: "Pull down to refresh",
                isRetryable: true,
                originalError: error
            )
            isLoadingWorkouts = false
        }
    }

    // MARK: - Map Snapshot Generation

    /// Generate map snapshot for a cardio workout
    private func generateMapSnapshotForWorkout(_ workout: CompletedWorkout) async {
        guard workout.isCardioWorkout else { return }

        // Find the corresponding Run using the HealthKit UUID or workout ID
        // Check both cachedRuns and the workout store for the latest data
        var run: Run?
        let allRuns = cachedRuns.isEmpty ? AppDependencies.shared.workoutStore.runs : cachedRuns
        if let healthKitUUID = workout.matchedHealthKitUUID {
            run = allRuns.first { $0.healthKitUUID == healthKitUUID }
        } else {
            run = allRuns.first { $0.id == workout.id }
        }

        // Get route coordinates — try run first, then fetch on-demand from HealthKit
        var coordinates: [CLLocationCoordinate2D]?
        var hrValues: [Double]?

        if let routeWithHR = run?.routeWithHR, routeWithHR.count > 1 {
            print("🗺️ [MapSnapshot] Using routeWithHR with \(routeWithHR.count) points")
            coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = routeWithHR.map { $0.hr ?? .nan }
        } else if let route = run?.route, route.count > 1 {
            print("🗺️ [MapSnapshot] Using route with \(route.count) points")
            coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        } else if let hkUUID = workout.matchedHealthKitUUID {
            // No route data on run — fetch on-demand from HealthKit
            print("🗺️ [MapSnapshot] No route on run (run found: \(run != nil)), fetching from HealthKit UUID: \(hkUUID)...")
            isGeneratingMap = true
            do {
                let workouts = try await HealthKitManager.shared.fetchWorkoutByUUID(hkUUID)
                print("🗺️ [MapSnapshot] fetchWorkoutByUUID returned \(workouts.count) workouts")
                if let hkWorkout = workouts.first {
                    print("🗺️ [MapSnapshot] Fetching route with HR for workout: \(hkWorkout.workoutActivityType.rawValue)")
                    do {
                        let routeWithHR = try await HealthKitManager.shared.fetchRouteWithHeartRate(for: hkWorkout)
                        print("🗺️ [MapSnapshot] fetchRouteWithHeartRate returned \(routeWithHR.count) points")
                        if routeWithHR.count > 1 {
                            coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                            hrValues = routeWithHR.map { $0.hr ?? .nan }
                        }
                    } catch {
                        print("🗺️ [MapSnapshot] fetchRouteWithHeartRate FAILED: \(error)")
                        // Try plain route as fallback
                        do {
                            let locations = try await HealthKitManager.shared.fetchRoute(for: hkWorkout)
                            print("🗺️ [MapSnapshot] fetchRoute returned \(locations.count) locations")
                            if locations.count > 1 {
                                coordinates = locations.map { CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                            }
                        } catch {
                            print("🗺️ [MapSnapshot] fetchRoute also FAILED: \(error)")
                        }
                    }
                } else {
                    print("🗺️ [MapSnapshot] No HKWorkout found for UUID \(hkUUID)")
                }
            } catch {
                print("🗺️ [MapSnapshot] fetchWorkoutByUUID FAILED: \(error)")
            }
        } else {
            print("🗺️ [MapSnapshot] No run found and no HealthKit UUID to fetch route")
        }

        guard let coordinates = coordinates, coordinates.count > 1 else {
            print("🗺️ [MapSnapshot] No route data available for run")
            isGeneratingMap = false
            return
        }

        isGeneratingMap = true

        do {
            print("🗺️ [MapSnapshot] Generating snapshot...")
            let snapshot = try await MapSnapshotService.shared.generateRouteSnapshot(
                coordinates: coordinates,
                hrValues: hrValues,
                size: CGSize(width: 600, height: 400)
            )

            addInitialImage(snapshot)
            print("🗺️ [MapSnapshot] Snapshot added to images!")
        } catch {
            print("🗺️ [MapSnapshot] Failed to generate snapshot: \(error)")
        }

        isGeneratingMap = false
    }
}
