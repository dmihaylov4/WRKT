//
//  ChooseNameModel.swift
//  WRKT
//
//  The "Choose your name" step, shared by the legacy and the Cut screens. A signed-in account
//  that still has the server's made-up name (see ProfileNamePolicy) sees it in place of Social and
//  of every post composer. It asks for a display name and a username. The username rule and its
//  messages are sign up's (CutSignupLogic); whether a username is free is decided the way sign up
//  decides it, by the server's unique constraint, which the save reports as "already taken".
//

import Foundation
import Observation

enum ChooseNameField: Hashable, CaseIterable {
    case displayName, username
}

struct ChooseNameForm: Equatable {
    var displayName = ""
    var username = ""
}

/// Why a save did not go through. The step stays open with the message and the button stays on.
enum ChooseNameFailure: Equatable {
    case offline
    case usernameTaken
    case invalidUsername
    case notSignedIn
    case failed

    var message: String {
        switch self {
        case .offline: ChooseNameLogic.offlineMessage
        case .usernameTaken: SupabaseError.usernameTaken.errorDescription ?? ""
        case .invalidUsername: CutSignupLogic.usernameInvalidMessage
        case .notSignedIn: ChooseNameLogic.notSignedInMessage
        case .failed: ChooseNameLogic.failedMessage
        }
    }

    /// The field the message is about, outlined in red until it is edited.
    var field: ChooseNameField? {
        switch self {
        case .usernameTaken, .invalidUsername: .username
        default: nil
        }
    }
}

struct ChooseNameModel: Equatable {
    var displayNameMessage: String?
    /// The line under Username: the rule, or what is wrong with the typed name.
    var usernameNote: String
    var usernameNoteIsWarning: Bool
    var canSave: Bool
    var buttonEnabled: Bool
    var isSaving: Bool
    var isSigningOut: Bool
    var error: String?
    var flagsUsername: Bool
}

enum ChooseNameLogic {
    static let title = "Choose your name"
    static let intro = "Friends see this on your posts, comments and battles. Pick it before you use Social. Logging workouts works without it."
    static let displayNameLabel = "Name"
    static let displayNamePrompt = "Your name"
    static let usernameLabel = "Username"
    static let usernamePrompt = "Username"
    static let saveTitle = "Save and continue"
    static let signOutTitle = "Sign out"
    static let closeTitle = "Not now"

    static let displayNameRequiredMessage = "Enter the name your friends know you by"
    static let displayNamePlaceholderMessage = "Use the name your friends know you by, not \"User\""
    static let usernamePlaceholderMessage = "Choose a username of your own, not the one made up for you"
    static let offlineMessage = "You are offline. Connect to the internet and try again."
    static let failedMessage = "Your name could not be saved. Try again."
    static let notSignedInMessage = "You are signed out. Sign in again to choose your name."
    static let signOutFailedMessage = "Could not sign out. Try again."

    /// What the step starts with: the profile's names when they are real ones, otherwise Apple's
    /// name from the first sign-in for the display name and an empty username.
    static func initialForm(profile: UserProfile, suggestedDisplayName: String?) -> ChooseNameForm {
        let keepsDisplayName = !ProfileNamePolicy.isPlaceholderDisplayName(profile.displayName, username: profile.username)
        let keepsUsername = !ProfileNamePolicy.isPlaceholderUsername(profile.username, id: profile.id)
            && CutSignupLogic.isValidUsername(profile.username)
        return .init(
            displayName: keepsDisplayName ? (profile.displayName ?? "") : (suggestedDisplayName ?? ""),
            username: keepsUsername ? profile.username : ""
        )
    }

    static func trimmedDisplayName(_ form: ChooseNameForm) -> String {
        form.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shown once something is typed; an empty field only keeps the button off.
    static func displayNameMessage(_ displayName: String) -> String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty { return nil }
        if name.isEmpty { return displayNameRequiredMessage }
        if name.caseInsensitiveCompare(ProfileNamePolicy.placeholderDisplayName) == .orderedSame {
            return displayNamePlaceholderMessage
        }
        return nil
    }

