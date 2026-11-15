import Foundation
import Testing
@testable import WRKT

@Suite("Auto-post settings")
@MainActor
struct AutoPostSettingTests {
    private struct SaveFailed: Error {}

    /// A stand-in for the auth service's published user.
    private final class LiveUser {
        var user: AuthUser?
        init(_ profile: UserProfile?) {
            user = AuthUser(id: UUID(), email: "fixture@example.invalid", profile: profile)
        }
    }

    private static func profile(prs: Bool = true, runs: Bool = true, watch: Bool = false) -> UserProfile {
        UserProfile(id: UUID(), username: "fixture", autoPostPRs: prs, autoPostCardio: runs, autoPostWatchWorkouts: watch)
    }

    @Test func valuesAndDefaults() {
        let profile = Self.profile(prs: false, runs: true, watch: true)
        #expect(!AutoPostSetting.prs.value(in: profile))
        #expect(AutoPostSetting.runs.value(in: profile))
        #expect(AutoPostSetting.watchWorkouts.value(in: profile))
        #expect(AutoPostSetting.prs.value(in: nil))
        #expect(AutoPostSetting.runs.value(in: nil))
        #expect(!AutoPostSetting.watchWorkouts.value(in: nil))
    }

    @Test func theSwitchShowsTheNewValueBeforeTheSaveReturns() async throws {
        let live = LiveUser(Self.profile())
        var seenDuringSave: Bool?
        var sent: [Bool] = []
        try await AutoPostSetting.prs.set(false, read: { live.user }, write: { live.user = $0 }) { value in
            seenDuringSave = AutoPostSetting.prs.value(in: live.user?.profile)
            sent.append(value)
        }
        #expect(seenDuringSave == false)
        #expect(sent == [false])
        #expect(AutoPostSetting.prs.value(in: live.user?.profile) == false)
    }

    @Test func aFailedSaveRollsBackAndThrows() async {
        let live = LiveUser(Self.profile(watch: false))
        await #expect(throws: SaveFailed.self) {
            try await AutoPostSetting.watchWorkouts.set(true, read: { live.user }, write: { live.user = $0 }) { _ in
                throw SaveFailed()
            }
        }
        #expect(AutoPostSetting.watchWorkouts.value(in: live.user?.profile) == false)
    }

    @Test func rollbackTouchesOnlyItsOwnSwitch() async {
        let live = LiveUser(Self.profile(prs: true, runs: true))
        await #expect(throws: SaveFailed.self) {
            try await AutoPostSetting.runs.set(false, read: { live.user }, write: { live.user = $0 }) { _ in
                // Another switch changes while this save is in flight.
                live.user?.profile?.autoPostPRs = false
                throw SaveFailed()
            }
        }
        #expect(AutoPostSetting.runs.value(in: live.user?.profile) == true)
        #expect(AutoPostSetting.prs.value(in: live.user?.profile) == false)
    }

    @Test func noChangeSavesNothing() async throws {
        let live = LiveUser(Self.profile(prs: true))
        var saves = 0
        try await AutoPostSetting.prs.set(true, read: { live.user }, write: { live.user = $0 }) { _ in saves += 1 }
        #expect(saves == 0)
    }
}
