//
//  PostCreationView.swift
//  WRKT
//
//  Create and share workout posts
//

import SwiftUI
import PhotosUI
import SwiftData

struct PostCreationView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss

    let initialWorkout: CompletedWorkout?
    let initialMapImage: UIImage?

    @State private var viewModel: PostCreationViewModel?
    @State private var showingWorkoutPicker = false

    @Query(
        filter: #Predicate<PushPullBalance> { _ in true },
        sort: \PushPullBalance.weekStart,
        order: .forward
    ) private var pushPullAll: [PushPullBalance]

    private var pushPullNote: String? {
        let recent = pushPullAll.suffix(4)
        let totalPush = recent.reduce(0.0) { $0 + $1.pushVolume }
        let totalPull = recent.reduce(0.0) { $0 + $1.pullVolume }
        guard totalPush > 0 || totalPull > 0 else { return nil }
        let ratio = totalPush > 0 ? totalPull / totalPush : 999.0
        let ratioStr = String(format: "%.1f", min(ratio, 99.0))
        if ratio > 2.0 {
            return "Push:pull ratio this month: \(ratioStr). More pulling would support shoulder health."
        } else if ratio < 0.8 {
            return "Push:pull ratio this month: \(ratioStr). More pushing would balance your training."
        }
        return nil
    }

    init(workout: CompletedWorkout? = nil, mapImage: UIImage? = nil) {
        self.initialWorkout = workout
        self.initialMapImage = mapImage
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if let viewModel = viewModel {
                        Button("Share") {
                            Task {
                                await sharePost(viewModel: viewModel)
                            }
                        }
                        .disabled(viewModel.selectedWorkouts.isEmpty || viewModel.isUploading)
                        .bold()
                    }
                }
            }
            .sheet(isPresented: $showingWorkoutPicker) {
                if let viewModel = viewModel {
                    WorkoutPickerSheet(
                        workouts: viewModel.recentWorkouts,
                        selectedWorkouts: Binding(
                            get: { viewModel.selectedWorkouts },
                            set: { viewModel.selectedWorkouts = $0 }
                        )
                    )
                }
            }
            .task {
                if viewModel == nil {
                    let vm = PostCreationViewModel(
                        postRepository: deps.postRepository,
                        imageUploadService: deps.imageUploadService,
                        authService: deps.authService
                    )
                    viewModel = vm

                    if let initialWorkout {
                        vm.selectedWorkouts = [initialWorkout]
                    }

                    // Add initial map image if provided (from CardioDetailView)
                    if let mapImage = initialMapImage {
                        vm.addInitialImage(mapImage)
                    }

                    // Load recent workouts (populates cachedRuns for map generation)
                    await vm.loadRecentWorkouts()

                    // If cardio workout with no map provided, generate one now
                    // (cachedRuns is populated so route lookup will succeed)
                    if initialMapImage == nil,
                       let workout = initialWorkout, workout.isCardioWorkout {
                        await vm.generateMapSnapshotForWorkout(workout)
                    }
                }
            }
            .onChange(of: viewModel?.selectedWorkouts.map(\.id) ?? []) { _, newIDs in
                guard initialWorkout == nil, !newIDs.isEmpty else { return }
                guard let vm = viewModel else { return }
                Task {
                    await vm.generateMapSnapshotsForSelectedWorkouts()
                }
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: PostCreationViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Workout Preview
                if !viewModel.selectedWorkouts.isEmpty {
                    workoutPreview(viewModel.selectedWorkouts, viewModel: viewModel)
                } else {
                    noWorkoutState(viewModel: viewModel)
                }

                // Caption Input
                captionSection(viewModel: viewModel)

                // Photo Picker
                photoSection(viewModel: viewModel)

                // Visibility Selector
                visibilitySection(viewModel: viewModel)

                // Error Message
                if let error = viewModel.error, !viewModel.selectedWorkouts.isEmpty {
                    let workouts = viewModel.selectedWorkouts
                    InlineErrorView(
                        error: error,
                        onRetry: {
                            Task {
                                try? await viewModel.createPost(with: workouts)
                            }
                        },
                        onDismiss: {
                            viewModel.error = nil
                        }
                    )
                }
            }
            .padding()
        }
        .overlay {
            if viewModel.isUploading {
                uploadingOverlay
            } else if viewModel.isGeneratingMap {
                mapGeneratingOverlay
            }
        }
    }

    private func workoutPreview(_ workouts: [CompletedWorkout], viewModel: PostCreationViewModel) -> some View {
        let isSession = workouts.count > 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isSession ? "Session" : "Workout")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                Button {
                    showingWorkoutPicker = true
                } label: {
                    Text("Change")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.brand)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(workouts, id: \.id) { workout in
                    WorkoutPickerRow(workout: workout, isSelected: false)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func noWorkoutState(viewModel: PostCreationViewModel) -> some View {
        VStack(spacing: 16) {
            if viewModel.isLoadingWorkouts {
                ProgressView()
                    .padding()
            } else if viewModel.recentWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.run.circle")
                        .dsFont(.largeTitle)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text("No workouts yet")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("Complete a workout to share it")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .dsFont(.largeTitle)
                        .foregroundStyle(DS.Semantic.brand)

                    Text("Select a workout")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("Choose from your recent workouts")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Button {
                        showingWorkoutPicker = true
                    } label: {
                        Text("Choose Workout")
                            .dsFont(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(DS.Semantic.brand)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    private func captionSection(viewModel: PostCreationViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caption")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            TextField("Share your thoughts...", text: Binding(
                get: { viewModel.caption },
                set: { viewModel.caption = $0 }
            ), axis: .vertical)
                .lineLimit(5...10)
                .textFieldStyle(.plain)
                .padding(12)
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func photoSection(viewModel: PostCreationViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                PhotosPicker(
                    selection: Binding(
                        get: { viewModel.selectedPhotos },
                        set: { viewModel.selectedPhotos = $0 }
                    ),
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.brand)
                }
                .onChange(of: viewModel.selectedPhotos) { _, _ in
                    Task {
                        await viewModel.loadPhotos()
                    }
                }
            }

            let hasAnyImage = !viewModel.photoImages.isEmpty || viewModel.mapImage != nil
            if hasAnyImage {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // User-picked photos first
                        ForEach(Array(viewModel.photoImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .bottomLeading) {
                                        privacyToggleButton(for: index, viewModel: viewModel)
                                    }

                                Button {
                                    viewModel.removePhoto(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .dsFont(.title3)
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.5)))
                                }
                                .padding(4)
                            }
                        }

                        // Map snapshot — slot 2 (after user photos), non-removable
                        if let map = viewModel.mapImage {
                            ZStack(alignment: .bottomLeading) {
                                Image(uiImage: map)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                Text("Map")
                                    .dsFont(.caption2, weight: .bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                                    .padding(6)
                            }
                        }
                    }
                }
            } else {
                Text("No photos selected")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func visibilitySection(viewModel: PostCreationViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visibility")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 0) {
                visibilityOption(.publicPost, viewModel: viewModel)
                Divider().padding(.leading, 44)
                visibilityOption(.friends, viewModel: viewModel)
                Divider().padding(.leading, 44)
                visibilityOption(.privatePost, viewModel: viewModel)
            }
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func visibilityOption(_ visibility: PostVisibility, viewModel: PostCreationViewModel) -> some View {
        Button {
            viewModel.selectedVisibility = visibility
            Haptics.light()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: visibility.icon)
                    .dsFont(.title3)
                    .foregroundStyle(viewModel.selectedVisibility == visibility ? DS.Semantic.brand : DS.Semantic.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(visibility.displayName)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(visibilityDescription(visibility))
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                if viewModel.selectedVisibility == visibility {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Semantic.brand)
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func visibilityDescription(_ visibility: PostVisibility) -> String {
        switch visibility {
        case .publicPost:
            return "Anyone can see this post"
        case .friends:
            return "Only your friends can see this"
        case .privatePost:
            return "Only you can see this"
        }
    }


    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)

                Text("Sharing workout...")
                    .dsFont(.headline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var mapGeneratingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)

                Text("Preparing map...")
                    .dsFont(.headline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func privacyToggleButton(for index: Int, viewModel: PostCreationViewModel) -> some View {
        if index < viewModel.imagePrivacySettings.count {
            let isPublic = viewModel.imagePrivacySettings[index]

            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.toggleImagePrivacy(at: index)
                }
                Haptics.light()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isPublic ? "eye.fill" : "eye.slash.fill")
                        .dsFont(.caption2)
                    Text(isPublic ? "Public" : "Private")
                        .dsFont(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPublic ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                )
            }
            .padding(6)
        }
    }

    private func sharePost(viewModel: PostCreationViewModel) async {
        let workouts = viewModel.selectedWorkouts
        guard !workouts.isEmpty else { return }

        do {
            try await viewModel.createPost(with: workouts)
            dismiss()
        } catch {
            // Error is already set in viewModel
        }
    }
}

