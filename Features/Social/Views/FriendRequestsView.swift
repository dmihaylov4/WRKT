import SwiftUI
import Kingfisher

struct FriendRequestsView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: FriendRequestsViewModel?
    @State private var selectedTab: RequestTab = .incoming
    @State private var selectedUserId: UUID?

    enum RequestTab: String, CaseIterable {
        case incoming = "Requests"
        case outgoing = "Sent"
    }

    var body: some View {
        Group {
            if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Friend Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = FriendRequestsViewModel(
                    friendshipRepository: deps.friendshipRepository,
                    authService: deps.authService
                )
                await viewModel?.loadRequests()
            }
        }
        .refreshable {
            await viewModel?.loadRequests()
        }
        .navigationDestination(item: $selectedUserId) { userId in
            SocialProfileView(userId: userId)
        }
    }

    @ViewBuilder
    private func content(viewModel: FriendRequestsViewModel) -> some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("Type", selection: $selectedTab) {
                ForEach(RequestTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Error Banner
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.error = nil
                    }
                    .font(.caption.bold())
                }
                .padding()
                .background(.red.opacity(0.1))
            }

            // Content
            if viewModel.isLoading {
                loadingState()
            } else {
                TabView(selection: $selectedTab) {
                    incomingRequestsList(viewModel: viewModel)
                        .tag(RequestTab.incoming)

                    outgoingRequestsList(viewModel: viewModel)
                        .tag(RequestTab.outgoing)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private func loadingState() -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading requests...")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func incomingRequestsList(viewModel: FriendRequestsViewModel) -> some View {
        if viewModel.incomingRequests.isEmpty {
            emptyIncomingState()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.incomingRequests) { request in
                        IncomingRequestRow(
                            request: request,
                            onAccept: {
                                Task {
                                    await viewModel.acceptRequest(request)
                                }
                            },
                            onReject: {
                                Task {
                                    await viewModel.rejectRequest(request)
                                }
                            },
                            onTap: {
                                selectedUserId = request.profile.id
                            }
                        )

                        if request.id != viewModel.incomingRequests.last?.id {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func outgoingRequestsList(viewModel: FriendRequestsViewModel) -> some View {
        if viewModel.outgoingRequests.isEmpty {
            emptyOutgoingState()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.outgoingRequests) { request in
                        OutgoingRequestRow(
                            request: request,
                            onCancel: {
                                Task {
                                    await viewModel.cancelRequest(request)
                                }
                            },
                            onTap: {
                                selectedUserId = request.profile.id
                            }
                        )

                        if request.id != viewModel.outgoingRequests.last?.id {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
            }
        }
    }

    private func emptyIncomingState() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("No friend requests")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("You don't have any pending friend requests")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyOutgoingState() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "paperplane")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("No outgoing requests")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("You haven't sent any friend requests")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                UserSearchView()
            } label: {
                Text("Find Friends")
                    .font(.headline)
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

// MARK: - Incoming Request Row

struct IncomingRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onReject: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Hexagonal Avatar (tappable)
            Button(action: onTap) {
                KFImage(URL(string: request.profile.avatarUrl ?? ""))
                    .placeholder {
                        Hexagon()
                            .fill(DS.Semantic.brandSoft)
                            .overlay(
                                Text(request.profile.username.prefix(1).uppercased())
                                    .font(.title3.bold())
                                    .foregroundStyle(DS.Semantic.brand)
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Hexagon())
            }
            .buttonStyle(.plain)

            // User Info (tappable)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    if let displayName = request.profile.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text("@\(request.profile.username)")
                            .font(.subheadline)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    } else {
                        Text("@\(request.profile.username)")
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Action Buttons (hexagonal)
            HStack(spacing: 8) {
                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(DS.Semantic.fillSubtle)
                        .clipShape(Hexagon())
                }

                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(DS.Palette.marone)
                        .clipShape(Hexagon())
                }
            }
        }
        .padding()
    }
}

// MARK: - Outgoing Request Row

struct OutgoingRequestRow: View {
    let request: FriendRequest
    let onCancel: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Hexagonal Avatar (tappable)
            Button(action: onTap) {
                KFImage(URL(string: request.profile.avatarUrl ?? ""))
                    .placeholder {
                        Hexagon()
                            .fill(DS.Semantic.brandSoft)
                            .overlay(
                                Text(request.profile.username.prefix(1).uppercased())
                                    .font(.title3.bold())
                                    .foregroundStyle(DS.Semantic.brand)
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Hexagon())
            }
            .buttonStyle(.plain)

            // User Info (tappable)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    if let displayName = request.profile.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text("@\(request.profile.username)")
                            .font(.subheadline)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    } else {
                        Text("@\(request.profile.username)")
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    Text("Request pending")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Cancel Button
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }
}
