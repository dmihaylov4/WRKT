//
//  CutSentInvitesHost.swift
//  WRKT
//
//  The same loads and revoke as SentInvitesSheet.
//

import SwiftUI

struct CutSentInvitesHost: View {
    let split: WorkoutSplit
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var invites: [ProgramInviteRow] = []
    @State private var profilesByID: [UUID: UserProfile] = [:]
    @State private var isLoading = true
    @State private var revoking: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        CutSentInvitesView(
            model: CutSentInvitesLogic.model(
                programName: split.name,
                invites: invites.map { invite in
                    let profile = profilesByID[invite.recipientUserId]
                    return CutSentInviteFacts(id: invite.id, status: invite.status, displayName: profile?.displayName,
                                              username: profile?.username, avatarURL: profile?.avatarUrl)
                },
                loading: isLoading,
                revoking: revoking
            ),
            revoke: { id in
                guard let invite = invites.first(where: { $0.id == id }) else { return }
                Task { await revoke(invite) }
            },
            close: { dismiss() }
        )
        .task { await load() }
        .alert("Invite Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unable to load sent invites.")
        }
    }

    private func load() async {
        guard let programID = split.lastSharedProgramID, let currentUserID = deps.authService.currentUser?.id else {
            invites = []
            isLoading = false
            return
        }
        do {
            invites = try await deps.programSharingRepository.fetchSentInvites(for: currentUserID, programId: programID)
            let profiles = try await deps.profileRepository.fetchProfilesBatched(invites.map(\.recipientUserId))
            profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func revoke(_ invite: ProgramInviteRow) async {
        revoking.insert(invite.id)
        defer { revoking.remove(invite.id) }
        do {
            _ = try await deps.programSharingRepository.revoke(inviteId: invite.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
