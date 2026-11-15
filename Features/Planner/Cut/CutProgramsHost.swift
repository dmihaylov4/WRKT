//
//  CutProgramsHost.swift
//  WRKT
//
//  Feeds CutProgramsView from ProgramLibraryViewModel with the same loading, realtime, refresh
//  triggers, sheets and destinations as ProgramLibraryView. Only the presentation differs.
//

import SwiftUI

struct CutProgramsHost: View {
    @Binding var pendingNotification: AppNotification?
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ProgramLibraryViewModel?
    @State private var shareSplitID: UUID?
    @State private var sentSplitID: UUID?
    @State private var previewInvite: CutProgramInviteDestination?
    @State private var setup: PlannerSetupCarouselView.LaunchMode?
    @State private var confirmingClear = false

    var body: some View {
        CutProgramsView(model: model, actions: actions, confirmingClear: $confirmingClear)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                viewModel?.refreshLibrary()
                await viewModel?.refreshPendingInvites()
            }
            .task {
                await configureViewModelIfNeeded()
                await viewModel?.startRealtime()
                await viewModel?.refreshPendingInvites()
                viewModel?.refreshLibrary()
                consumePendingNotification()
            }
            .onChange(of: pendingNotification) { _, _ in consumePendingNotification() }
            .onReceive(NotificationCenter.default.publisher(for: .plannedWorkoutsChanged)) { _ in
                viewModel?.refreshLibrary()
            }
            .navigationDestination(item: $setup) { mode in
                PlannerSetupCarouselView(launchMode: mode)
            }
            .navigationDestination(item: $previewInvite) { item in
                ProgramPreviewView(inviteID: item.id, onChanged: {
                    viewModel?.refreshLibrary()
                    await viewModel?.refreshPendingInvites()
                })
                .environment(\.dependencies, deps)
            }
            .sheet(item: shareBinding) { item in
                NavigationStack {
                    CutProgramShareHost(split: item.split, currentUserID: item.userID, currentUsername: item.username,
                                        currentDisplayName: item.displayName) {
                        viewModel?.refreshLibrary()
                        sentSplitID = item.split.id
                    }
                }
                .environment(\.dependencies, deps)
            }
            .sheet(item: sentBinding) { item in
                NavigationStack { CutSentInvitesHost(split: item.split) }
                    .environment(\.dependencies, deps)
            }
            .alert("Program Error", isPresented: Binding(
                get: { viewModel?.errorMessage != nil },
                set: { if !$0 { viewModel?.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel?.errorMessage ?? "Something went wrong.")
            }
    }

    private var model: CutProgramsModel {
        guard let viewModel else { return CutProgramsLogic.model(library: [], invites: [], loading: true) }
        return CutProgramsLogic.model(
            library: viewModel.library.map(CutProgramFacts.init),
            invites: viewModel.pendingInvites.map {
                CutProgramInviteFacts(id: $0.id, programName: $0.programName, senderDisplayName: $0.senderDisplayName, senderUsername: $0.senderUsername)
            }
        )
    }

    private var actions: CutProgramsActions {
        CutProgramsActions(
            back: { dismiss() },
            new: { setup = .create },
            edit: { setup = .editCurrent },
            share: { shareSplitID = $0 },
            sentInvites: { id in
                guard split(id)?.lastSharedProgramID != nil else { return }
                sentSplitID = id
            },
            clearPlan: { viewModel?.deleteAllPlannedWorkouts() },
            use: { id in
                guard let split = split(id) else { return }
                Haptics.light()
                viewModel?.activate(split)
            },
            openInvite: { previewInvite = .init(id: $0) }
        )
    }

    private func split(_ id: UUID) -> WorkoutSplit? {
        viewModel?.library.first { $0.id == id } ?? (viewModel?.activeSplit?.id == id ? viewModel?.activeSplit : nil)
    }

    private func configureViewModelIfNeeded() async {
        guard viewModel == nil, let currentUserID = deps.authService.currentUser?.id else { return }
        viewModel = ProgramLibraryViewModel(
            repo: deps.programSharingRepository,
            plannerStore: deps.plannerStore,
            currentUserID: currentUserID,
            realtime: deps.realtimeService,
            profileRepo: deps.profileRepository
        )
        viewModel?.refreshLibrary()
        await viewModel?.refreshPendingInvites()
    }

    private func consumePendingNotification() {
        guard pendingNotification?.type == .programInvite else { return }
        previewInvite = pendingNotification?.targetId.map { CutProgramInviteDestination(id: $0) }
        pendingNotification = nil
    }

    private var shareBinding: Binding<CutProgramShareItem?> {
        Binding(
            get: {
                guard let shareSplitID, let user = deps.authService.currentUser, let split = split(shareSplitID) else { return nil }
                return CutProgramShareItem(split: split, userID: user.id, username: user.profile?.username, displayName: user.profile?.displayName)
            },
            set: { shareSplitID = $0?.split.id }
        )
    }

    private var sentBinding: Binding<CutProgramSplitItem?> {
        Binding(
            get: { sentSplitID.flatMap { id in viewModel?.library.first { $0.id == id } }.map(CutProgramSplitItem.init) },
            set: { sentSplitID = $0?.split.id }
        )
    }
}

struct CutProgramInviteDestination: Hashable, Identifiable {
    let id: UUID
}

private struct CutProgramShareItem: Identifiable {
    let split: WorkoutSplit
    let userID: UUID
    let username: String?
    let displayName: String?
    var id: UUID { split.id }
}

private struct CutProgramSplitItem: Identifiable {
    let split: WorkoutSplit
    var id: UUID { split.id }
}

extension CutProgramFacts {
    init(_ split: WorkoutSplit) {
        self.init(
            id: split.id,
            name: split.name,
            isActive: split.isActive,
            days: split.orderedPlanBlocks.map { $0.isRestDay ? nil : $0.exercises.count },
            creatorName: CutProgramsLogic.creatorName(displayName: split.creatorDisplayName, username: split.creatorUsername),
            hasBeenShared: split.lastSharedProgramID != nil
        )
    }
}
