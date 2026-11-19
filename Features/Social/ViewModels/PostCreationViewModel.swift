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
    var weeklyProgressStats: WeeklyPostStats? = nil
    var selectedPhotos: [PhotosPickerItem] = []
    var photoImages: [UIImage] = []         // user-picked photos only
    var mapImage: UIImage?                  // map snapshot, tracked separately so loadPhotos() never wipes it
    var attachedImage: UIImage?             // picture handed in by the caller (year award), posted first, never wiped by loadPhotos()
    var imagePrivacySettings: [Bool] = []   // mirrors photoImages (not mapImage)
    var isUploading = false
    var isLoadingWorkouts = false
    var isGeneratingMap = false
    var error: UserFriendlyError?
    var retryAttempt = 0
    var recentWorkouts: [CompletedWorkout] = []
    var selectedWorkouts: [CompletedWorkout] = []
    var mapImagesByWorkoutID: [UUID: UIImage] = [:]
    var friends: [Friend] = []
    var selectedPartner: Friend?
    var isLoadingFriends = false

    var selectedWorkout: CompletedWorkout? {
        get { selectedWorkouts.first }
        set { selectedWorkouts = newValue.map { [$0] } ?? [] }
    }

    var primaryWorkout: CompletedWorkout? {
        selectedWorkouts.first
    }

    /// The picker entries that stand for a run, as the picker built them (without heart-rate
    /// samples). One still selected unchanged is completed from the run before posting.
    private var runPickerWorkouts: [UUID: CompletedWorkout] = [:]

    private let postRepository: PostRepository
    private let imageUploadService: ImageUploadService
    private let authService: SupabaseAuthService
    private let friendshipRepository: FriendshipRepository
    /// nil: the app's store.
    private let injectedStore: WorkoutStoreV2?
    private var workoutStore: WorkoutStoreV2 { injectedStore ?? AppDependencies.shared.workoutStore }
    private let retryManager = RetryManager.shared
    private let errorHandler = ErrorHandler.shared

    init(
        postRepository: PostRepository,
        imageUploadService: ImageUploadService,
        authService: SupabaseAuthService,
        friendshipRepository: FriendshipRepository,
        workoutStore: WorkoutStoreV2? = nil
    ) {
        self.postRepository = postRepository
        self.imageUploadService = imageUploadService
        self.authService = authService
        self.friendshipRepository = friendshipRepository
        self.injectedStore = workoutStore
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

        isUploading = true
        defer { isUploading = false }
        // Run-backed picker entries carry no heart-rate samples: post the full workout.
        let workouts = await Self.workoutsForPosting(workouts, picker: runPickerWorkouts, store: workoutStore)
        selectedWorkouts = workouts
        error = nil
        retryAttempt = 0

        // Step 1: Upload the attached picture and user-picked photos (if any). The attached
        // picture goes first, public, under its own file name so the post can be recognised
        // as the year award's (see PostImage.isYearAwardImage).
        var uploadedUserPhotos: [PostImage] = []
        let batches: [(images: [UIImage], isPublic: [Bool], prefix: String)] = [
            (attachedImage.map { [$0] } ?? [], attachedImage == nil ? [] : [true], PostImage.yearAwardPrefix),
            (photoImages,
             imagePrivacySettings.count == photoImages.count ? imagePrivacySettings : Array(repeating: true, count: photoImages.count),
             "workout")
        ]
        for batch in batches where !batch.images.isEmpty {
            let uploadResult = await retryManager.uploadWithRetry {
                try await self.imageUploadService.uploadWorkoutImages(
                    images: batch.images,
                    userId: currentUserId,
                    isPublic: batch.isPublic,
                    fileNamePrefix: batch.prefix
                )
            }

            switch uploadResult {
            case .success(let images):
                uploadedUserPhotos += images

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
        // Only applies to single-workout posts, and not to a post built around an attached
        // picture: that one keeps its own caption as a new post.
        if selectedPartner == nil,
           attachedImage == nil,
           weeklyProgressStats == nil,
           workouts.count == 1,
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
        if let selectedPartner, weeklyProgressStats == nil {
            let sharedPostResult = await retryManager.fetchWithRetry {
                try await self.postRepository.createSharedPost(
                    caption: self.caption.isEmpty ? nil : self.caption,
                    visibility: self.selectedVisibility,
                    images: allImages.isEmpty ? nil : allImages,
                    workoutData: workouts[0],
                    workoutDataList: workouts.count > 1 ? workouts : nil,
                    partnerUserId: selectedPartner.id,
                    partnerVRStats: nil,
                    runId: nil
                )
            }

            switch sharedPostResult {
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

            return
        }

        let postResult = await retryManager.fetchWithRetry {
            try await self.postRepository.createPost(
                workouts: workouts,
                caption: self.caption.isEmpty ? nil : self.caption,
                images: allImages.isEmpty ? nil : allImages,
                visibility: self.selectedVisibility,
                userId: currentUserId,
                postType: self.weeklyProgressStats != nil ? .weeklyProgress : .workout,
                weeklyStats: self.weeklyProgressStats
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

    func loadFriends() async {
        guard friends.isEmpty, !isLoadingFriends else { return }
        guard let currentUserId = authService.currentUser?.id else { return }

        isLoadingFriends = true
        defer { isLoadingFriends = false }

        do {
            friends = try await friendshipRepository.fetchFriends(userId: currentUserId)
        } catch {
            AppLogger.error("Failed to load friends for post partner picker", error: error, category: AppLogger.app)
        }
    }

    func selectPartner(_ friend: Friend?) {
        selectedPartner = friend
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

    /// Attach a picture the caller hands in (the year award plaque). Posted as the first,
    /// public photo; kept apart from user-picked photos so loadPhotos() never wipes it.
    func attachImage(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.92),
              let finalImage = UIImage(data: jpegData) else {
            attachedImage = image
            return
        }
        attachedImage = finalImage
    }

    func loadRecentWorkouts() async {
        isLoadingWorkouts = true
        // Strength workouts and cardio runs, from the loaded store: the history is never decoded
        // here. A history that failed to load, or does not load in time, ends in the error state.
        switch await Self.waitForHistory(workoutStore, limit: Self.historyWaitLimit) {
        case .loaded:
            let candidates = Self.pickerCandidates(workouts: workoutStore.completedWorkouts, runs: workoutStore.runSummaries)
            recentWorkouts = candidates.map(\.completedWorkout)
            runPickerWorkouts = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
                if case .run = candidate { return (candidate.completedWorkout.id, candidate.completedWorkout) }
                return nil
            })
        case .failed(let failure):
            error = UserFriendlyError(
                title: "Workouts Load Failed",
                message: "Failed to load workouts",
                suggestion: "Pull down to refresh",
                isRetryable: true,
                originalError: failure
            )
        }
        isLoadingWorkouts = false
    }

    enum HistoryWait {
        case loaded
        case failed(Error)
    }

    struct HistoryWaitTimedOut: Error {}

    /// How long the composer waits for history that is still loading.
    static let historyWaitLimit: Duration = .seconds(15)

    /// Waits for the store's history, but never longer than `limit` and never past a failed load.
    static func waitForHistory(_ store: WorkoutStoreV2, limit: Duration) async -> HistoryWait {
        if store.isStorageLoaded { return .loaded }
        return await waitForHistory(limit: limit) { try await store.waitForStorage() }
    }

    /// `wait` races the time limit; whichever ends first decides.
    static func waitForHistory(limit: Duration, _ wait: @escaping @MainActor () async throws -> Void) async -> HistoryWait {
        let once = HistoryWaitOnce()
        return await withCheckedContinuation { continuation in
            once.continuation = continuation
            once.timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                once.finish(.failed(HistoryWaitTimedOut()))
            }
            Task { @MainActor in
                do {
                    try await wait()
                    once.finish(.loaded)
                } catch {
                    once.finish(.failed(error))
                }
            }
        }
    }

    /// The picker's workouts: the latest `limit` of the logged workouts and the runs not already
    /// matched to one, newest first; on equal dates logged workouts come first, each in input
    /// order. Runs are converted without their heart-rate samples.
    static func pickerWorkouts(workouts: [CompletedWorkout], runs: [RunSummary], limit: Int = 10) -> [CompletedWorkout] {
        pickerCandidates(workouts: workouts, runs: runs, limit: limit).map(\.completedWorkout)
    }

    /// The picker's entries before conversion. The order is explicit: newest first, and on equal
    /// dates the order of `workouts` followed by the order of `runs`.
    static func pickerCandidates(workouts: [CompletedWorkout], runs: [RunSummary], limit: Int = 10) -> [HistoryCandidate] {
        // Runs already matched to an app workout (strength sessions recorded in the app)
        // are not shown again as separate entries.
        let matchedHKUUIDs = Set(workouts.compactMap { $0.matchedHealthKitUUID })
        let candidates = workouts.map(HistoryCandidate.workout) + runs
            .filter { run in
                guard let hkUUID = run.healthKitUUID else { return true }
                return !matchedHKUUIDs.contains(hkUUID)
            }
            .map(HistoryCandidate.run)
        return Array(HistoryCandidate.newestFirst(candidates).prefix(limit))
    }

    /// The workouts to post: a picker entry that stands for a run and is still exactly as the
    /// picker built it is replaced by the run's full conversion, samples included. Anything
    /// else, such as a detail screen's share with its route samples, is posted as it is. A run
    /// that can no longer be read is posted as listed.
    static func workoutsForPosting(_ workouts: [CompletedWorkout], picker: [UUID: CompletedWorkout],
                                   store: WorkoutStoreV2) async -> [CompletedWorkout] {
        let runIDs = workouts.compactMap { workout in picker[workout.id] == workout ? workout.id : nil }
        guard !runIDs.isEmpty, let loaded = try? await store.loadRuns(ids: runIDs) else { return workouts }
        return workouts.map { workout in
            guard picker[workout.id] == workout, case .loaded(let run) = loaded[workout.id] else { return workout }
            return run.toCompletedWorkout()
        }
    }

    // MARK: - Map Snapshot Generation

    /// Generate map snapshot for a cardio workout
    func generateMapSnapshotForWorkout(_ workout: CompletedWorkout) async {
        guard workout.isCardioWorkout else { return }

        // Skip if a map snapshot has already been generated for this specific workout.
        let identity = mapIdentity(for: workout)
        if mapImagesByWorkoutID[identity] != nil { return }

        // Find the corresponding run by HealthKit UUID or workout ID, and read its route.
        let store = workoutStore
        let summary: RunSummary?
        if let healthKitUUID = workout.matchedHealthKitUUID {
            summary = store.runSummary(healthKitUUID: healthKitUUID)
        } else {
            summary = store.runSummary(id: workout.id)
        }
        var run: Run?
        if let summary, case .loaded(let full)? = try? await store.loadRun(id: summary.id) {
            run = full
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

/// Resolves `waitForHistory` once, whichever of the load and the time limit ends first.
@MainActor
private final class HistoryWaitOnce {
    var continuation: CheckedContinuation<PostCreationViewModel.HistoryWait, Never>?
    var timer: Task<Void, Never>?

    func finish(_ result: PostCreationViewModel.HistoryWait) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        continuation.resume(returning: result)
    }
}
