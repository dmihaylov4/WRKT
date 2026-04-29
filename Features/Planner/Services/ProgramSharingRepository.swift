//
//  ProgramSharingRepository.swift
//  WRKT
//
//  Supabase CRUD for shared programs and invite lifecycle.
//

import Foundation
import Supabase

struct SharedProgramRow: Codable, Sendable, Identifiable {
    let id: UUID
    let creatorUserId: UUID
    let name: String
    let description: String?
    let structure: SharedProgramStructure
    let reschedulePolicy: String
    let createdAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorUserId = "creator_user_id"
        case name
        case description
        case structure
        case reschedulePolicy = "reschedule_policy"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
}

enum ProgramInviteStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
    case revoked
    case cancelled
}

struct ProgramInviteRow: Codable, Sendable, Identifiable {
    let id: UUID
    let programId: UUID
    let senderUserId: UUID
    let recipientUserId: UUID
    let status: ProgramInviteStatus
    let createdAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case programId = "program_id"
        case senderUserId = "sender_user_id"
        case recipientUserId = "recipient_user_id"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

enum ProgramSharingError: LocalizedError {
    case notAuthenticated
    case programUnavailable
    case inviteAlreadyResponded
    case inviteStateConflict

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .programUnavailable:
            return "This program is no longer available."
        case .inviteAlreadyResponded:
            return "This invite has already been responded to."
        case .inviteStateConflict:
            return "This invite can no longer be changed."
        }
    }
}

@MainActor
protocol ProgramSharingRepositoryInterface: AnyObject {
    func send(
        split: WorkoutSplit,
        description: String?,
        to recipientIds: [UUID],
        currentUserID: UUID,
        currentUsername: String?,
        currentDisplayName: String?
    ) async throws -> ProgramSharingRepository.SendResult
    func fetchProgram(id: UUID) async throws -> SharedProgramRow
    func fetchInvite(id: UUID) async throws -> ProgramInviteRow
    func fetchPendingInvites(for userId: UUID) async throws -> [ProgramInviteRow]
    func fetchSentInvites(for userId: UUID, programId: UUID?) async throws -> [ProgramInviteRow]
    func accept(inviteId: UUID) async throws -> ProgramInviteRow
    func decline(inviteId: UUID) async throws -> ProgramInviteRow
    func revoke(inviteId: UUID) async throws -> ProgramInviteRow
    func softDeleteProgram(id: UUID) async throws
}

@MainActor
final class ProgramSharingRepository: ProgramSharingRepositoryInterface {
    struct SendResult {
        let program: SharedProgramRow
        let succeeded: [ProgramInviteRow]
        let failed: [(recipientId: UUID, error: Error)]
    }

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.client = client
    }

    func send(
        split: WorkoutSplit,
        description: String?,
        to recipientIds: [UUID],
        currentUserID: UUID,
        currentUsername: String?,
        currentDisplayName: String?
    ) async throws -> SendResult {
        guard !recipientIds.isEmpty else {
            throw ProgramSharingError.inviteStateConflict
        }

        let attribution = ProgramSerializer.outgoingAttribution(
            for: split,
            currentUserID: currentUserID.uuidString,
            currentUsername: currentUsername,
            currentDisplayName: currentDisplayName
        )
        let structure = ProgramSerializer.toStructure(split, creator: attribution)

        struct NewProgram: Encodable {
            let creator_user_id: String
            let name: String
            let description: String?
            let structure: SharedProgramStructure
            let reschedule_policy: String
        }

        let program: SharedProgramRow = try await client
            .from("shared_programs")
            .insert(
                NewProgram(
                    creator_user_id: currentUserID.uuidString.lowercased(),
                    name: split.name,
                    description: description,
                    structure: structure,
                    reschedule_policy: split.policy.rawValue
                )
            )
            .select()
            .single()
            .execute()
            .value

        var succeeded: [ProgramInviteRow] = []
        var failed: [(recipientId: UUID, error: Error)] = []

        struct NewInvite: Encodable {
            let program_id: String
            let sender_user_id: String
            let recipient_user_id: String
            let status: String
        }

        for recipientId in recipientIds {
            do {
                let invite: ProgramInviteRow = try await client
                    .from("program_invites")
                    .insert(
                        NewInvite(
                            program_id: program.id.uuidString.lowercased(),
                            sender_user_id: currentUserID.uuidString.lowercased(),
                            recipient_user_id: recipientId.uuidString.lowercased(),
                            status: ProgramInviteStatus.pending.rawValue
                        )
                    )
                    .select()
                    .single()
                    .execute()
                    .value
                succeeded.append(invite)
            } catch {
                failed.append((recipientId, error))
            }
        }

        if succeeded.isEmpty {
            try? await softDeleteProgram(id: program.id)
        }

        return SendResult(program: program, succeeded: succeeded, failed: failed)
    }

    func fetchProgram(id: UUID) async throws -> SharedProgramRow {
        do {
            let row: SharedProgramRow = try await client
                .from("shared_programs")
                .select()
                .eq("id", value: id.uuidString.lowercased())
                .single()
                .execute()
                .value

            if row.deletedAt != nil {
                throw ProgramSharingError.programUnavailable
            }
            return row
        } catch let error as ProgramSharingError {
            throw error
        } catch {
            throw error
        }
    }

    func fetchInvite(id: UUID) async throws -> ProgramInviteRow {
        try await client
            .from("program_invites")
            .select()
            .eq("id", value: id.uuidString.lowercased())
            .single()
            .execute()
            .value
    }

    func fetchPendingInvites(for userId: UUID) async throws -> [ProgramInviteRow] {
        try await client
            .from("program_invites")
            .select()
            .eq("recipient_user_id", value: userId.uuidString.lowercased())
            .eq("status", value: ProgramInviteStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchSentInvites(for userId: UUID, programId: UUID? = nil) async throws -> [ProgramInviteRow] {
        var query = client
            .from("program_invites")
            .select()
            .eq("sender_user_id", value: userId.uuidString.lowercased())
        if let programId {
            query = query.eq("program_id", value: programId.uuidString.lowercased())
        }
        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func accept(inviteId: UUID) async throws -> ProgramInviteRow {
        try await updateInvite(inviteId: inviteId, status: .accepted)
    }

    func decline(inviteId: UUID) async throws -> ProgramInviteRow {
        try await updateInvite(inviteId: inviteId, status: .declined)
    }

    func revoke(inviteId: UUID) async throws -> ProgramInviteRow {
        try await updateInvite(inviteId: inviteId, status: .revoked)
    }

    func softDeleteProgram(id: UUID) async throws {
        struct Update: Encodable { let deleted_at: String }
        _ = try await client
            .from("shared_programs")
            .update(Update(deleted_at: Date().ISO8601Format()))
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    private func updateInvite(inviteId: UUID, status: ProgramInviteStatus) async throws -> ProgramInviteRow {
        struct Update: Encodable { let status: String }

        do {
            return try await client
                .from("program_invites")
                .update(Update(status: status.rawValue))
                .eq("id", value: inviteId.uuidString.lowercased())
                .eq("status", value: ProgramInviteStatus.pending.rawValue)
                .select()
                .single()
                .execute()
                .value
        } catch let error as PostgrestError
            where error.message.contains("JSON object requested, multiple (or no) rows returned") {
            throw ProgramSharingError.inviteAlreadyResponded
        } catch {
            throw error
        }
    }
}
