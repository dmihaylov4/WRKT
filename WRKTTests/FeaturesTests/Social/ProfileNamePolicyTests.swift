import Foundation
import Testing
@testable import WRKT

/// The made-up name test, the surfaces it closes, automatic posts, and Apple's name.
/// Every profile here is a fixture; nothing reaches a server.
@Suite("Profile name policy")
struct ProfileNamePolicyTests {
    /// Nine accounts in the shape the server's new-user trigger leaves: display name "User",
    /// username "user_" plus the first 8 characters of the id. The ids are fixtures with the
    /// same form as real ones (lower-case hex, hyphenated), including ids whose prefix is all
    /// digits or all letters.
    static let nineShapes: [UUID] = [
        "1a2b3c4d-0000-4000-8000-000000000001",
        "00000000-1111-4111-8111-111111111111",
        "abcdefab-2222-4222-8222-222222222222",
        "9f8e7d6c-3333-4333-8333-333333333333",
        "deadbeef-4444-4444-8444-444444444444",
        "12345678-5555-4555-8555-555555555555",
        "c0ffee00-6666-4666-8666-666666666666",
        "0a0b0c0d-7777-4777-8777-777777777777",
        "fedcba98-8888-4888-8888-888888888888"
    ].map { UUID(uuidString: $0)! }

    static func profile(id: UUID = UUID(), username: String, displayName: String?,
                        prs: Bool = true, runs: Bool = true, watch: Bool = true) -> UserProfile {
        UserProfile(id: id, username: username, displayName: displayName,
                    autoPostPRs: prs, autoPostCardio: runs, autoPostWatchWorkouts: watch)
    }

    static func placeholder(_ id: UUID) -> UserProfile {
        profile(id: id, username: "user_" + id.uuidString.lowercased().prefix(8), displayName: "User")
    }

    // MARK: - The placeholder test

