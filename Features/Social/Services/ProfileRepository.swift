import Foundation
import Supabase

/// Repository for managing user profiles with query optimization
@MainActor
final class ProfileRepository: BaseRepository<UserProfile>, ProfileRepositoryProtocol {

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        super.init(
            tableName: "profiles",
            logPrefix: "Profile",
            client: client
        )
    }

    // MARK: - Fetch Profile

    /// Fetch a user profile by ID with caching
    func fetchProfile(userId: UUID) async throws -> UserProfile? {
        logInfo("Fetching profile for user: \(userId)", emoji: "🔍")

        // Try cache first
        let cacheKey = QueryCache.profileKey(userId: userId.uuidString)
        if let cached: UserProfile = cache.get(cacheKey) {
            logSuccess("Cache hit for profile: \(userId)")
            return cached
        }

        // Fetch from database
        let profiles: [UserProfile] = try await client
            .from(tableName)
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value

        guard let profile = profiles.first else {
            logWarning("Profile not found: \(userId)")
            return nil
        }

        // Cache the result
        cache.set(cacheKey, value: profile, ttl: .userProfiles)

        logSuccess("Fetched profile: \(userId)")
        return profile
    }

    // MARK: - Update Profile

    /// Update a user's profile information
    func updateProfile(
        userId: UUID,
        displayName: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil
    ) async throws -> UserProfile {
        logInfo("Updating profile for user: \(userId)", emoji: "✏️")

        struct UpdateProfile: Encodable {
            let display_name: String?
            let bio: String?
            let avatar_url: String?
            let updated_at: String

            init(displayName: String?, bio: String?, avatarUrl: String?) {
                self.display_name = displayName
                self.bio = bio
                self.avatar_url = avatarUrl
                self.updated_at = Date().ISO8601Format()
            }
        }

        let updateData = UpdateProfile(
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl
        )

        let profile: UserProfile = try await client
            .from(tableName)
            .update(updateData)
            .eq("id", value: userId.uuidString)
            .select()
            .single()
            .execute()
            .value

        // Invalidate cache
        let cacheKey = QueryCache.profileKey(userId: userId.uuidString)
        cache.invalidate(cacheKey)

        logSuccess("Profile updated: \(userId)")
        return profile
    }

    // MARK: - Update Privacy

    /// Update a user's privacy setting
    func updatePrivacy(userId: UUID, isPrivate: Bool) async throws {
        logInfo("Updating privacy for user: \(userId) to \(isPrivate ? "private" : "public")", emoji: "🔒")

        struct UpdatePrivacy: Encodable {
            let is_private: Bool
            let updated_at: String

            init(isPrivate: Bool) {
                self.is_private = isPrivate
                self.updated_at = Date().ISO8601Format()
            }
        }

        try await client
            .from(tableName)
            .update(UpdatePrivacy(isPrivate: isPrivate))
            .eq("id", value: userId.uuidString)
            .execute()

        // Invalidate cache
        let cacheKey = QueryCache.profileKey(userId: userId.uuidString)
        cache.invalidate(cacheKey)

        logSuccess("Privacy updated: \(userId)")
    }

    // MARK: - Search Users

    /// Search users by username with privacy filtering
    func searchUsers(query: String, limit: Int = 20, excludePrivate: Bool = true) async throws -> [UserProfile] {
        logInfo("Searching users with query: '\(query)'", emoji: "🔍")

        var dbQuery = client
            .from(tableName)
            .select()
            .like("username", pattern: "%\(query)%")

        if excludePrivate {
            dbQuery = dbQuery.eq("is_private", value: false)
        }

        let profiles: [UserProfile] = try await dbQuery
            .order("username")
            .limit(limit)
            .execute()
            .value

        logSuccess("Found \(profiles.count) users matching '\(query)'")
        return profiles
    }

    // MARK: - Batch Operations

    // Note: fetchProfilesBatched is inherited from BaseRepository and can be used directly
}
