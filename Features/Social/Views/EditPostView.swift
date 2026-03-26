import SwiftUI
import CoreLocation

/// View for editing a post's caption and visibility
struct EditPostView: View {
    let post: PostWithAuthor
    let currentUserId: UUID?
    let onSave: @MainActor @Sendable (String?, PostVisibility) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    @State private var visibility: PostVisibility
    @State private var isSaving = false
    @State private var error: String?
    @State private var isBackfilling = false
    @State private var routeBackfillStatus: RouteStatus = .unknown

    private enum RouteStatus {
        case unknown, hasMap, noMap, building, success, failed
    }

    private let imageUploadService = ImageUploadService()

    init(post: PostWithAuthor, currentUserId: UUID? = nil, onSave: @escaping @MainActor @Sendable (String?, PostVisibility) async -> Void) {
        self.post = post
        self.currentUserId = currentUserId
        self.onSave = onSave
        _caption = State(initialValue: post.post.caption ?? "")
        _visibility = State(initialValue: post.post.visibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Caption (optional)", text: $caption, axis: .vertical)
                        .lineLimit(5...10)
                        .disabled(isSaving)
                } header: {
                    Text("Caption")
                } footer: {
                    Text("You can only edit the caption and visibility. The workout details and photos cannot be changed.")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Section("Visibility") {
                    Picker("Who can see this post", selection: $visibility) {
                        ForEach([PostVisibility.publicPost, .friends, .privatePost], id: \.self) { vis in
                            Label(vis.displayName, systemImage: vis.icon)
                                .tag(vis)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(isSaving)
                }

                // Route Map section — only for own cardio posts linked to HealthKit
                if post.post.workoutData.isCardioWorkout,
                   currentUserId == post.post.userId,
                   post.post.workoutData.matchedHealthKitUUID != nil {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Route Map")
                                    .font(.subheadline)
                                switch routeBackfillStatus {
                                case .unknown:
                                    Text(post.post.images?.isEmpty == false ? "Map attached" : "No map yet")
                                        .font(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .hasMap:
                                    Text("Map attached")
                                        .font(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .noMap:
                                    Text("No route data in HealthKit yet")
                                        .font(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .building:
                                    Text("Building...")
                                        .font(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .success:
                                    Text("Route map added")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                case .failed:
                                    Text("Could not build route — try again later")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            if isBackfilling {
                                ProgressView()
                            } else if routeBackfillStatus != .success {
                                Button("Rebuild") {
                                    Task { await backfillRoute() }
                                }
                                .font(.subheadline)
                                .disabled(isSaving)
                            }
                        }
                    } header: {
                        Text("Route")
                    } footer: {
                        Text("Fetches the GPS route from HealthKit and attaches it as a map image.")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await saveChanges()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || !hasChanges)
                }
            }
        }
    }

    private func backfillRoute() async {
        guard !isBackfilling,
              let userId = currentUserId,
              let hkUUID = post.post.workoutData.matchedHealthKitUUID else { return }

        isBackfilling = true
        routeBackfillStatus = .building

        // Fetch workout from HealthKit
        guard let hkWorkout = try? await HealthKitManager.shared.fetchWorkoutByUUID(hkUUID).first else {
            routeBackfillStatus = .noMap
            isBackfilling = false
            return
        }

        // Fetch route, preferring HR-enriched version
        let routePoints = try? await HealthKitManager.shared.fetchRouteWithHeartRate(for: hkWorkout)
        let coordinates: [CLLocationCoordinate2D]
        let hrValues: [Double]?

        if let points = routePoints, points.count > 1 {
            coordinates = points.map { $0.coordinate }
            hrValues = points.compactMap { $0.hr }.isEmpty ? nil : points.map { $0.hr ?? .nan }
        } else if let locations = try? await HealthKitManager.shared.fetchRoute(for: hkWorkout),
                  locations.count > 1 {
            coordinates = locations.map { $0.coordinate }
            hrValues = nil
        } else {
            routeBackfillStatus = .noMap
            isBackfilling = false
            return
        }

        guard let snapshot = try? await MapSnapshotService.shared.generateRouteSnapshot(
            coordinates: coordinates,
            hrValues: hrValues
        ) else {
            routeBackfillStatus = .failed
            isBackfilling = false
            return
        }

        guard let uploadedImages = try? await imageUploadService.uploadWorkoutImages(
            images: [snapshot],
            userId: userId,
            isPublic: [true]
        ), !uploadedImages.isEmpty else {
            routeBackfillStatus = .failed
            isBackfilling = false
            return
        }

        let postRepo = PostRepository()
        let allImages = (post.post.images ?? []) + uploadedImages
        if (try? await postRepo.updatePostImages(post.post.id, images: allImages)) != nil {
            routeBackfillStatus = .success
        } else {
            routeBackfillStatus = .failed
        }
        isBackfilling = false
    }

    private var hasChanges: Bool {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalCaption = post.post.caption ?? ""
        return trimmedCaption != originalCaption || visibility != post.post.visibility
    }

    private func saveChanges() async {
        isSaving = true
        error = nil

        // Capture values before async operations to avoid concurrency issues
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = trimmedCaption.isEmpty ? nil : trimmedCaption
        let currentVisibility = visibility

        await onSave(finalCaption, currentVisibility)
        Haptics.success()
        dismiss()
    }
}

// Preview removed to avoid complex initializations
