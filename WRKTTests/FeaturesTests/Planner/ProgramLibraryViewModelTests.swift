import Foundation
import Testing
@testable import WRKT

@MainActor
struct ProgramLibraryViewModelTests {

    @Test func pendingInviteAcceptCreatesLocalSplit() async throws {
        let programID = UUID()
        let vm = ProgramLibraryViewModel(
            repo: StubSharingRepo(programID: programID),
            plannerStore: InMemoryPlannerStore(),
            currentUserID: UUID()
        )

        try await vm.acceptInvite(
            inviteId: UUID(),
            senderUsername: "alice",
            senderDisplayName: "Alice"
        )

        #expect(vm.library.count == 1)
        let split = try #require(vm.library.first)
        #expect(split.creatorUsername == "alice")
        #expect(split.creatorDisplayName == "Alice")
        #expect(split.originProgramID == programID)
        #expect(split.isActive == false)
    }
}

@MainActor
private final class StubSharingRepo: ProgramSharingRepositoryInterface {
    let programID: UUID

    init(programID: UUID) {
        self.programID = programID
    }

    func send(
        split: WorkoutSplit,
        description: String?,
        to recipientIds: [UUID],
        currentUserID: UUID,
        currentUsername: String?,
        currentDisplayName: String?
    ) async throws -> ProgramSharingRepository.SendResult {
        ProgramSharingRepository.SendResult(program: try await fetchProgram(id: programID), succeeded: [], failed: [])
    }

    func fetchProgram(id: UUID) async throws -> SharedProgramRow {
        SharedProgramRow(
            id: programID,
            creatorUserId: UUID(),
            name: "Stub",
            description: nil,
            structure: SharedProgramStructure(
                creator: .init(userID: "alice-id", username: "alice", displayName: "Alice"),
                planBlocks: []
            ),
            reschedulePolicy: ReschedulePolicy.strict.rawValue,
            createdAt: .now,
            deletedAt: nil
        )
    }

    func fetchInvite(id: UUID) async throws -> ProgramInviteRow {
        ProgramInviteRow(
            id: id,
            programId: programID,
            senderUserId: UUID(),
            recipientUserId: UUID(),
            status: .pending,
            createdAt: .now,
            respondedAt: nil
        )
    }

    func fetchPendingInvites(for userId: UUID) async throws -> [ProgramInviteRow] { [] }
    func fetchSentInvites(for userId: UUID, programId: UUID?) async throws -> [ProgramInviteRow] { [] }

    func accept(inviteId: UUID) async throws -> ProgramInviteRow {
        ProgramInviteRow(
            id: inviteId,
            programId: programID,
            senderUserId: UUID(),
            recipientUserId: UUID(),
            status: .accepted,
            createdAt: .now,
            respondedAt: .now
        )
    }

    func decline(inviteId: UUID) async throws -> ProgramInviteRow { fatalError("unused") }
    func revoke(inviteId: UUID) async throws -> ProgramInviteRow { fatalError("unused") }
    func softDeleteProgram(id: UUID) async throws {}
}

@MainActor
private final class InMemoryPlannerStore: PlannerStoreInterface {
    var splits: [WorkoutSplit] = []

    func splitLibrary() throws -> [WorkoutSplit] { splits }

    func insert(_ split: WorkoutSplit) throws {
        splits.append(split)
    }

    func activate(_ split: WorkoutSplit, customization: ActivationCustomization) throws {}
    func replanUpcomingWorkouts(for split: WorkoutSplit, fromDate: Date) throws {}
    func saveContext() throws {}
}
