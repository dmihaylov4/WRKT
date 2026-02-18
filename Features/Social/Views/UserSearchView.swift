import SwiftUI
import Kingfisher

struct UserSearchView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: UserSearchViewModel?
    @State private var selectedUserId: UUID?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = UserSearchViewModel(
                    authService: deps.authService,
                    friendshipRepository: deps.friendshipRepository
                )
            }
        }
        .navigationDestination(item: $selectedUserId) { userId in
            SocialProfileView(userId: userId)
        }
    }

    @ViewBuilder
    private func content(viewModel: UserSearchViewModel) -> some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBar(viewModel: viewModel)

            // Results
            if viewModel.isSearching {
                searchingState()
            } else if let error = viewModel.error {
                errorState(error: error)
            } else if viewModel.searchQuery.isEmpty {
                emptySearchState()
            } else if viewModel.searchResults.isEmpty {
                noResultsState()
            } else {
                resultsList(viewModel: viewModel)
            }
        }
    }

    private func searchBar(viewModel: UserSearchViewModel) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.Semantic.textSecondary)

            TextField("Search by username...", text: Binding(
                get: { viewModel.searchQuery },
                set: { newValue in
                    viewModel.searchQuery = newValue
                    viewModel.performSearch()
                }
            ))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
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

    private func searchingState() -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptySearchState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("Search for friends")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Enter a username to find people")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noResultsState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("No users found")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Try a different username")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsList(viewModel: UserSearchViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { profile in
                    UserSearchResultRow(profile: profile)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUserId = profile.id
                        }

                    if profile.id != viewModel.searchResults.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
    }
}

struct UserSearchResultRow: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 16) {
            // Hexagonal Avatar
            KFImage(URL(string: profile.avatarUrl ?? ""))
                .placeholder {
                    Hexagon()
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(profile.username.prefix(1).uppercased())
                                .font(.title3.bold())
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
                if let displayName = profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    Text("@\(profile.username)")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .padding()
    }
}

// Helper to make UUID optional identifiable
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
