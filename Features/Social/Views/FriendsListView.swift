import SwiftUI
import Kingfisher

struct FriendsListView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: FriendsListViewModel?
    @State private var selectedUserId: UUID?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = FriendsListViewModel(
                    friendshipRepository: deps.friendshipRepository,
                    authService: deps.authService
                )
                await viewModel?.loadFriends()
            }
        }
        .refreshable {
            await viewModel?.loadFriends()
        }
        .navigationDestination(item: $selectedUserId) { userId in
            SocialProfileView(userId: userId)
        }
    }

    @ViewBuilder
    private func content(viewModel: FriendsListViewModel) -> some View {
        VStack(spacing: 0) {
            // Search Bar
            if !viewModel.friends.isEmpty {
                searchBar(viewModel: viewModel)
            }

            // Content
            if viewModel.isLoading {
                loadingState()
            } else if let error = viewModel.error {
                errorState(error: error, viewModel: viewModel)
            } else if viewModel.friends.isEmpty {
                emptyState()
            } else if viewModel.filteredFriends.isEmpty {
                noResultsState()
            } else {
                friendsList(viewModel: viewModel)
            }
        }
    }

    private func searchBar(viewModel: FriendsListViewModel) -> some View {
        FriendPickerSearchBar(searchText: Binding(
            get: { viewModel.searchQuery },
            set: { newValue in
                viewModel.searchQuery = newValue
                viewModel.filterFriends()
            }
        ))
    }

    private func loadingState() -> some View {
        FriendsLoadingState()
    }

    private func errorState(error: String, viewModel: FriendsListViewModel) -> some View {
        FriendsErrorState(message: error) {
            Task {
                await viewModel.loadFriends()
            }
        }
    }

    private func emptyState() -> some View {
        FriendsEmptyState()
    }

    private func noResultsState() -> some View {
        FriendsNoResultsState(searchQuery: viewModel?.searchQuery ?? "")
    }

    private func friendsList(viewModel: FriendsListViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredFriends) { friend in
                    FriendRow(friend: friend)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUserId = friend.profile.id
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.removeFriend(friend)

                                UndoToastManager.shared.show(
                                    message: "Removed @\(friend.profile.username)",
                                    undoAction: {
                                        viewModel.undoRemove(friend)
                                    }
                                )
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "person.fill.xmark")
                                        .dsFont(.title2)
                                        .foregroundStyle(DS.Palette.marone)
                                    Text("Remove")
                                        .dsFont(.caption2, weight: .semibold)
                                        .foregroundStyle(DS.Palette.marone)
                                }
                            }
                            .tint(.black)
                        }

                    if friend.id != viewModel.filteredFriends.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
    }
}

struct FriendPickerSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.Semantic.textSecondary)

            TextField("Search friends...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
        }
        .padding()
        .background(DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

struct FriendsLoadingState: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading friends...")
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FriendsErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(message)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FriendsEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("No friends yet")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Find people and send friend requests to connect")
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                UserSearchView()
            } label: {
                Text("Find Friends")
                    .dsFont(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DS.Palette.marone)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FriendsNoResultsState: View {
    let searchQuery: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("No results")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("No friends match '\(searchQuery)'")
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SelectableFriendRow: View {
    let friend: Friend
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FriendRow(friend: friend)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? Text("Selected") : Text(""))
    }
}

struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 16) {
            // Hexagonal Avatar
            KFImage(URL(string: friend.profile.avatarUrl ?? ""))
                .placeholder {
                    Hexagon()
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(friend.profile.username.prefix(1).uppercased())
                                .dsFont(.title3, weight: .bold)
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(Hexagon())

            // User Info
            VStack(alignment: .leading, spacing: 4) {
                if let displayName = friend.profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("@\(friend.profile.username)")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    Text("@\(friend.profile.username)")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Text(friend.friendsSinceText)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .padding()
    }
}
