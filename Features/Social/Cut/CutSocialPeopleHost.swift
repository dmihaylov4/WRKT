//
//  CutSocialPeopleHost.swift
//  WRKT
//
//  Feeds the Cut Activity, Friend requests, My friends and Find friends screens from the view
//  models the legacy screens already use. Same loads, actions, undo, refresh and destinations;
//  only the presentation differs.
//

import SwiftUI

// MARK: - Activity

/// ActivityFeedView's data and flows: load on open, then mark everything read and clear the
/// badge, as the legacy list does.
struct CutActivityHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: ActivityFeedViewModel?
    @State private var destination: CutSocialPeopleLogic.ActivityDestination?

    var body: some View {
        CutActivityView(model: model, actions: actions)
            .navigationTitle(Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .profile(let userId):
                    SocialProfileView(userId: userId).environment(\.dependencies, deps)
                case .post(let postId):
                    PostLoaderView(postId: postId).environment(\.dependencies, deps)
                case .battle(let battleId):
                    BattleLoaderView(battleId: battleId).environment(\.dependencies, deps)
                case .challenge(let challengeId):
                    ChallengeLoaderView(challengeId: challengeId).environment(\.dependencies, deps)
                case .missing(let message):
                    Text(message).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                case .programInvite(let inviteId):
                    ProgramPreviewView(inviteID: inviteId, bottomActionPadding: 72).environment(\.dependencies, deps)
                }
            }
            .task {
                if viewModel == nil {
                    let vm = ActivityFeedViewModel(
                        notificationRepository: deps.notificationRepository,
                        authService: deps.authService,
                        realtimeService: deps.realtimeService
                    )
                    viewModel = vm
                }
                guard let vm = viewModel else { return }
                // Returning from a destination resumes the subscription torn down on disappear.
                await vm.loadNotifications()
                await vm.subscribeToRealtimeUpdates()
                if vm.notifications.contains(where: { !$0.read }) {
                    await vm.markAllAsRead()
                    NotificationBadgeManager.shared.notificationCount = 0
                }
            }
            .onDisappear {
                if let vm = viewModel {
                    Task { [weak vm] in await vm?.cleanup() }
                }
            }
    }

    private var model: CutActivityModel {
        guard let vm = viewModel else { return CutActivityModel(content: .loading) }
        let facts = vm.notifications.map { item in
            CutActivityFacts(id: item.id, type: item.type, actorId: item.actor.id,
                             actorName: item.actor.displayName ?? item.actor.username, actorAvatarURL: item.actor.avatarUrl,
                             message: item.message, targetId: item.targetId, createdAt: item.createdAt, read: item.read)
        }
        return CutSocialPeopleLogic.activity(facts, isLoading: vm.isLoading, error: vm.error?.message, now: .now)
    }

    private var actions: CutActivityActions {
        func item(_ id: UUID) -> NotificationWithActor? { viewModel?.notifications.first { $0.id == id } }
        return CutActivityActions(
            refresh: { await viewModel?.loadNotifications() },
            retry: { Task { await viewModel?.loadNotifications() } },
            dismissError: { viewModel?.error = nil },
            open: { id in
                guard let item = item(id) else { return }
                destination = CutSocialPeopleLogic.destination(type: item.type, actorId: item.actor.id, targetId: item.targetId)
            },
            markRead: { id in
                guard let vm = viewModel, let item = item(id) else { return }
                Task { await vm.markAsRead(item) }
            },
            delete: { id in
                guard let vm = viewModel, let item = item(id) else { return }
                Task { await vm.deleteNotification(item) }
            },
            markAllRead: { Task { await viewModel?.markAllAsRead() } },
            clearAll: { Task { await viewModel?.clearAllNotifications() } }
        )
    }
}

// MARK: - Friend requests

