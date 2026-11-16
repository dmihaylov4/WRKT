import SwiftUI
import PhotosUI

struct CutPostComposeHost: View {
    let initialWorkout: CompletedWorkout?
    let initialWorkouts: [CompletedWorkout]
    let initialMapImage: UIImage?
    let initialCaption: String
    let navigationTitle: String
    let weeklyStats: WeeklyProgressStats?
    let attachedImage: UIImage?
    @Environment(\.dependencies) private var deps
    @Environment(\.cutSheetDepth) private var sheetDepth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    @State private var viewModel: PostCreationViewModel?
    @State private var showingWorkoutPicker = false
    @State private var showingPartnerPicker = false
    @State private var showingSubmissionError = false

    var body: some View {
        NavigationStack {
            CutPostComposeView(model: model,
                caption: Binding(get: { viewModel?.caption ?? "" }, set: { viewModel?.caption = $0 }),
                visibility: Binding(get: { viewModel?.selectedVisibility ?? .friends }, set: { viewModel?.selectedVisibility = $0 }),
                actions: actions, image: photoImage, photoPicker: {
                    if let vm = viewModel {
                        PhotosPicker(selection: Binding(get: { vm.selectedPhotos }, set: { vm.selectedPhotos = $0 }), maxSelectionCount: 5, matching: .images) {
                            Label("Add Photos", systemImage: "photo.on.rectangle.angled").cutFont(.body).frame(minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(DS.Cut.Colors.textPrimary)
                    }
                })
                .toolbar(.hidden, for: .navigationBar)
                .alert(viewModel?.error?.title ?? "Can't Share Workout", isPresented: $showingSubmissionError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let error = viewModel?.error { Text([error.message, error.suggestion].compactMap { $0 }.joined(separator: "\n\n")) }
                }
                .sheet(isPresented: $showingWorkoutPicker) {
                    if let vm = viewModel {
                        CutPostComposeWorkoutPickerHost(workouts: vm.recentWorkouts,
                            selectedWorkouts: Binding(get: { vm.selectedWorkouts }, set: { vm.selectedWorkouts = $0 }))
                            .environment(\.cutSheetDepth, sheetDepth + 1)
                    }
                }
                .sheet(isPresented: $showingPartnerPicker) {
                    if let vm = viewModel {
                        CutPostComposePartnerPickerHost(friends: vm.friends,
                            selectedPartner: Binding(get: { vm.selectedPartner }, set: { vm.selectPartner($0) }), isLoading: vm.isLoadingFriends)
                            .environment(\.cutSheetDepth, sheetDepth + 1)
                    }
                }
                .task { await prepare() }
                .onChange(of: viewModel?.selectedPhotos ?? []) { _, _ in
                    if let vm = viewModel { Task { await vm.loadPhotos() } }
                }
                .onChange(of: viewModel?.selectedWorkouts.map(\.id) ?? []) { _, ids in
                    guard CutPostComposeLogic.shouldGenerateMaps(initialWorkoutProvided: initialWorkout != nil, attached: attachedImage != nil, selection: ids),
                          let vm = viewModel else { return }
                    Task { await vm.generateMapSnapshotsForSelectedWorkouts() }
                }
        }
    }
    private var model: CutPostComposeModel {
        guard let vm = viewModel else { return .init(title: navigationTitle, isInitializing: true) }
        let weekly = weeklyStats.map {
            CutPostComposeWeeklyFacts(volumeKg: $0.totalVolumeKg, exercises: $0.totalExercises, sets: $0.totalSets,
                                      strengthDone: $0.strengthDaysDone, strengthTarget: $0.strengthTarget,
                                      activeDone: $0.activeMinutesDone, activeTarget: $0.activeMinutesTarget,
                                      streak: $0.streak, superStreak: $0.superStreak)
        }
        return CutPostComposeLogic.model(title: navigationTitle, selected: vm.selectedWorkouts.map(Self.workoutFacts),
            available: vm.recentWorkouts.map(Self.workoutFacts), loadingWorkouts: vm.isLoadingWorkouts,
            uploading: vm.isUploading, generatingMap: vm.isGeneratingMap, weekly: weekly,
            partner: vm.selectedPartner.map(Self.partnerFacts), loadingFriends: vm.isLoadingFriends,
            attached: vm.attachedImage != nil,
            pickedPrivacy: vm.photoImages.indices.map { vm.imagePrivacySettings.indices.contains($0) ? vm.imagePrivacySettings[$0] : nil },
            map: vm.mapImage != nil, errorTitle: vm.error?.title, errorMessage: vm.error?.message,
            errorIsRetryable: vm.error?.isRetryable ?? false, unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg)
    }
    private var actions: CutPostComposeActions {
        .init(cancel: { dismiss() }, share: { if let vm = viewModel { Task { await sharePost(viewModel: vm) } } },
              chooseWorkouts: { showingWorkoutPicker = true }, choosePartner: { showingPartnerPicker = true },
              removePhoto: { viewModel?.removePhoto(at: $0) }, togglePrivacy: { index in
                  withAnimation(.spring(response: 0.3)) { viewModel?.toggleImagePrivacy(at: index) }
                  Haptics.light()
              }, retry: {
                  Haptics.light()
                  if let vm = viewModel { Task { await sharePost(viewModel: vm) } }
              }, dismissError: { Haptics.light(); viewModel?.error = nil }, feedback: { Haptics.light() })
    }
    private func photoImage(_ photo: CutPostComposeModel.Photo) -> Image? {
        guard let vm = viewModel else { return nil }
        switch photo.kind {
        case .attached: return vm.attachedImage.map { Image(uiImage: $0) }
        case .map: return vm.mapImage.map { Image(uiImage: $0) }
        case .picked(let index): return vm.photoImages.indices.contains(index) ? Image(uiImage: vm.photoImages[index]) : nil
        }
    }
    static func workoutFacts(_ workout: CompletedWorkout) -> CutPostComposeWorkoutFacts {
        .init(id: workout.id, title: workout.workoutName ?? workout.workoutTypeDisplayName, date: workout.date, icon: workout.workoutIcon,
              isCardio: workout.isCardioWorkout, isHealthKitOnlyStrength: !workout.isCardioWorkout && workout.entries.isEmpty && workout.matchedHealthKitUUID != nil,
              durationSeconds: workout.matchedHealthKitDuration, calories: workout.matchedHealthKitCalories,
              heartRate: workout.matchedHealthKitHeartRate, exercises: workout.entries.count, sets: workout.entries.reduce(0) { $0 + $1.sets.count })
    }
    static func partnerFacts(_ friend: Friend) -> CutPostComposeModel.Partner {
        .init(id: friend.id, name: friend.profile.displayName ?? friend.profile.username, handle: "@\(friend.profile.username)",
              initials: CutSocialLogic.initials(friend.profile.displayName ?? friend.profile.username), avatarURL: friend.profile.avatarUrl)
    }
    private func prepare() async {
        guard viewModel == nil else { return }
        let vm = PostCreationViewModel(postRepository: deps.postRepository, imageUploadService: deps.imageUploadService,
                                      authService: deps.authService, friendshipRepository: deps.friendshipRepository)
        viewModel = vm
        if !initialWorkouts.isEmpty { vm.selectedWorkouts = initialWorkouts }
        else if let initialWorkout { vm.selectedWorkouts = [initialWorkout] }
        if let weeklyStats { vm.weeklyProgressStats = weeklyStats.asPostStats(); vm.selectedVisibility = .friends }
        if !initialCaption.isEmpty { vm.caption = initialCaption }
        if let attachedImage { vm.attachImage(attachedImage) }
        if let initialMapImage { vm.addInitialImage(initialMapImage) }
        // Load cached runs before generating a route, as in the legacy screen.
        await vm.loadRecentWorkouts()
        await vm.loadFriends()
        if initialMapImage == nil, attachedImage == nil, let initialWorkout, initialWorkout.isCardioWorkout {
            await vm.generateMapSnapshotForWorkout(initialWorkout)
        }
    }
    private func sharePost(viewModel: PostCreationViewModel) async {
        guard !viewModel.isUploading else { return }
        let workouts = viewModel.selectedWorkouts
        guard !workouts.isEmpty else { return }
        do {
            try await viewModel.createPost(with: workouts)
            dismiss()
        } catch {
            if viewModel.error == nil {
                viewModel.error = ErrorHandler.shared.handleError(error, context: .post)
                Haptics.error()
            }
            showingSubmissionError = true
        }
    }
}

struct CutPostComposeWorkoutPickerHost: View {
    let workouts: [CompletedWorkout]
    @Binding var selectedWorkouts: [CompletedWorkout]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        CutPostComposeWorkoutPickerView(workouts: workouts.map { CutPostComposeLogic.workout(CutPostComposeHost.workoutFacts($0)) },
            selectedIDs: selectedWorkouts.map(\.id), done: { ids in
                selectedWorkouts = workouts.filter { ids.contains($0.id) }
                dismiss()
            }, cancel: { dismiss() }, feedback: { Haptics.light() })
    }
}

struct CutPostComposePartnerPickerHost: View {
    let friends: [Friend]
    @Binding var selectedPartner: Friend?
    let isLoading: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        CutPostComposePartnerPickerView(friends: friends.map(CutPostComposeHost.partnerFacts), selectedID: selectedPartner?.id,
            isLoading: isLoading, select: { id in
                selectedPartner = friends.first { $0.id == id }
                dismiss()
            }, cancel: { dismiss() })
    }
}
