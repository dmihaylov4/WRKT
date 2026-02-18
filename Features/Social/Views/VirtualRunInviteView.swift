//
//  VirtualRunInviteView.swift
//  WRKT
//
//  View for inviting a friend to a virtual run
//

import SwiftUI
import Kingfisher

struct VirtualRunInviteView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = VirtualRunInviteCoordinator.shared
    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var sendingTo: UUID?
    @State private var error: String?
    @State private var isCancellingRun = false
    @State private var showCancelConfirmation = false
    @State private var staleActiveRun: VirtualRun?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if coordinator.isInActiveRun || coordinator.isWaitingForAcceptance || staleActiveRun != nil {
                        activeRunBanner
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if friends.isEmpty {
                        emptyState
                    } else {
                        friendsGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle("Invite to Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadFriends()
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .confirmationDialog("Cancel Active Run?", isPresented: $showCancelConfirmation, titleVisibility: .visible) {
                Button("Cancel Run", role: .destructive) {
                    Task { await cancelActiveRun() }
                }
            } message: {
                Text("This will end your current virtual run and notify your partner.")
            }
        }
    }

    // MARK: - Active Run Banner

    private var activeRunBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DS.Palette.marone)

                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.isWaitingForAcceptance ? "Invite Sent" : "Run In Progress")
                        .font(.subheadline.weight(.semibold))
                    if let name = coordinator.sentInvitePartnerName {
                        Text("Waiting for \(name)...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("You're currently in a virtual run")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isCancellingRun {
                    ProgressView()
                } else {
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Text("End")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(DS.card)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Palette.marone.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Friends Grid

    private var friendsGrid: some View {
        LazyVStack(spacing: 10) {
            ForEach(friends) { friend in
                FriendInviteCard(
                    friend: friend,
                    isSending: sendingTo == friend.profile.id
                ) {
                    Task { await sendInvite(to: friend) }
                }
                .disabled(sendingTo != nil)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No Friends Yet")
                .font(.title3.weight(.bold))
            Text("Add friends to invite them for a virtual run")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func loadFriends() async {
        isLoading = true
        do {
            guard let userId = deps.authService.currentUser?.id else {
                error = "Not logged in"
                isLoading = false
                return
            }

            // Check for stale active run in DB that the coordinator doesn't know about
            if !coordinator.isInActiveRun && !coordinator.isWaitingForAcceptance {
                staleActiveRun = try? await deps.virtualRunRepository.fetchActiveRun(for: userId)
            }

            friends = try await deps.friendshipRepository.fetchFriends(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func sendInvite(to friend: Friend) async {
        guard !coordinator.isInActiveRun && !coordinator.isWaitingForAcceptance && staleActiveRun == nil else {
            return
        }

        sendingTo = friend.profile.id
        do {
            guard let userId = deps.authService.currentUser?.id else {
                error = "Not logged in"
                sendingTo = nil
                return
            }
            let run = try await deps.virtualRunRepository.sendInvite(to: friend.profile.id, from: userId)

            VirtualRunInviteCoordinator.shared.trackSentInvite(
                runId: run.id,
                partnerId: friend.profile.id,
                partnerName: friend.profile.displayName ?? friend.profile.username
            )

            Haptics.success()
            dismiss()
        } catch let vrError as VirtualRunError where vrError == .alreadyInActiveRun {
            // Fetch the stale active run from DB so the banner can show
            if let userId = deps.authService.currentUser?.id {
                staleActiveRun = try? await deps.virtualRunRepository.fetchActiveRun(for: userId)
            }
        } catch {
            self.error = error.localizedDescription
        }
        sendingTo = nil
    }

    private func cancelActiveRun() async {
        isCancellingRun = true
        do {
            if let runId = coordinator.activeRunId ?? coordinator.sentInviteId ?? staleActiveRun?.id {
                try await deps.virtualRunRepository.declineInvite(runId)
            }
            coordinator.runEnded()
            staleActiveRun = nil
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
        isCancellingRun = false
    }
}

// MARK: - Friend Invite Card

private struct FriendInviteCard: View {
    let friend: Friend
    let isSending: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                avatarView
                    .frame(width: 46, height: 46)

                // Name + username
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.profile.displayName ?? friend.profile.username)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("@\(friend.profile.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Invite action
                if isSending {
                    ProgressView()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "figure.run")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.marone)
                        .frame(width: 36, height: 36)
                        .background(DS.Palette.marone.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.card)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = friend.profile.avatarUrl,
           let url = URL(string: urlString) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(DS.Semantic.surface50)
                .overlay {
                    Text(String((friend.profile.displayName ?? friend.profile.username).prefix(1)).uppercased())
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
