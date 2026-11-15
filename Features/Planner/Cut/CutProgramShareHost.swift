//
//  CutProgramShareHost.swift
//  WRKT
//
//  Wires the share sheet to ProgramShareViewModel and the friends request the legacy picker made.
//  Same send, same result alert, same completion as ProgramShareSheet.
//

import SwiftUI

struct CutProgramShareHost: View {
    let split: WorkoutSplit
    let currentUserID: UUID
    let currentUsername: String?
    let currentDisplayName: String?
    let onComplete: () -> Void

    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProgramShareViewModel?
    @State private var friends = CutFriendsLoader()
    @State private var picking = false
    @State private var showResult = false

    var body: some View {
        CutProgramShareView(
            model: CutProgramShareLogic.model(
                programName: split.name,
                friends: friends.friends.map { CutBattleOpponent($0.profile) },
                selected: (viewModel?.selectedFriends ?? []).map(CutBattleOpponent.init),
                loading: friends.loading,
                loadError: friends.error,
                sending: viewModel?.isSending ?? false,
                sendError: showResult ? nil : viewModel?.errorMessage
            ),
            note: Binding(get: { viewModel?.descriptionText ?? "" }, set: { viewModel?.descriptionText = $0 }),
            toggle: toggle,
            openAll: { picking = true },
            retry: { Task { await friends.load(deps) } },
            send: { Task { await send() } },
            close: { dismiss() }
        )
        .sheet(isPresented: $picking) {
            NavigationStack {
                CutProgramFriendsHost(loader: friends, selected: Binding(
                    get: { viewModel?.selectedFriends ?? [] },
                    set: { viewModel?.selectedFriends = $0 }
                ))
            }
            .environment(\.dependencies, deps)
        }
        .alert("Share Result", isPresented: $showResult) {
            Button("Done") {
                dismiss()
                onComplete()
            }
        } message: {
            if let result = viewModel?.lastResult {
                Text(CutProgramShareLogic.resultMessage(sent: result.succeeded.count, failed: result.failed.count))
            } else {
                Text(viewModel?.errorMessage ?? "Unable to share this program.")
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ProgramShareViewModel(repo: deps.programSharingRepository, plannerStore: deps.plannerStore)
            }
            if !friends.started { await friends.load(deps) }
        }
    }

    private func toggle(_ id: UUID) {
        guard let friend = friends.friends.first(where: { $0.profile.id == id })?.profile
                ?? viewModel?.selectedFriends.first(where: { $0.id == id }) else { return }
        Haptics.light()
        viewModel?.toggleFriend(friend)
    }

    private func send() async {
        guard let viewModel, !viewModel.isSending else { return }
        let didSend = await viewModel.send(split: split, currentUserID: currentUserID,
                                           currentUsername: currentUsername, currentDisplayName: currentDisplayName)
        showResult = didSend
    }
}

/// The all-friends sheet, stacked on the share sheet; it shares the share sheet's friends request.
struct CutProgramFriendsHost: View {
    let loader: CutFriendsLoader
    @Binding var selected: [UserProfile]
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        CutProgramFriendsView(
            model: CutProgramShareLogic.friends(loader.friends.map { CutBattleOpponent($0.profile) }, query: query,
                                                selected: selected.map(CutBattleOpponent.init), loading: loader.loading, error: loader.error),
            query: $query,
            toggle: { id in
                guard let profile = loader.friends.first(where: { $0.profile.id == id })?.profile else { return }
                Haptics.light()
                if let index = selected.firstIndex(where: { $0.id == id }) { selected.remove(at: index) } else { selected.append(profile) }
            },
            retry: { Task { await loader.load(deps) } },
            close: { dismiss() }
        )
        .task { if !loader.started { await loader.load(deps) } }
    }
}
