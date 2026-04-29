import SwiftUI

/// View for editing a post's caption and visibility
struct EditPostView: View {
    let post: PostWithAuthor
    let currentUserId: UUID?
    let onSave: @MainActor @Sendable (String?, PostVisibility) async -> Void
    let onBackfillRoute: @MainActor @Sendable () async -> Bool

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

    init(
        post: PostWithAuthor,
        currentUserId: UUID? = nil,
        onSave: @escaping @MainActor @Sendable (String?, PostVisibility) async -> Void,
        onBackfillRoute: @escaping @MainActor @Sendable () async -> Bool
    ) {
        self.post = post
        self.currentUserId = currentUserId
        self.onSave = onSave
        self.onBackfillRoute = onBackfillRoute
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
                        .dsFont(.caption)
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
                                    .dsFont(.subheadline)
                                switch routeBackfillStatus {
                                case .unknown:
                                    Text(post.post.images?.isEmpty == false ? "Map attached" : "No map yet")
                                        .dsFont(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .hasMap:
                                    Text("Map attached")
                                        .dsFont(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .noMap:
                                    Text("No route data in HealthKit yet")
                                        .dsFont(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .building:
                                    Text("Building...")
                                        .dsFont(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                case .success:
                                    Text("Route map added")
                                        .dsFont(.caption)
                                        .foregroundStyle(.green)
                                case .failed:
                                    Text("Could not build route — try again later")
                                        .dsFont(.caption)
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
                                .dsFont(.subheadline)
                                .disabled(isSaving)
                            }
                        }
                    } header: {
                        Text("Route")
                    } footer: {
                        Text("Fetches the GPS route from HealthKit and attaches it as a map image.")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .dsFont(.caption)
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
              currentUserId != nil,
              post.post.workoutData.matchedHealthKitUUID != nil else { return }

        isBackfilling = true
        routeBackfillStatus = .building

        let success = await onBackfillRoute()
        routeBackfillStatus = success ? .success : .failed
        isBackfilling = false
    }

    private var hasChanges: Bool {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalCaption = post.post.caption ?? ""
        return trimmedCaption != originalCaption
            || visibility != post.post.visibility
            || routeBackfillStatus == .success
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
