import Foundation
import Testing
@testable import WRKT

/// The Choose your name step: what it starts with, what it accepts, and what each save outcome
/// leaves on screen. The save and sign out are fakes; nothing reaches a server.
@Suite("Choose your name")
@MainActor
struct ChooseNameLogicTests {
    private static let id = UUID(uuidString: "1a2b3c4d-0000-4000-8000-000000000001")!
    private static let placeholder = UserProfile(id: id, username: "user_1a2b3c4d", displayName: "User")

    private final class FakeAccount {
        var saves: [(username: String, displayName: String)] = []
        var savingSeen: [Bool] = []
        var nextSaveError: Error?
        var signOutError: Error?
        var signOuts = 0
        var online = true
    }

    private func controller(_ account: FakeAccount, profile: UserProfile = placeholder,
                            suggested: String? = nil) -> ChooseNameController {
        var controller: ChooseNameController!
        controller = ChooseNameController(
            profile: profile,
            suggestedDisplayName: suggested,
            save: { username, displayName in
                account.savingSeen.append(controller.isSaving)
                account.saves.append((username, displayName))
                if let error = account.nextSaveError {
                    account.nextSaveError = nil
                    throw error
                }
            },
            signOut: {
                account.signOuts += 1
                if let error = account.signOutError { throw error }
            },
            isOnline: { account.online }
        )
        return controller
    }

    // MARK: - Starting values

