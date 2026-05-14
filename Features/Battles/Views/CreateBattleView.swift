//
//  CreateBattleView.swift
//  WRKT
//
//  Create a new battle with a friend
//

import SwiftUI

struct CreateBattleView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: BattleViewModel

    @State private var selectedFriend: UserProfile?
    @State private var selectedBattleType: BattleType = .volume
    @State private var duration: Int = 7 // days
    @State private var showFriendPicker = false

    let durationOptions = [3, 7, 14, 30]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 10) {
                        headerSection
                        opponentSection
                        battleTypeSection
                        BattleRewardPreviewBlock(battleType: selectedBattleType)
                        durationSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                createBattleButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showFriendPicker) {
                FriendPickerView(selectedFriend: $selectedFriend)
            }
        }
    }

    // MARK: - View Components

    private var canCreateBattle: Bool {
        selectedFriend != nil
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Semantic.brand)
                    .frame(width: 96, height: 46)
                    .background(DS.Semantic.card.opacity(0.72), in: ChamferedRectangleAlt(.large))
                    .overlay(
                        ChamferedRectangleAlt(.large)
                            .stroke(DS.Semantic.border.opacity(0.55), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Create Battle")
                .dsFont(.headline, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            Button {
                Task { await createBattle() }
            } label: {
                Text("Create")
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(canCreateBattle ? DS.Semantic.brand : DS.Semantic.textSecondary)
                    .frame(width: 96, height: 46)
                    .background(DS.Semantic.card.opacity(0.72), in: ChamferedRectangle(.large))
                    .overlay(
                        ChamferedRectangle(.large)
                            .stroke(DS.Semantic.border.opacity(0.55), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canCreateBattle)
        }
        .frame(height: 48)
    }

    private var headerSection: some View {
        VStack(spacing: 5) {
            BattleAssetIcon(
                asset: "battle-flags-icon",
                size: 40,
                color: DS.Semantic.brand
            )

            Text("Start a Battle")
                .dsFont(.title2, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Challenge a friend and compete!")
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var opponentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("OPPONENT")
            opponentButton
        }
    }

    private var opponentButton: some View {
        Button {
            showFriendPicker = true
        } label: {
            HStack(spacing: 12) {
                opponentAvatar
                Spacer()
                BattleAssetIcon(
                    asset: "angular-chevron-right-icon",
                    size: 16,
                    color: DS.Semantic.textPrimary
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(selectedFriend != nil ? DS.Semantic.brand.opacity(0.35) : DS.Semantic.border, lineWidth: 1.5)
            )
            .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var opponentAvatar: some View {
        if let friend = selectedFriend {
            ChamferedRectangleAlt(.medium)
                .fill(DS.Semantic.brandSoft)
                .frame(width: 42, height: 42)
                .overlay(
                    Text(String(friend.username.prefix(1)).uppercased())
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.brand)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName ?? friend.username)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("@\(friend.username)")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        } else {
            BattleAssetIcon(
                asset: "battle-opponent-icon",
                size: 42,
                color: DS.Semantic.surface50
            )

            Text("Choose Opponent")
                .dsFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
    }

    private var battleTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("BATTLE TYPE")
            VStack(spacing: 8) {
                ForEach([BattleType.volume, .workoutCount, .consistency], id: \.self) { type in
                    BattleTypeCard(
                        type: type,
                        isSelected: selectedBattleType == type
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedBattleType = type
                        }
                    }
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DURATION")
            HStack(spacing: 8) {
                ForEach(durationOptions, id: \.self) { days in
                    DurationButton(
                        days: days,
                        isSelected: duration == days
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            duration = days
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .dsFont(.caption, weight: .semibold)
            .foregroundStyle(DS.Semantic.textSecondary)
    }

    private var createBattleButton: some View {
        Button {
            Task {
                await createBattle()
            }
        } label: {
            HStack(spacing: 10) {
                BattleAssetIcon(
                    asset: "battle-flags-icon",
                    size: 24,
                    color: canCreateBattle ? .black : DS.Semantic.textPrimary
                )

                Text("Start Battle")
                    .dsFont(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canCreateBattle ? DS.Semantic.brand : DS.Semantic.surface50, in: ChamferedRectangle(.large))
            .foregroundStyle(canCreateBattle ? .black : DS.Semantic.textPrimary)
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(canCreateBattle ? DS.Semantic.brand.opacity(0.35) : DS.Semantic.border.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: canCreateBattle ? DS.Semantic.brand.opacity(0.25) : .clear, radius: 12, y: 4)
        }
        .disabled(!canCreateBattle)
    }

    private func createBattle() async {
        guard let friend = selectedFriend else { return }

        await viewModel.createBattle(
            opponentId: friend.id.uuidString,
            battleType: selectedBattleType,
            durationDays: duration
        )

        dismiss()
    }
}

struct BattleAssetIcon: View {
    let asset: String
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}

private extension BattleType {
    var battleIconAsset: String {
        switch self {
        case .volume:
            return "battle-volume-icon"
        case .consistency:
            return "tab-plan"
        case .workoutCount:
            return "battle-workout-count-icon"
        case .pr:
            return "challenge-trophy-icon"
        case .exercise:
            return "tab-train"
        case .runningDistance:
            return "battle-workout-count-icon"
        }
    }
}

// MARK: - Battle Type Card

private struct BattleTypeCard: View {
    let type: BattleType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    ChamferedRectangleAlt(.small)
                        .fill(isSelected ? DS.Semantic.brand.opacity(0.16) : DS.Semantic.fillSubtle)

                    BattleAssetIcon(
                        asset: type.battleIconAsset,
                        size: 24,
                        color: isSelected ? DS.Semantic.brand : DS.Semantic.textSecondary
                    )
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(type.description)
                        .dsFont(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                ZStack {
                    ChamferedRectangleAlt(.small)
                        .fill(isSelected ? DS.Semantic.brand : Color.clear)
                        .overlay(
                            ChamferedRectangleAlt(.small)
                                .stroke(isSelected ? DS.Semantic.brand : DS.Semantic.border, lineWidth: 2)
                        )

                    if isSelected {
                        BattleAssetIcon(
                            asset: "angular-check-icon",
                            size: 15,
                            color: .black
                        )
                    }
                }
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 12)
            .frame(height: 64)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(isSelected ? DS.Semantic.brand : DS.Semantic.border, lineWidth: isSelected ? 2.5 : 1)
            )
            .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duration Button

private struct DurationButton: View {
    let days: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(days)")
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(isSelected ? .black : DS.Semantic.textPrimary)

                Text(days == 1 ? "day" : "days")
                    .dsFont(.caption2)
                    .foregroundStyle(isSelected ? .black.opacity(0.7) : DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isSelected ? DS.Semantic.brand : DS.Semantic.card, in: ChamferedRectangleAlt(.medium))
            .overlay(
                ChamferedRectangleAlt(.medium)
                    .stroke(isSelected ? DS.Semantic.brand.opacity(0.3) : DS.Semantic.border, lineWidth: 1)
            )
            .contentShape(ChamferedRectangleAlt(.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friend Picker

struct FriendPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps
    @Binding var selectedFriend: UserProfile?
    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            content
            .background(DS.Semantic.surface)
            .navigationTitle("Choose Opponent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFriends()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            FriendsLoadingState()
        } else if let errorMessage {
            FriendsErrorState(message: errorMessage) {
                Task {
                    await loadFriends()
                }
            }
        } else if friends.isEmpty {
            FriendsEmptyState()
        } else {
            VStack(spacing: 0) {
                FriendPickerSearchBar(searchText: $searchText)

                if filteredFriends.isEmpty {
                    FriendsNoResultsState(searchQuery: searchText)
                } else {
                    friendsList
                }
            }
        }
    }

    private var friendsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredFriends) { friend in
                    SelectableFriendRow(friend: friend, isSelected: selectedFriend?.id == friend.profile.id) {
                        Haptics.light()
                        selectedFriend = friend.profile
                        dismiss()
                    }

                    if friend.id != filteredFriends.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
    }

    private var filteredFriends: [Friend] {
        if searchText.isEmpty {
            return friends
        }
        return friends.filter {
            $0.profile.username.localizedCaseInsensitiveContains(searchText) ||
            $0.profile.displayName?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    private func loadFriends() async {
        guard let currentUserId = deps.authService.currentUser?.id else {
            errorMessage = "Not authenticated"
            isLoading = false
            return
        }

        do {
            isLoading = true
            errorMessage = nil
            let friendships = try await deps.friendshipRepository.fetchFriends(userId: currentUserId)
            friends = friendships
            isLoading = false
        } catch {
            errorMessage = "Failed to load friends: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