    @Test(arguments: nineShapes)
    func theNineShapesArePlaceholders(_ id: UUID) {
        let username = "user_" + id.uuidString.lowercased().prefix(8)
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: username, displayName: "User"))
        #expect(ProfileNamePolicy.needsName(Self.placeholder(id)))
    }

    @Test func letterCaseDoesNotMatter() {
        let id = UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000001")!
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: "User_1A2B3C4D", displayName: "USER"))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: "USER_1a2b3c4d", displayName: "user"))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: "user_1a2B3c4D", displayName: " User "))
    }

    @Test func aMissingBlankOrEchoedDisplayNameIsStillAPlaceholder() {
        let id = Self.nineShapes[0]
        let username = "user_1a2b3c4d"
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: username, displayName: nil))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: username, displayName: ""))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: username, displayName: "   "))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: username, displayName: "user_1a2b3c4d"))
    }

    @Test func realUsernamesThatStartWithUserAreNotPlaceholders() {
        let id = Self.nineShapes[0]
        for username in ["user_anna", "username", "user", "users_club", "user_1a2b3c4", "user_1a2b3c4d5",
                         "user1a2b3c4d", "userdeadbeef", "User_Anna", "USER_Bob_99"] {
            #expect(!ProfileNamePolicy.isPlaceholder(id: id, username: username, displayName: "User"), "\(username)")
        }
    }

    @Test func anotherAccountsMadeUpUsernameIsNotThisAccountsPlaceholder() {
        // Someone picked "user_deadbeef" on purpose; their own id starts differently.
        let id = Self.nineShapes[0]
        #expect(!ProfileNamePolicy.isPlaceholder(id: id, username: "user_deadbeef", displayName: "User"))
    }

    @Test func aRealDisplayNameEndsThePlaceholder() {
        // Apple's name already reached the profile: friends can tell who this is.
        let id = Self.nineShapes[0]
        #expect(!ProfileNamePolicy.isPlaceholder(id: id, username: "user_1a2b3c4d", displayName: "Anna Smith"))
        #expect(!ProfileNamePolicy.isPlaceholder(id: id, username: "user_1a2b3c4d", displayName: "Users United"))
    }

    @Test func aRealUsernameEndsThePlaceholderEvenWithDisplayNameUser() {
        #expect(!ProfileNamePolicy.isPlaceholder(id: Self.nineShapes[0], username: "anna_lifts", displayName: "User"))
    }

    @Test func usernamesTheOAuthSetupRejectsArePlaceholdersToo() {
        let id = Self.nineShapes[0]
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: "", displayName: "Anna"))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: "ab", displayName: "Anna"))
        #expect(ProfileNamePolicy.isPlaceholder(id: id, username: id.uuidString.lowercased(), displayName: "Anna"))
    }

    @Test func noProfileNeedsNoName() {
        // Signed out or local mode: nothing to gate.
        #expect(!ProfileNamePolicy.needsName(nil))
    }

    @Test func placeholderUsernameIsBuiltFromTheIdsStart() {
        #expect(ProfileNamePolicy.placeholderUsername(for: Self.nineShapes[2]) == "user_abcdefab")
    }

    // MARK: - The gate

    @Test func theGatedSurfacesAreExactlyTheSocialOnes() {
        // Training, planning, cardio, Health, settings and sign out are deliberately absent.
        #expect(SocialNameSurface.allCases == [.socialTab, .posting, .socialSettings, .autoPost, .battleShare])
    }

    @Test(arguments: SocialNameSurface.allCases)
    func everySocialSurfaceIsClosedToAPlaceholder(_ surface: SocialNameSurface) {
        #expect(surface.isBlocked(for: Self.placeholder(Self.nineShapes[3])))
    }

    @Test(arguments: SocialNameSurface.allCases)
    func noSurfaceIsClosedToARealNameOrWithoutAProfile(_ surface: SocialNameSurface) {
        #expect(!surface.isBlocked(for: Self.profile(username: "anna_lifts", displayName: "Anna")))
        #expect(!surface.isBlocked(for: nil))
    }

    // MARK: - Automatic posts

    @Test(arguments: AutoPostSetting.allCases)
    func aPlaceholderNeverAutoPostsWhateverItsSwitchesSay(_ setting: AutoPostSetting) {
        let placeholder = Self.placeholder(Self.nineShapes[4])
        #expect(setting.value(in: placeholder))
        #expect(!setting.allowsPosting(for: placeholder))
    }

    @Test(arguments: AutoPostSetting.allCases)
    func aRealNameAutoPostsWhenItsSwitchIsOn(_ setting: AutoPostSetting) {
        #expect(setting.allowsPosting(for: Self.profile(username: "anna_lifts", displayName: "Anna")))
        let off = Self.profile(username: "anna_lifts", displayName: "Anna", prs: false, runs: false, watch: false)
        #expect(!setting.allowsPosting(for: off))
        #expect(!setting.allowsPosting(for: nil))
    }

    @Test func choosingANameReopensPosting() {
        var profile = Self.placeholder(Self.nineShapes[5])
        #expect(!ProfileNamePolicy.allowsPosting(profile))
        profile.username = "anna_lifts"
        profile.displayName = "Anna"
        #expect(ProfileNamePolicy.allowsPosting(profile))
        #expect(AutoPostSetting.prs.allowsPosting(for: profile))
    }

    // MARK: - Apple's name

    @Test func appleNameIsFormattedForDisplay() {
        var components = PersonNameComponents()
        components.givenName = "Anna"
        components.familyName = "Smith"
        #expect(ProfileNamePolicy.displayName(from: components) == "Anna Smith")
    }

    @Test func noOrBlankAppleNameGivesNothing() {
        #expect(ProfileNamePolicy.displayName(from: nil) == nil)
        #expect(ProfileNamePolicy.displayName(from: PersonNameComponents()) == nil)
        var blank = PersonNameComponents()
        blank.givenName = "  "
        #expect(ProfileNamePolicy.displayName(from: blank) == nil)
    }

    @Test func thePendingAppleNameIsKeptPerAccountUntilCleared() throws {
        let suite = "ProfileNamePolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let anna = UUID(), other = UUID()
        PendingAppleName.save("Anna Smith", for: anna, defaults: defaults)
        #expect(PendingAppleName.value(for: anna, defaults: defaults) == "Anna Smith")
        #expect(PendingAppleName.value(for: other, defaults: defaults) == nil)
        PendingAppleName.clear(for: anna, defaults: defaults)
        #expect(PendingAppleName.value(for: anna, defaults: defaults) == nil)
    }
}
