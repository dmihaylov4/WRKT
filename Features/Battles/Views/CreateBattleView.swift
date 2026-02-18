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
            VStack(spacing: 24) {
                headerSection
                opponentSection
                battleTypeSection
                durationSection
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .background(DS.Semantic.surface)
            .navigationTitle("Create Battle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
            .safeAreaInset(edge: .bottom) {
                createBattleButton
            }
            .sheet(isPresented: $showFriendPicker) {
                FriendPickerView(selectedFriend: $selectedFriend)
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.2.crossed.fill")
                .font(.system(size: 44))
                .foregroundStyle(DS.Semantic.brand)

            Text("Start a Battle")
                .font(.title2.bold())

            Text("Challenge a friend and compete!")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(.top, 8)
    }

    private var opponentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPPONENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)

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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
            }
            .padding()
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selectedFriend != nil ? DS.Semantic.brand.opacity(0.2) : DS.Semantic.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var opponentAvatar: some View {
        if let friend = selectedFriend {
            Circle()
                .fill(DS.Semantic.brandSoft)
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(friend.username.prefix(1)).uppercased())
                        .font(.title3.bold())
                        .foregroundStyle(DS.Semantic.brand)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName ?? friend.username)
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("@\(friend.username)")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(DS.Semantic.surface50)

            Text("Choose Opponent")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
    }

    private var battleTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BATTLE TYPE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)

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
        VStack(alignment: .leading, spacing: 12) {
            Text("DURATION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)

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

    private var confirmButton: some View {
        Button {
            Task {
                await createBattle()
            }
        } label: {
            Text("Create")
                .font(.headline)
                .foregroundStyle(selectedFriend != nil ? DS.Semantic.brand : DS.Semantic.textPrimary)
        }
        .disabled(selectedFriend == nil)
    }

    private var createBattleButton: some View {
        Button {
            Task {
                await createBattle()
            }
        } label: {
            HStack {
                Image(systemName: "flag.2.crossed.fill")
                Text("Start Battle")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(selectedFriend != nil ? DS.Semantic.brand : DS.Semantic.surface50)
            .foregroundStyle(selectedFriend != nil ? .white : DS.Semantic.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: selectedFriend != nil ? DS.Semantic.brand.opacity(0.3) : .clear, radius: 12, y: 4)
        }
        .disabled(selectedFriend == nil)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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

// MARK: - Battle Type Card

private struct BattleTypeCard: View {
    let type: BattleType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? DS.Semantic.brand : DS.Semantic.textSecondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Semantic.brand)
                        .font(.title3)
                } else {
                    Circle()
                        .strokeBorder(DS.Semantic.border, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(16)
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? DS.Semantic.brand : DS.Semantic.border, lineWidth: isSelected ? 2 : 1)
            )
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
                    .font(.title3.bold())
                    .foregroundStyle(isSelected ? .black : DS.Semantic.textPrimary)

                Text(days == 1 ? "day" : "days")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .black.opacity(0.7) : DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? DS.Semantic.brand : DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? .clear : DS.Semantic.border, lineWidth: 1)
            )
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
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    // Loading skeleton
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<8, id: \.self) { _ in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(DS.Semantic.surface50)
                                        .frame(width: 50, height: 50)

                                    VStack(alignment: .leading, spacing: 6) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(DS.Semantic.surface50)
                                            .frame(width: 120, height: 14)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(DS.Semantic.surface50)
                                            .frame(width: 80, height: 10)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(DS.Semantic.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding()
                    }
                } else if friends.isEmpty {
                    ContentUnavailableView(
                        "No Friends Yet",
                        systemImage: "person.2.slash",
                        description: Text("Add friends to battle with them")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredFriends) { friend in
                                FriendRowButton(
                                    friend: friend.profile,
                                    isSelected: selectedFriend?.id == friend.profile.id
                                ) {
                                    Haptics.light()
                                    selectedFriend = friend.profile
                                    dismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(DS.Semantic.surface)
            .searchable(text: $searchText, prompt: "Search friends")
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
        guard let currentUserId = deps.authService.currentUser?.id else { return }

        do {
            let friendships = try await deps.friendshipRepository.fetchFriends(userId: currentUserId)
            friends = friendships
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

// MARK: - Friend Row Button

private struct FriendRowButton: View {
    let friend: UserProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(DS.Semantic.brandSoft)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(friend.username.prefix(1)).uppercased())
                            .font(.title3.bold())
                            .foregroundStyle(DS.Semantic.brand)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName ?? friend.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("@\(friend.username)")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Semantic.brand)
                        .font(.title3)
                }
            }
            .padding(16)
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? DS.Semantic.brand : DS.Semantic.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

