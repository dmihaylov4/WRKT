import Foundation
import Testing
@testable import WRKT

@MainActor
struct ProgramAttributionTests {

    @Test func outgoingAttributionUsesCurrentUserForLocallyCreatedSplit() {
        let split = WorkoutSplit(name: "PPL", planBlocks: [])
        let attribution = ProgramSerializer.outgoingAttribution(
            for: split,
            currentUserID: "me",
            currentUsername: "bob",
            currentDisplayName: "Bob"
        )

        #expect(attribution.userID == "me")
        #expect(attribution.username == "bob")
        #expect(attribution.displayName == "Bob")
    }

    @Test func outgoingAttributionPreservesOriginalCreatorOnReshare() {
        let split = WorkoutSplit(
            name: "Shared PPL",
            planBlocks: [],
            creatorUserID: "alice-id",
            creatorUsername: "alice",
            creatorDisplayName: "Alice",
            originProgramID: UUID()
        )

        let attribution = ProgramSerializer.outgoingAttribution(
            for: split,
            currentUserID: "bob-id",
            currentUsername: "bob",
            currentDisplayName: "Bob"
        )

        #expect(attribution.userID == "alice-id")
        #expect(attribution.username == "alice")
        #expect(attribution.displayName == "Alice")
    }
}