// MARK: - Workout Picker Sheet

struct WorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workouts: [CompletedWorkout]
    @Binding var selectedWorkouts: [CompletedWorkout]
    @State private var pendingSelection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(workouts, id: \.id) { workout in
                        Button {
                            if pendingSelection.contains(workout.id) {
                                pendingSelection.remove(workout.id)
                            } else {
                                pendingSelection.insert(workout.id)
                            }
                            Haptics.light()
                        } label: {
                            WorkoutPickerRow(
                                workout: workout,
                                isSelected: pendingSelection.contains(workout.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Select Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(pendingSelection.count))") {
                        selectedWorkouts = workouts.filter { pendingSelection.contains($0.id) }
                        dismiss()
                    }
                    .disabled(pendingSelection.isEmpty)
                    .bold()
                }
            }
            .onAppear {
                pendingSelection = Set(selectedWorkouts.map(\.id))
            }
        }
    }
}

struct WorkoutPickerRow: View {
    let workout: CompletedWorkout
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: workout.workoutIcon)
                        .foregroundStyle(DS.Semantic.brand)
                        .dsFont(.caption)

                    Text(workout.workoutName ?? workout.workoutTypeDisplayName)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Text(workout.date, style: .date)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                // Stats - different for cardio vs strength
                if workout.isCardioWorkout {
                    HStack(spacing: 16) {
                        if let calories = workout.matchedHealthKitCalories {
                            Label(String(format: "%.0f cal", calories), systemImage: "flame.fill")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        if let duration = workout.matchedHealthKitDuration {
                            let minutes = duration / 60
                            Label("\(minutes) min", systemImage: "clock.fill")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                } else if workout.entries.isEmpty && workout.matchedHealthKitUUID != nil {
                    // HK-only strength workout: show duration + calories + avg HR
                    HStack(spacing: 16) {
                        if let duration = workout.matchedHealthKitDuration {
                            Label("\(duration / 60) min", systemImage: "clock.fill")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        if let calories = workout.matchedHealthKitCalories {
                            Label(String(format: "%.0f cal", calories), systemImage: "flame.fill")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        if let hr = workout.matchedHealthKitHeartRate {
                            Label(String(format: "%.0f bpm", hr), systemImage: "heart.fill")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                } else {
                    HStack(spacing: 16) {
                        Label("\(workout.entries.count) exercises", systemImage: "dumbbell.fill")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        let totalSets = workout.entries.reduce(0) { $0 + $1.sets.count }
                        Label("\(totalSets) sets", systemImage: "list.bullet")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.Semantic.brand)
                    .dsFont(.title3)
            }
        }
        .padding()
        .background(isSelected ? DS.Semantic.brand.opacity(0.1) : DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    let sampleWorkout = CompletedWorkout(
        date: Date(),
        startedAt: Date().addingTimeInterval(-3600),
        entries: [
            WorkoutEntry(
                exerciseID: "bench-press",
                exerciseName: "Bench Press",
                muscleGroups: ["Chest", "Triceps"],
                sets: [
                    SetInput(reps: 10, weight: 100, isCompleted: true)
                ]
            )
        ],
        workoutName: "Push Day"
    )

    PostCreationView(workout: sampleWorkout)
        .environment(\.dependencies, AppDependencies.shared)
}
