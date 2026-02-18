import Foundation
import SwiftData

/// SwiftData model for caching user profiles locally
@Model
final class CachedProfile {
    @Attribute(.unique) var id: String
    var username: String
    var displayName: String?
    var avatarUrl: String?
    var bio: String?
    var isPrivate: Bool
    var autoPostPRs: Bool = true  // Default to true to match database default
    var birthYear: Int?
    var createdAt: Date
    var updatedAt: Date
    var cachedAt: Date

    init(
        id: String,
        username: String,
        displayName: String?,
        avatarUrl: String?,
        bio: String?,
        isPrivate: Bool,
        autoPostPRs: Bool,
        birthYear: Int? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.isPrivate = isPrivate
        self.autoPostPRs = autoPostPRs
        self.birthYear = birthYear
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cachedAt = Date()
    }

    /// Check if cache is expired (15 minutes TTL for profiles)
    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > 900 // 15 minutes
    }
}

// MARK: - Conversion Extensions
extension CachedProfile {
    /// Convert from UserProfile to CachedProfile
    static func from(_ profile: UserProfile) -> CachedProfile {
        CachedProfile(
            id: profile.id.uuidString,
            username: profile.username,
            displayName: profile.displayName,
            avatarUrl: profile.avatarUrl,
            bio: profile.bio,
            isPrivate: profile.isPrivate,
            autoPostPRs: profile.autoPostPRs,
            birthYear: profile.birthYear,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    /// Convert CachedProfile to UserProfile
    func toUserProfile() -> UserProfile? {
        guard let profileId = UUID(uuidString: id) else {
            return nil
        }

        return UserProfile(
            id: profileId,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            bio: bio,
            isPrivate: isPrivate,
            autoPostPRs: autoPostPRs,
            birthYear: birthYear,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