struct CutFriendRequestsHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: FriendRequestsViewModel?
    @State private var tab: CutFriendRequestsModel.Tab = .incoming
    @State private var selectedUserId: UUID?
    @State private var showingSearch = false

    var body: some View {
        CutFriendRequestsView(model: model, actions: actions)
            .navigationTitle(Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel == nil {
                    viewModel = FriendRequestsViewModel(friendshipRepository: deps.friendshipRepository, authService: deps.authService)
                    await viewModel?.loadRequests()
                }
            }
            .navigationDestination(item: $selectedUserId) { userId in
                SocialProfileView(userId: userId)
            }
            .navigationDestination(isPresented: $showingSearch) {
                UserSearchView()
            }
    }

    private var model: CutFriendRequestsModel {
        let vm = viewModel
        let loaded = vm.map { !$0.isLoading } ?? false
        func facts(_ requests: [FriendRequest]) -> [CutFriendRequestFacts] {
            requests.map {
                CutFriendRequestFacts(id: $0.id, person: Self.person($0.profile), needsReconfirmation: $0.friendship.requiresReconfirmation, statusText: $0.statusText)
            }
        }
        return CutSocialPeopleLogic.requests(
            incoming: loaded ? vm.map { facts($0.incomingRequests) } : nil,
            outgoing: loaded ? vm.map { facts($0.outgoingRequests) } : nil,
            tab: tab,
            isLoading: vm?.isLoading ?? true,
            error: vm?.error
        )
    }

    private var actions: CutFriendRequestsActions {
        func incoming(_ id: UUID) -> FriendRequest? { viewModel?.incomingRequests.first { $0.id == id } }
        return CutFriendRequestsActions(
            refresh: { await viewModel?.loadRequests() },
            select: { tab = $0 },
            retry: { Task { await viewModel?.loadRequests() } },
            dismissError: { viewModel?.error = nil },
            openProfile: { selectedUserId = $0 },
            accept: { id in
                guard let vm = viewModel, let request = incoming(id) else { return }
                Task { await vm.acceptRequest(request) }
            },
            decline: { id in
                guard let vm = viewModel, let request = incoming(id) else { return }
                Task { await vm.rejectRequest(request) }
            },
            cancel: { id in
                guard let vm = viewModel, let request = vm.outgoingRequests.first(where: { $0.id == id }) else { return }
                Task { await vm.cancelRequest(request) }
            },
            findFriends: { showingSearch = true }
        )
    }

    static func person(_ profile: UserProfile) -> CutSocialPersonFacts {
        .init(id: profile.id, username: profile.username, displayName: profile.displayName, avatarURL: profile.avatarUrl, bio: profile.bio)
    }
}

// MARK: - Friends

/// FriendsListView's data: search filters locally, removal is optimistic with the same undo toast.
struct CutFriendsListHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: FriendsListViewModel?
    @State private var selectedUserId: UUID?
    @State private var showingSearch = false

    var body: some View {
        CutFriendsListView(
            model: model,
            query: Binding(
                get: { viewModel?.searchQuery ?? "" },
                set: { newValue in
                    viewModel?.searchQuery = newValue
                    viewModel?.filterFriends()
                }
            ),
            actions: CutFriendsListActions(
                refresh: { await viewModel?.loadFriends() },
                retry: { Task { await viewModel?.loadFriends() } },
                dismissError: { viewModel?.error = nil },
                open: { id in selectedUserId = viewModel?.friends.first { $0.id == id }?.profile.id },
                remove: { id in
                    guard let vm = viewModel, let friend = vm.friends.first(where: { $0.id == id }) else { return }
                    vm.removeFriend(friend)
                    UndoToastManager.shared.show(message: "Removed @\(friend.profile.username)", undoAction: {
                        vm.undoRemove(friend)
                    })
                },
                findFriends: { showingSearch = true }
            )
        )
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = FriendsListViewModel(friendshipRepository: deps.friendshipRepository, authService: deps.authService)
                await viewModel?.loadFriends()
            }
        }
        .navigationDestination(item: $selectedUserId) { userId in
            SocialProfileView(userId: userId)
        }
        .navigationDestination(isPresented: $showingSearch) {
            UserSearchView()
        }
    }

    private var model: CutFriendsListModel {
        guard let vm = viewModel else { return CutFriendsListModel(content: .loading, showsSearch: false) }
        let friends = vm.friends.map {
            CutFriendFacts(id: $0.id, person: CutFriendRequestsHost.person($0.profile), friendsSince: $0.friendsSince)
        }
        return CutSocialPeopleLogic.friends(friends, query: vm.searchQuery, isLoading: vm.isLoading, error: vm.error)
    }
}

// MARK: - Find friends

/// UserSearchView's debounced username search; a result opens the profile, where the friend
/// request lives.
struct CutUserSearchHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: UserSearchViewModel?
    @State private var selectedUserId: UUID?

    var body: some View {
        CutUserSearchView(
            model: model,
            query: Binding(
                get: { viewModel?.searchQuery ?? "" },
                set: { newValue in
                    viewModel?.searchQuery = newValue
                    viewModel?.performSearch()
                }
            ),
            open: { selectedUserId = $0 }
        )
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = UserSearchViewModel(authService: deps.authService, friendshipRepository: deps.friendshipRepository)
            }
        }
        .navigationDestination(item: $selectedUserId) { userId in
            SocialProfileView(userId: userId)
        }
    }

    private var model: CutUserSearchModel {
        guard let vm = viewModel else { return CutUserSearchModel(content: .idle) }
        return CutSocialPeopleLogic.search(query: vm.searchQuery, results: vm.searchResults.map(CutFriendRequestsHost.person),
                                           isSearching: vm.isSearching, error: vm.error)
    }
}