    /// Sign up's username message, plus a refusal of this account's own made-up username.
    static func usernameMessage(_ username: String, id: UUID) -> String? {
        if username.isEmpty { return nil }
        if let message = CutSignupLogic.usernameMessage(username) { return message }
        if ProfileNamePolicy.isPlaceholderUsername(username, id: id) { return usernamePlaceholderMessage }
        return nil
    }

    static func canSave(_ form: ChooseNameForm, id: UUID) -> Bool {
        !trimmedDisplayName(form).isEmpty
            && displayNameMessage(form.displayName) == nil
            && !form.username.isEmpty
            && usernameMessage(form.username, id: id) == nil
    }

    /// Return moves from Name to Username; on Username it closes the keyboard.
    static func next(after field: ChooseNameField) -> ChooseNameField? {
        field == .displayName ? .username : nil
    }

    /// Sorts a save error into what the person can do about it.
    static func failure(for error: Error, isOnline: Bool) -> ChooseNameFailure {
        if !isOnline { return .offline }
        guard let supabaseError = error as? SupabaseError else {
            return isConnectionError(error) ? .offline : .failed
        }
        switch supabaseError {
        case .usernameTaken: return .usernameTaken
        case .invalidUsername: return .invalidUsername
        case .notAuthenticated: return .notSignedIn
        case .networkError(let underlying): return isConnectionError(underlying) ? .offline : .failed
        default: return .failed
        }
    }

    private static func isConnectionError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    static func model(_ form: ChooseNameForm, id: UUID, isSaving: Bool, isSigningOut: Bool = false,
                      failure: ChooseNameFailure?, signOutFailed: Bool = false) -> ChooseNameModel {
        let usernameMessage = usernameMessage(form.username, id: id)
        let can = canSave(form, id: id)
        return .init(
            displayNameMessage: displayNameMessage(form.displayName),
            usernameNote: usernameMessage ?? CutSignupLogic.usernameRule,
            usernameNoteIsWarning: usernameMessage != nil,
            canSave: can,
            buttonEnabled: can && !isSaving && !isSigningOut,
            isSaving: isSaving,
            isSigningOut: isSigningOut,
            error: signOutFailed ? signOutFailedMessage : failure?.message,
            flagsUsername: failure?.field == .username
        )
    }
}

/// Holds the step's form and runs its save and sign out. Both are passed in, so tests run it with
/// fakes; the app passes the auth service.
@MainActor
@Observable
final class ChooseNameController {
    let profileId: UUID
    var form: ChooseNameForm {
        didSet {
            // Editing the field a message points at clears it, as sign up does.
            if form.username != oldValue.username, failure?.field == .username { failure = nil }
        }
    }
    private(set) var isSaving = false
    private(set) var isSigningOut = false
    private(set) var failure: ChooseNameFailure?
    private(set) var signOutFailed = false

    private let save: (_ username: String, _ displayName: String) async throws -> Void
    private let performSignOut: () async throws -> Void
    private let isOnline: () -> Bool

    init(profile: UserProfile, suggestedDisplayName: String?,
         save: @escaping (_ username: String, _ displayName: String) async throws -> Void,
         signOut: @escaping () async throws -> Void,
         isOnline: @escaping () -> Bool) {
        self.profileId = profile.id
        self.form = ChooseNameLogic.initialForm(profile: profile, suggestedDisplayName: suggestedDisplayName)
        self.save = save
        self.performSignOut = signOut
        self.isOnline = isOnline
    }

    var model: ChooseNameModel {
        ChooseNameLogic.model(form, id: profileId, isSaving: isSaving, isSigningOut: isSigningOut,
                              failure: failure, signOutFailed: signOutFailed)
    }

    /// Returns true once the name is saved. Offline, nothing is sent and the step says so.
    @discardableResult
    func submit() async -> Bool {
        guard ChooseNameLogic.canSave(form, id: profileId), !isSaving, !isSigningOut else { return false }
        failure = nil
        signOutFailed = false
        guard isOnline() else {
            failure = .offline
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await save(form.username, ChooseNameLogic.trimmedDisplayName(form))
            return true
        } catch {
            failure = ChooseNameLogic.failure(for: error, isOnline: isOnline())
            return false
        }
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        signOutFailed = false
        defer { isSigningOut = false }
        do {
            try await performSignOut()
        } catch {
            signOutFailed = true
        }
    }
}
