//
//  AutoPostSetting.swift
//  WRKT
//
//  The three social auto-post switches in Preferences (legacy and Cut). Their one source of
//  truth is the signed in user's profile on the auth service, which views observe. A toggle
//  writes the new value into that profile at once, saves it with the same updateProfile call
//  and payload as before, and puts the old value back if the save throws, so the caller can
//  show the error.
//

import Foundation

enum AutoPostSetting: CaseIterable {
    case prs, runs, watchWorkouts

    static let saveFailedTitle = "Could not save"
    static let saveFailedMessage = "The setting was not changed. Check your connection and try again."

    /// The switch's value; the profile defaults when there is none.
    func value(in profile: UserProfile?) -> Bool {
        switch self {
        case .prs: profile?.autoPostPRs ?? true
        case .runs: profile?.autoPostCardio ?? true
        case .watchWorkouts: profile?.autoPostWatchWorkouts ?? false
        }
    }

    func setting(_ value: Bool, in profile: UserProfile) -> UserProfile {
        var profile = profile
        switch self {
        case .prs: profile.autoPostPRs = value
        case .runs: profile.autoPostCardio = value
        case .watchWorkouts: profile.autoPostWatchWorkouts = value
        }
        return profile
    }

    /// Optimistic update with rollback. `read` and `write` are the live user; `save` sends the
    /// value. On failure the old value goes back only if nothing else changed it meanwhile.
    @MainActor
    func set(
        _ value: Bool,
        read: () -> AuthUser?,
        write: (AuthUser) -> Void,
        save: (Bool) async throws -> Void
    ) async throws {
        guard var user = read(), let profile = user.profile else { return }
        let old = self.value(in: profile)
        guard old != value else { return }
        user.profile = setting(value, in: profile)
        write(user)
        do {
            try await save(value)
        } catch {
            if var current = read(), let currentProfile = current.profile, self.value(in: currentProfile) == value {
                current.profile = setting(old, in: currentProfile)
                write(current)
            }
            throw error
        }
    }

    /// The app's wiring: the auth service's live user and its updateProfile call.
    @MainActor
    func set(_ value: Bool, auth: SupabaseAuthService) async throws {
        try await set(value, read: { auth.currentUser }, write: { auth.currentUser = $0 }) { value in
            switch self {
            case .prs: try await auth.updateProfile(autoPostPRs: value)
            case .runs: try await auth.updateProfile(autoPostCardio: value)
            case .watchWorkouts: try await auth.updateProfile(autoPostWatchWorkouts: value)
            }
        }
    }
}
