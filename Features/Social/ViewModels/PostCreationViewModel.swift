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
    var photoImages: [UIImage] = []         // user-picked photos only
    var mapImage: UIImage?                  // map snapshot, tracked separately so loadPhotos() never wipes it
    var imagePrivacySettings: [Bool] = []   // mirrors photoImages (not mapImage)
    var isUploading = false
    var isLoadingWorkouts = false
    var isGeneratingMap = false
    var error: UserFriendlyError?
    var retryAttempt = 0
    var recentWorkouts: [CompletedWorkout] = []
    var selectedWorkouts: [CompletedWorkout] = []
    var mapImagesByWorkoutID: [UUID: UIImage] = [:]

    var selectedWorkout: CompletedWorkout? {
        get { selectedWorkouts.first }
        set { selectedWorkouts = newValue.map { [$0] } ?? [] }
    }

    var primaryWorkout: CompletedWorkout? {
        selectedWorkouts.first
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
        try await createPost(with: [workout])
    }

    func createPost(with workouts: [CompletedWorkout]) async throws {
        guard !workouts.isEmpty else {
            throw SupabaseError.serverError("Cannot create post without a workout")
        }

        guard let currentUserId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        selectedWorkouts = workouts
        isUploading = true
        error = nil
        retryAttempt = 0

        // Step 1: Upload user-picked photos (if any)
        var uploadedUserPhotos: [PostImage] = []
        if !photoImages.isEmpty {
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
                uploadedUserPhotos = images

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

        // Step 2: Check if an auto-post already exists for this workout.
        // If so, extend it with the user's photo instead of creating a duplicate.
        // Only applies to single-workout posts.
        if workouts.count == 1,
           let workout = workouts.first,
           let hkUUID = workout.matchedHealthKitUUID,
           let existingPost = try? await postRepository.fetchOwnPost(forHealthKitUUID: hkUUID, userId: currentUserId),
           !uploadedUserPhotos.isEmpty {
            // Order: user photo(s) → map (slot 2) → any other existing images
            let existingImages = existingPost.images ?? []
            let mapImages = existingImages.filter(\.isGeneratedMapImage)
            let otherImages = existingImages.filter { !$0.isGeneratedMapImage }
            let reorderedImages = uploadedUserPhotos + mapImages + otherImages

            try await postRepository.updatePostImages(existingPost.id, images: reorderedImages)
            isUploading = false
            error = nil
            Haptics.success()
            return
        }

        // Step 3: No existing post — create a new one.
        // Compose images: user photos first, then map snapshot(s) (if any).
        let mapImagesToUpload: [UIImage]
        if workouts.count > 1 {
            mapImagesToUpload = generatedMapImagesInSelectionOrder
        } else if let mapImage {
            mapImagesToUpload = [mapImage]
        } else {
            mapImagesToUpload = []
        }

        var mapUploadedImages: [PostImage] = []
        if !mapImagesToUpload.isEmpty {
            let mapResult = await retryManager.uploadWithRetry {
                try await self.imageUploadService.uploadWorkoutImages(
                    images: mapImagesToUpload,
                    userId: currentUserId,
                    isPublic: Array(repeating: true, count: mapImagesToUpload.count),
                    fileNamePrefix: "route_map"
                )
            }
            if case .success(let imgs) = mapResult {
                mapUploadedImages = imgs
            }
        }

        let allImages = uploadedUserPhotos + mapUploadedImages
        let postResult = await retryManager.fetchWithRetry {
            try await self.postRepository.createPost(
                workouts: workouts,
                caption: self.caption.isEmpty ? nil : self.caption,
                images: allImages.isEmpty ? nil : allImages,
                visibility: self.selectedVisibility,
                userId: currentUserId
            )
        }

        switch postResult {
        case .success:
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

    private func mapIdentity(for workout: CompletedWorkout) -> UUID {
        workout.matchedHealthKitUUID ?? workout.id
    }

    private var generatedMapImagesInSelectionOrder: [UIImage] {
        selectedWorkouts.compactMap { workout in
            mapImagesByWorkoutID[mapIdentity(for: workout)]
        }
    }

    func loadPhotos() async {
        photoImages.removeAll()          // only clears user-picked photos; mapImage is untouched
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

    /// Set the map snapshot for this post. Tracked separately from user-picked photos
    /// so that loadPhotos() never wipes it when the user selects images.
    func addInitialImage(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.9),
              let finalImage = UIImage(data: jpegData) else {
            return
        }
        mapImage = finalImage
        // Also update the per-workout dict so external callers (e.g. CardioDetailView)
        // that call addInitialImage directly are reflected in map selection order.
        if let selectedWorkout {
            mapImagesByWorkoutID[mapIdentity(for: selectedWorkout)] = finalImage
        }
    }

    func loadRecentWorkouts() async {
        isLoadingWorkouts = true
        do {
            // Load both strength workouts and cardio runs
            let (workouts, _) = try await workoutStorage.loadWorkouts()
            let runs = try await workoutStorage.loadRuns()

            // Cache runs for map generation
            self.cachedRuns = runs

            // Show the latest workouts regardless of age, then cap the picker list.
            let recentStrengthWorkouts = workouts

            // Build the set of HealthKit UUIDs already matched to app workouts,
            // so we don't show them again as separate entries in the picker.
            let matchedHKUUIDs = Set(workouts.compactMap { $0.matchedHealthKitUUID })

            // Filter and convert runs to CompletedWorkout, excluding those already
            // matched to an app workout (strength sessions recorded via ExerciseSessionView).
            let recentCardioWorkouts = runs
                .filter { run in
                    guard let hkUUID = run.healthKitUUID else { return true }
                    return !matchedHKUUIDs.contains(hkUUID)
                }
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
    func generateMapSnapshotForWorkout(_ workout: CompletedWorkout) async {
        guard workout.isCardioWorkout else { return }

        // Skip if a map snapshot has already been generated for this specific workout.
        let identity = mapIdentity(for: workout)
        if mapImagesByWorkoutID[identity] != nil { return }

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
            coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = routeWithHR.map { $0.hr ?? .nan }
        } else if let route = run?.route, route.count > 1 {
            coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        } else if let hkUUID = workout.matchedHealthKitUUID {
            // No usable route on the cached run — fetch on-demand from HealthKit.
            await HealthKitManager.shared.retryFailedRouteTaskIfNeeded(for: hkUUID)
            isGeneratingMap = true
            if let hkWorkout = try? await HealthKitManager.shared.fetchWorkoutByUUID(hkUUID).first {
                do {
                    let routeWithHR = try await HealthKitManager.shared.fetchRouteWithHeartRate(for: hkWorkout)
                    if routeWithHR.count > 1 {
                        coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                        hrValues = routeWithHR.map { $0.hr ?? .nan }
                    } else {
                        let locations = try await HealthKitManager.shared.fetchRoute(for: hkWorkout)
                        if locations.count > 1 {
                            coordinates = locations.map { CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                        }
                    }
                } catch {
                    if let locations = try? await HealthKitManager.shared.fetchRoute(for: hkWorkout),
                       locations.count > 1 {
                        coordinates = locations.map { CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                    }
                }
            }
        }

        guard let coordinates = coordinates, coordinates.count > 1 else {
            isGeneratingMap = false
            return
        }

        do {
            let snapshot = try await MapSnapshotService.shared.generateRouteSnapshot(
                coordinates: coordinates,
                hrValues: hrValues,
                size: CGSize(width: 600, height: 400)
            )
            mapImagesByWorkoutID[identity] = snapshot
            if selectedWorkouts.count <= 1 {
                addInitialImage(snapshot)
            }
        } catch {
            // snapshot generation failed — post without map
        }

        isGeneratingMap = false
    }

    func generateMapSnapshotsForSelectedWorkouts() async {
        let cardioWorkouts = selectedWorkouts.filter(\.isCardioWorkout)
        guard !cardioWorkouts.isEmpty else { return }

        isGeneratingMap = true
        defer { isGeneratingMap = false }

        for workout in cardioWorkouts {
            let identity = mapIdentity(for: workout)
            if mapImagesByWorkoutID[identity] != nil { continue }
            await generateMapSnapshotForWorkout(workout)
        }
    }
}