    @Test func aPlaceholderStartsEmptyOrWithApplesName() {
        #expect(ChooseNameLogic.initialForm(profile: Self.placeholder, suggestedDisplayName: nil) == .init())
        #expect(ChooseNameLogic.initialForm(profile: Self.placeholder, suggestedDisplayName: "Anna Smith")
                == .init(displayName: "Anna Smith", username: ""))
    }

    @Test func realNamesOnTheProfileAreKept() {
        let profile = UserProfile(id: Self.id, username: "ab", displayName: "Anna")
        // A too-short username is not offered back; the real display name is.
        #expect(ChooseNameLogic.initialForm(profile: profile, suggestedDisplayName: "Other")
                == .init(displayName: "Anna", username: ""))
    }

    // MARK: - Validation

    @Test func bothFieldsAreRequired() {
        #expect(!ChooseNameLogic.canSave(.init(displayName: "", username: "anna_lifts"), id: Self.id))
        #expect(!ChooseNameLogic.canSave(.init(displayName: "   ", username: "anna_lifts"), id: Self.id))
        #expect(!ChooseNameLogic.canSave(.init(displayName: "Anna", username: ""), id: Self.id))
        #expect(ChooseNameLogic.canSave(.init(displayName: "Anna", username: "anna_lifts"), id: Self.id))
    }

    @Test func theUsernameRuleIsSignUps() {
        for bad in ["ab", "anna lifts", "anna-lifts", "anna!", String(repeating: "a", count: 31)] {
            #expect(ChooseNameLogic.usernameMessage(bad, id: Self.id) == CutSignupLogic.usernameInvalidMessage, "\(bad)")
            #expect(!ChooseNameLogic.canSave(.init(displayName: "Anna", username: bad), id: Self.id))
        }
        #expect(ChooseNameLogic.usernameMessage("A_1", id: Self.id) == nil)
        #expect(ChooseNameLogic.usernameMessage("", id: Self.id) == nil)
    }

    @Test func theMadeUpUsernameAndDisplayNameAreRefused() {
        #expect(ChooseNameLogic.usernameMessage("User_1A2B3C4D", id: Self.id) == ChooseNameLogic.usernamePlaceholderMessage)
        #expect(ChooseNameLogic.displayNameMessage("user") == ChooseNameLogic.displayNamePlaceholderMessage)
        #expect(!ChooseNameLogic.canSave(.init(displayName: "Anna", username: "user_1a2b3c4d"), id: Self.id))
        #expect(!ChooseNameLogic.canSave(.init(displayName: "User", username: "anna_lifts"), id: Self.id))
        // A real name that starts with "user" is fine.
        #expect(ChooseNameLogic.canSave(.init(displayName: "Userina", username: "user_anna"), id: Self.id))
    }

    @Test func theModelShowsTheRuleUntilTheNameBreaksIt() {
        let empty = ChooseNameLogic.model(.init(), id: Self.id, isSaving: false, failure: nil)
        #expect(empty.usernameNote == CutSignupLogic.usernameRule)
        #expect(!empty.usernameNoteIsWarning)
        #expect(!empty.buttonEnabled)
        #expect(empty.error == nil)

        let bad = ChooseNameLogic.model(.init(displayName: "Anna", username: "a!"), id: Self.id, isSaving: false, failure: nil)
        #expect(bad.usernameNoteIsWarning)
        #expect(!bad.canSave)

        let saving = ChooseNameLogic.model(.init(displayName: "Anna", username: "anna_lifts"), id: Self.id, isSaving: true, failure: nil)
        #expect(saving.canSave)
        #expect(!saving.buttonEnabled)
        #expect(saving.isSaving)
    }

    @Test func returnMovesFromNameToUsernameThenCloses() {
        #expect(ChooseNameLogic.next(after: .displayName) == .username)
        #expect(ChooseNameLogic.next(after: .username) == nil)
    }

    // MARK: - Failure sorting

    @Test func errorsAreSortedIntoWhatThePersonCanDo() {
        #expect(ChooseNameLogic.failure(for: SupabaseError.usernameTaken, isOnline: true) == .usernameTaken)
        #expect(ChooseNameLogic.failure(for: SupabaseError.invalidUsername, isOnline: true) == .invalidUsername)
        #expect(ChooseNameLogic.failure(for: SupabaseError.notAuthenticated, isOnline: true) == .notSignedIn)
        #expect(ChooseNameLogic.failure(for: SupabaseError.networkError(URLError(.notConnectedToInternet)), isOnline: true) == .offline)
        #expect(ChooseNameLogic.failure(for: SupabaseError.networkError(URLError(.timedOut)), isOnline: true) == .offline)
        #expect(ChooseNameLogic.failure(for: URLError(.networkConnectionLost), isOnline: true) == .offline)
        #expect(ChooseNameLogic.failure(for: SupabaseError.serverError("boom"), isOnline: true) == .failed)
        #expect(ChooseNameLogic.failure(for: SupabaseError.networkError(URLError(.badServerResponse)), isOnline: true) == .failed)
        #expect(ChooseNameLogic.failure(for: SupabaseError.serverError("boom"), isOnline: false) == .offline)
    }

    @Test func takenUsesSignUpsWordsAndPointsAtUsername() {
        #expect(ChooseNameFailure.usernameTaken.message == "This username is already taken")
        #expect(ChooseNameFailure.usernameTaken.field == .username)
        #expect(ChooseNameFailure.offline.field == nil)
    }

    // MARK: - Save outcomes

    @Test func aGoodSaveSendsTheTrimmedNamesOnce() async {
        let account = FakeAccount()
        let step = controller(account)
        step.form = .init(displayName: "  Anna Smith ", username: "anna_lifts")
        #expect(await step.submit())
        #expect(account.saves.map(\.username) == ["anna_lifts"])
        #expect(account.saves.map(\.displayName) == ["Anna Smith"])
        #expect(account.savingSeen == [true])
        #expect(!step.isSaving)
        #expect(step.failure == nil)
    }

    @Test func offlineSendsNothingAndSaysSo() async {
        let account = FakeAccount()
        account.online = false
        let step = controller(account)
        step.form = .init(displayName: "Anna", username: "anna_lifts")
        #expect(!(await step.submit()))
        #expect(account.saves.isEmpty)
        #expect(step.failure == .offline)
        #expect(step.model.error == ChooseNameLogic.offlineMessage)
        #expect(step.model.buttonEnabled)
    }

    @Test func aTakenUsernameStaysOnTheStepAndClearsWhenEdited() async {
        let account = FakeAccount()
        account.nextSaveError = SupabaseError.usernameTaken
        let step = controller(account)
        step.form = .init(displayName: "Anna", username: "anna")
        #expect(!(await step.submit()))
        #expect(step.model.flagsUsername)
        #expect(step.model.error == "This username is already taken")
        step.form.displayName = "Anna S"
        #expect(step.failure == .usernameTaken)
        step.form.username = "anna_lifts"
        #expect(step.failure == nil)
        #expect(await step.submit())
        #expect(account.saves.map(\.username) == ["anna", "anna_lifts"])
    }

    @Test func aFailedSaveCanBeRetried() async {
        let account = FakeAccount()
        account.nextSaveError = SupabaseError.serverError("Server error: 503")
        let step = controller(account)
        step.form = .init(displayName: "Anna", username: "anna_lifts")
        #expect(!(await step.submit()))
        #expect(step.model.error == ChooseNameLogic.failedMessage)
        #expect(step.model.buttonEnabled)
        #expect(await step.submit())
        #expect(step.model.error == nil)
        #expect(account.saves.count == 2)
    }

    @Test func aLostConnectionDuringTheSaveReadsAsOffline() async {
        let account = FakeAccount()
        account.nextSaveError = SupabaseError.networkError(URLError(.notConnectedToInternet))
        let step = controller(account)
        step.form = .init(displayName: "Anna", username: "anna_lifts")
        #expect(!(await step.submit()))
        #expect(step.failure == .offline)
    }

    @Test func anIncompleteFormSavesNothing() async {
        let account = FakeAccount()
        let step = controller(account)
        step.form = .init(displayName: "Anna", username: "user_1a2b3c4d")
        #expect(!(await step.submit()))
        #expect(account.saves.isEmpty)
        #expect(step.failure == nil)
    }

    @Test func signOutRunsAndAFailureIsShown() async {
        let account = FakeAccount()
        let step = controller(account)
        await step.signOut()
        #expect(account.signOuts == 1)
        #expect(step.model.error == nil)

        account.signOutError = SupabaseError.networkError(URLError(.notConnectedToInternet))
        await step.signOut()
        #expect(account.signOuts == 2)
        #expect(step.model.error == ChooseNameLogic.signOutFailedMessage)
        #expect(!step.isSigningOut)
    }
}
