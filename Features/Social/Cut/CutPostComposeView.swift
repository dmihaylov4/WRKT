import SwiftUI

struct CutPostComposeActions {
    var cancel: () -> Void = {}
    var share: () -> Void = {}
    var chooseWorkouts: () -> Void = {}
    var choosePartner: () -> Void = {}
    var removePhoto: (Int) -> Void = { _ in }
    var togglePrivacy: (Int) -> Void = { _ in }
    var retry: () -> Void = {}
    var dismissError: () -> Void = {}
    var feedback: () -> Void = {}
}

struct CutPostComposeView<PhotoPicker: View>: View {
    let model: CutPostComposeModel
    @Binding var caption: String
    @Binding var visibility: PostVisibility
    var actions = CutPostComposeActions()
    var image: (CutPostComposeModel.Photo) -> Image? = { _ in nil }
    @ViewBuilder var photoPicker: () -> PhotoPicker
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: actions.cancel).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                Spacer(minLength: 12)
                if !model.isInitializing {
                    Button("Share", action: actions.share).buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
                        .disabled(!model.canShare)
                }
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(model.title.uppercased()).font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    if model.isInitializing { ProgressView().accessibilityLabel("Loading post editor") }
                    else {
                        workoutSection
                        if model.showsPartner { partnerSection }
                        section("Caption") {
                            TextField("Share your thoughts...", text: $caption,
                                      prompt: Text("Share your thoughts...").foregroundStyle(DS.Cut.Colors.textSecondary), axis: .vertical)
                                .cutFont(.body).lineLimit(5...10).textFieldStyle(.plain).tint(DS.Cut.Colors.lime)
                            CutHairline()
                        }
                        photoSection
                        section("Visibility") {
                            ForEach([PostVisibility.publicPost, .friends, .privatePost], id: \.self) { value in
                                Button { visibility = value; actions.feedback() } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: value.icon).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(value.displayName).cutFont(.title)
                                            Text(CutPostComposeLogic.visibilityDescription(value)).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        if visibility == value { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) }
                                    }.padding(.vertical, 10).frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(visibility == value ? .isSelected : [])
                                CutHairline()
                            }
                        }
                        if let error = model.errorMessage, model.workoutState == .selected {
                            VStack(alignment: .leading, spacing: 12) {
                                if let title = model.errorTitle { Text(title).cutFont(.title) }
                                Text(error).cutFont(.body)
                                HStack(spacing: 12) {
                                    if model.errorIsRetryable { Button("Retry", action: actions.retry).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false)) }
                                    Button("Dismiss", action: actions.dismissError).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                                }
                            }
                        }
                    }
                }.padding(DS.Cut.Metrics.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if let overlay = model.overlay {
                    ZStack {
                        DS.Cut.Colors.background.opacity(0.94)
                        VStack(spacing: 16) { ProgressView(); Text(overlay).cutFont(.body) }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
    private var workoutSection: some View {
        section(model.weeklyStats.isEmpty ? (model.workouts.count > 1 ? "Session" : "Workout") : "Weekly Progress") {
            if !model.weeklyStats.isEmpty {
                Button("Change", action: actions.chooseWorkouts).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                ForEach(Array(model.weeklyStats.enumerated()), id: \.offset) { _, stats in CutStatColumns(stats) }
                if let streak = model.superStreak { Text(streak).cutFont(.body).foregroundStyle(DS.Cut.Colors.lime) }
                if let hint = model.sessionHint { Text(hint).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
            } else {
                switch model.workoutState {
                case .loading: ProgressView().accessibilityLabel("Loading workouts")
                case .empty:
                    Text("No workouts yet").cutFont(.title)
                    Text("Complete a workout to share it").cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                case .choose:
                    Text("Select a workout").cutFont(.title)
                    Text("Choose from your recent workouts").cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                    Button("Choose Workout", action: actions.chooseWorkouts).buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                case .selected:
                    Button("Change", action: actions.chooseWorkouts).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                    ForEach(model.workouts) { workout in CutPostComposeWorkoutRow(workout: workout) }
                }
            }
        }
    }
    private var partnerSection: some View {
        section("Partner") {
            Button(action: actions.choosePartner) {
                HStack(spacing: 12) {
                    if let partner = model.partner {
                        CutSocialAvatar(initials: partner.initials, url: partner.avatarURL, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(partner.name).cutFont(.title)
                            Text("Shared post").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tag a workout partner").cutFont(.title)
                            Text("Optional").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if model.isLoadingFriends { ProgressView() } else { Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)) }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.isLoadingFriends)
            CutHairline()
        }
    }
    private var photoSection: some View {
        section("Photos") {
            photoPicker()
            if model.photos.isEmpty {
                Text("No photos selected").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(model.photos) { photo in
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        if let image = image(photo) { image.resizable().scaledToFill() }
                                        else { Rectangle().fill(DS.Cut.Colors.controlFill).overlay(Image(systemName: "photo")) }
                                    }
                                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 260 : 140, height: 140).clipped()
                                    .accessibilityLabel(photo.kind == .attached ? "Attached picture" : photo.kind == .map ? "Map" : "Selected photo")
                                    if photo.canRemove, case .picked(let index) = photo.kind {
                                        Button("Remove photo", systemImage: "xmark") { actions.removePhoto(index) }
                                            .labelStyle(.iconOnly).buttonStyle(CutIconButtonStyle(tone: .outline, diameter: 44)).background(.black)
                                    }
                                }
                                if case .picked(let index) = photo.kind, let privacy = photo.privacy {
                                    Button(privacy ? "Public" : "Private", systemImage: privacy ? "eye" : "eye.slash") { actions.togglePrivacy(index) }
                                        .cutFont(.secondary).frame(minHeight: 44).buttonStyle(.plain)
                                } else if photo.kind == .map { Text("Map").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { CutSectionTitle(title); CutHairline(); content() }
    }
}

/// The same value-only row is used in the selection sheet and the selected-workout preview.
private struct CutPostComposeWorkoutRow: View {
    let workout: CutPostComposeModel.Workout
    var selected = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Label(workout.title, systemImage: workout.icon).cutFont(.title).frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) }
            }
            Text(workout.date).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            Text(workout.stats).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            CutHairline()
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}

struct CutPostComposeWorkoutPickerView: View {
    let workouts: [CutPostComposeModel.Workout]
    let selectedIDs: [UUID]
    var done: ([UUID]) -> Void = { _ in }
    var cancel: () -> Void = {}
    var feedback: () -> Void = {}
    @State private var pending: Set<UUID> = []
    @State private var contentHeight: CGFloat = 300
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Cancel", action: cancel).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                    Spacer(minLength: 12)
                    Button("Done (\(pending.count))") { done(CutPostComposeLogic.committedSelection(availableIDs: workouts.map(\.id), pending: pending)) }
                        .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
                        .disabled(!CutPostComposeLogic.canFinishSelection(pending))
                }
                Text("SELECT WORKOUTS").font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                ForEach(workouts) { workout in
                    Button { pending = CutPostComposeLogic.toggledSelection(pending, id: workout.id); feedback() } label: {
                        CutPostComposeWorkoutRow(workout: workout, selected: pending.contains(workout.id))
                    }.buttonStyle(.plain).accessibilityAddTraits(pending.contains(workout.id) ? .isSelected : [])
                }
            }.padding(DS.Cut.Metrics.gutter)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .onAppear { pending = Set(selectedIDs) }
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(min(640, max(240, contentHeight + 24))), .large])
        .presentationDragIndicator(.visible).shellPresentationBackground(DS.Cut.Colors.background)
    }
}

