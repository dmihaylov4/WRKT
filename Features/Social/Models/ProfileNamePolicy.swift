//
//  ProfileNamePolicy.swift
//  WRKT
//
//  Tells a made-up profile name from a real one. When an account is created without a username
//  (Sign in with Apple or Google), the server's new-user trigger fills the profile with display
//  name "User" and username "user_" plus the first 8 characters of the account id. Friends cannot
//  tell such an account apart from any other, so it must choose a name before it can use Social,
//  and it never posts automatically. The test is on the shape of the name, so accounts that were
//  created before this check existed are caught too.
//

import Foundation

enum ProfileNamePolicy {
    /// The display name the server gives an account that signed up without one.
    static let placeholderDisplayName = "User"
    /// The username the server gives such an account starts with this, then the id's first 8 characters.
    static let placeholderUsernamePrefix = "user_"

    /// The username the server would make up for this account id, in lower case.
    static func placeholderUsername(for id: UUID) -> String {
        placeholderUsernamePrefix + String(id.uuidString.lowercased().prefix(8))
    }

    /// True when `username` is the made-up one for this id, in any letter case. A real username
    /// that happens to start with "user_" does not match, because its tail is not this id's start.
    static func isPlaceholderUsername(_ username: String, id: UUID) -> Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == placeholderUsername(for: id)
    }

    /// True when the display name tells nobody who this is: missing, blank, "User" in any case,
    /// or the same as the username.
    static func isPlaceholderDisplayName(_ displayName: String?, username: String) -> Bool {
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return true }
        if name.caseInsensitiveCompare(placeholderDisplayName) == .orderedSame { return true }
        return name.caseInsensitiveCompare(username.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    /// The one test: this profile still carries the server's made-up name. Also true for the
    /// usernames the OAuth setup check already rejects (empty, under 3 characters, a bare UUID).
    static func isPlaceholder(id: UUID, username: String, displayName: String?) -> Bool {
        if OAuthProfileState.needsSetup(username: username) { return true }
        return isPlaceholderUsername(username, id: id)
            && isPlaceholderDisplayName(displayName, username: username)
    }

    static func needsName(_ profile: UserProfile?) -> Bool {
        guard let profile else { return false }
        return isPlaceholder(id: profile.id, username: profile.username, displayName: profile.displayName)
    }

    /// Whether this account may post to friends at all: automatic posts and battle shares.
    /// A signed out user (no profile) posts nothing either.
    static func allowsPosting(_ profile: UserProfile?) -> Bool {
        guard let profile else { return false }
        return !needsName(profile)
    }

    /// The name Apple hands over on the first authorization, formatted for display, or nil when
    /// Apple sent none (every later sign-in) or only blanks.
    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}

/// The parts of the app that need a real name. Each is wired to `SocialNameGate` or checks
/// `ProfileNamePolicy` directly. Training, planning, cardio, Health, settings and sign out are not
/// listed: they never ask for a name.
enum SocialNameSurface: CaseIterable, Equatable {
    /// The Social tab: feed, likes, comments, Compete (battles and challenges) and Friends.
    case socialTab
    /// Every post composer, wherever it is opened from (win screen, cardio detail, year award).
    case posting
    /// The social rows in settings: my profile, activity, friends, friend requests, find friends.
    case socialSettings
    /// Automatic PR, run and Watch workout posts.
    case autoPost
    /// Sharing a finished battle to the feed.
    case battleShare

    /// Whether this surface is closed to `profile` until it chooses a name.
    func isBlocked(for profile: UserProfile?) -> Bool {
        ProfileNamePolicy.needsName(profile)
    }
}

extension AutoPostSetting {
    /// The switch is on and the account has a real name. A placeholder account never auto-posts,
    /// whatever its switches say (they default to on).
    func allowsPosting(for profile: UserProfile?) -> Bool {
        guard let profile, ProfileNamePolicy.allowsPosting(profile) else { return false }
        return value(in: profile)
    }
}

/// Apple's name from the first sign-in, kept on this device until it reaches the profile.
/// Apple never sends it again, so a failed save must not lose it.
enum PendingAppleName {
    private static func key(_ userId: UUID) -> String { "auth.pendingAppleName.\(userId.uuidString)" }

    static func save(_ name: String, for userId: UUID, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: key(userId))
    }

    static func value(for userId: UUID, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(userId))
    }

    static func clear(for userId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
    }
}
