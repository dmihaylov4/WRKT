import Testing
@testable import WRKT

private let stub = WhatsNewRelease(version: "5.1.1", title: "Test", bullets: ["bullet"])

@Suite(.serialized)
@MainActor
struct WhatsNewManagerTests {
    let manager = WhatsNewManager.shared

    init() {
        manager.reset()
    }

    @Test func doesNotShowForNewUser() {
        manager.configure(hasCompletedOnboarding: false, currentVersion: "5.1.1", releases: [stub])
        #expect(manager.needsWhatsNew == false)
    }

    @Test func showsForExistingUserOnNewVersion() {
        manager.configure(hasCompletedOnboarding: true, currentVersion: "5.1.1", releases: [stub])
        #expect(manager.needsWhatsNew == true)
    }

    @Test func doesNotShowWhenVersionAlreadySeen() {
        manager.lastSeenVersion = "5.1.1"
        manager.configure(hasCompletedOnboarding: true, currentVersion: "5.1.1", releases: [stub])
        #expect(manager.needsWhatsNew == false)
    }

    @Test func stampsVersionSilentlyWhenNoReleaseEntry() {
        manager.configure(hasCompletedOnboarding: true, currentVersion: "9.9.9", releases: [])
        #expect(manager.needsWhatsNew == false)
        #expect(manager.lastSeenVersion == "9.9.9")
    }

    @Test func stampsVersionSilentlyAfterOnboardingCompletion() {
        manager.configure(
            hasCompletedOnboarding: true,
            fromOnboardingCompletion: true,
            currentVersion: "5.1.1",
            releases: [stub]
        )
        #expect(manager.needsWhatsNew == false)
        #expect(manager.lastSeenVersion == "5.1.1")
    }

    @Test func dismissClearsSheetAndStampsVersion() {
        manager.configure(hasCompletedOnboarding: true, currentVersion: "5.1.1", releases: [stub])
        manager.dismiss()
        #expect(manager.needsWhatsNew == false)
        #expect(manager.lastSeenVersion == "5.1.1")
    }
}