struct CutPostComposePartnerPickerView: View {
    let friends: [CutPostComposeModel.Partner]
    let selectedID: UUID?
    var isLoading = false
    var select: (UUID?) -> Void = { _ in }
    var cancel: () -> Void = {}
    @State private var contentHeight: CGFloat = 260
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Button("Cancel", action: cancel).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                Text("TAG PARTNER").font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                if isLoading { ProgressView().accessibilityLabel("Loading friends") }
                else if friends.isEmpty { Text("No friends yet").cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary) }
                else {
                    Button { select(nil) } label: {
                        HStack { Text("No partner").cutFont(.body); Spacer(); if selectedID == nil { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) } }
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    CutHairline()
                    ForEach(friends) { friend in
                        Button { select(friend.id) } label: {
                            HStack(spacing: 12) {
                                CutSocialAvatar(initials: friend.initials, url: friend.avatarURL, size: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(friend.name).cutFont(.title)
                                    Text(friend.handle).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if selectedID == friend.id { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) }
                            }.padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(selectedID == friend.id ? .isSelected : [])
                        CutHairline()
                    }
                }
            }.padding(DS.Cut.Metrics.gutter)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(min(640, max(240, contentHeight + 24))), .large])
        .presentationDragIndicator(.visible).shellPresentationBackground(DS.Cut.Colors.background)
    }
}
