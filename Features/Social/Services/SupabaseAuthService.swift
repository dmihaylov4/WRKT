import Foundation
import Supabase
import Auth
import Combine

@MainActor
final class SupabaseAuthService: ObservableObject {
    static let shared = SupabaseAuthService()

    @Published var currentUser: AuthUser?
    @Published var isLoading = false
    @Published var error: SupabaseError?
    @Published var isCheckingSession = true // Track initial session check
    @Published var needsEmailVerification = false // Track if user needs to verify email
    @Published var signupEmail: String? // Store email for resend verification
    @Published var needsPasswordReset = false // Track if user is in password recovery flow

    private let client: SupabaseClient

    private init() {
        self.client = SupabaseClientWrapper.shared.client

        // Check for existing session on init
        Task {
            await restoreSession()
            isCheckingSession = false // Session check complete
        }
    }

    // MARK: - Session Management

    /// Restore existing session from storage (with offline support)
    func restoreSession() async {
        let networkMonitor = NetworkMonitor.shared
        let cacheManager = CacheManager.shared

        do {
            let session = try await client.auth.session
            let user = session.user

            // Try to fetch profile online, fallback to cache if offline
            let profile: UserProfile

            if networkMonitor.isConnected {
                // Online: Fetch fresh profile
                profile = try await client
                    .from("profiles")
                    .select()
                    .eq("id", value: user.id.uuidString)
                    .single()
                    .execute()
                    .value

                // Cache the profile for offline use
                cacheManager.cacheProfile(profile)
            } else {
                // Offline: Try to restore from cache
                if let cachedProfile = cacheManager.fetchCachedProfile(id: user.id, includeExpired: true) {
                    profile = cachedProfile
                } else {
                    // No cache available, can't restore
                    self.currentUser = nil
                    return
                }
            }

            self.currentUser = AuthUser(
                id: user.id,
                email: user.email ?? "",
                profile: profile
            )

            // Upload push notification token now that user is logged in
            await PushNotificationService.shared.uploadTokenToServer()

            // One-time sync: if local age is set but profile has no birth_year, push it to Supabase
            if networkMonitor.isConnected, profile.birthYear == nil {
                let localAge = UserDefaults.standard.integer(forKey: "user_age")
                if localAge > 0 {
                    let birthYear = Calendar.current.component(.year, from: Date()) - localAge
                    Task {
                        try? await self.updateProfile(birthYear: birthYear)
                    }
                }
            }
        } catch {
            // No session or error - user is logged out
            self.currentUser = nil
        }
    }

    // MARK: - Authentication Methods

    /// Sign up a new user (requires email verification)
    func signUp(email: String, password: String, username: String, displayName: String?) async throws {
        isLoading = true
        defer { isLoading = false }

        // Validate username
        guard isValidUsername(username) else {
            throw SupabaseError.invalidUsername
        }

        do {
            // Create auth user with metadata
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: [
                    "username": .string(username),
                    "display_name": .string(displayName ?? username)
                ]
            )

            // Store email for resend verification
            self.signupEmail = email

            let user = response.user

            // Check if email confirmation is required
            if user.emailConfirmedAt == nil {
                // Email confirmation required
                self.needsEmailVerification = true
                self.currentUser = nil  // Don't log them in yet
                self.error = nil
            } else {
                // Email already verified (shouldn't happen with confirmation enabled, but handle it)

                // Fetch the auto-created profile
                let profile: UserProfile = try await client
                    .from("profiles")
                    .select()
                    .eq("id", value: user.id.uuidString)
                    .single()
                    .execute()
                    .value

                // Cache profile for offline use
                CacheManager.shared.cacheProfile(profile)

                self.currentUser = AuthUser(
                    id: user.id,
                    email: email,
                    profile: profile
                )

                self.needsEmailVerification = false
                self.error = nil
            }
        } catch let error as PostgrestError {
            // Check for duplicate username error
            if error.message.contains("duplicate key") || error.message.contains("unique constraint") {
                self.error = .usernameTaken
                throw SupabaseError.usernameTaken
            } else {
                self.error = .serverError(error.message)
                throw SupabaseError.serverError(error.message)
            }
        } catch {
            // Check if generic error contains unique constraint message
            let errorMessage = error.localizedDescription
            if errorMessage.contains("duplicate key") ||
               errorMessage.contains("unique constraint") ||
               errorMessage.contains("profiles_username_key") ||
               errorMessage.contains("Database error saving new user") {
                self.error = .usernameTaken
                throw SupabaseError.usernameTaken
            }

            self.error = .networkError(error)
            throw SupabaseError.networkError(error)
        }
    }

    /// Sign in existing user
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {

            let response = try await client.auth.signIn(
                email: email,
                password: password
            )


            // Fetch profile
            let profile: UserProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: response.user.id.uuidString)
                .single()
                .execute()
                .value


            // Cache profile for offline use
            CacheManager.shared.cacheProfile(profile)

            self.currentUser = AuthUser(
                id: response.user.id,
                email: email,
                profile: profile
            )

            self.error = nil

            // Upload push notification token now that user is logged in
            await PushNotificationService.shared.uploadTokenToServer()
        } catch {
            self.error = .invalidCredentials
            throw SupabaseError.invalidCredentials
        }
    }

    /// Sign out current user
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // Remove push token from server before signing out
            await PushNotificationService.shared.removeTokenFromServer()

            try await client.auth.signOut()
            self.currentUser = nil
            self.error = nil
        } catch {
            self.error = .networkError(error)
            throw SupabaseError.networkError(error)
        }
    }

    /// Send password reset email
    func resetPassword(email: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "wrkt://auth/recovery")
            )
            self.error = nil
        } catch {
            self.error = .networkError(error)
            throw SupabaseError.networkError(error)
        }
    }

    /// Update password (used after clicking reset link)
    func updatePassword(newPassword: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.update(user: .init(password: newPassword))
            self.needsPasswordReset = false
            self.error = nil
        } catch {
            self.error = .networkError(error)
            throw SupabaseError.networkError(error)
        }
    }

    /// Handle the password recovery deep link
    func handlePasswordRecovery(url: URL) async {
        // Supabase sends tokens in the URL fragment (after #)
        // We need to use the SDK's session(from:) method to handle this
        do {
            // The SDK's session(from:) method parses the URL fragment and creates a session
            let session = try await client.auth.session(from: url)

            if session.user.id != UUID() {
                // Session is valid, user can now set new password
                self.needsPasswordReset = true
                AppLogger.success("Password recovery session established for user: \(session.user.id)", category: AppLogger.app)
            }
        } catch {
            AppLogger.error("Failed to handle password recovery", error: error, category: AppLogger.app)
            self.error = .networkError(error)
        }
    }

    /// Resend verification email
    func resendVerificationEmail() async throws {
        guard let email = signupEmail else {
            throw SupabaseError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Resend confirmation email
            try await client.auth.resend(
                email: email,
                type: .signup
            )
            self.error = nil
        } catch {
            self.error = .networkError(error)
            throw SupabaseError.networkError(error)
        }
    }

    /// Check if current session's email is verified
    func checkEmailVerified() async -> Bool {
        do {
            let session = try await client.auth.session
            return session.user.emailConfirmedAt != nil
        } catch {
            return false
        }
    }

    // MARK: - Profile Management

    /// Update current user's profile
    func updateProfile(username: String? = nil, displayName: String? = nil, bio: String? = nil, avatarUrl: String? = nil, isPrivate: Bool? = nil, autoPostPRs: Bool? = nil, autoPostCardio: Bool? = nil, birthYear: Int? = nil) async throws {
        guard let userId = currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        // Validate username if provided
        if let username = username {
            guard isValidUsername(username) else {
                throw SupabaseError.invalidUsername
            }
        }

        // Build update object
        var updates: [String: AnyJSON] = [:]
        if let username = username {
            updates["username"] = .string(username)
        }
        if let displayName = displayName {
            updates["display_name"] = .string(displayName)
        }
        if let bio = bio {
            updates["bio"] = .string(bio)
        }
        if let avatarUrl = avatarUrl {
            updates["avatar_url"] = .string(avatarUrl)
        }
        if let isPrivate = isPrivate {
            updates["is_private"] = .bool(isPrivate)
        }
        if let autoPostPRs = autoPostPRs {
            updates["auto_post_prs"] = .bool(autoPostPRs)
        }
        if let autoPostCardio = autoPostCardio {
            updates["auto_post_cardio"] = .bool(autoPostCardio)
        }
        if let birthYear = birthYear {
            updates["birth_year"] = .integer(birthYear)
        }

        do {
            let updatedProfile: UserProfile = try await client
                .from("profiles")
                .update(updates)
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            // Update local state
            if let email = currentUser?.email {
                self.currentUser = AuthUser(
                    id: userId,
                    email: email,
                    profile: updatedProfile
                )
            }

            self.error = nil
        } catch let error as PostgrestError {
            if error.message.contains("duplicate key") || error.message.contains("unique constraint") {
                self.error = .usernameTaken
                throw SupabaseError.usernameTaken
            } else {
                self.error = .serverError(error.message)
                throw SupabaseError.serverError(error.message)
            }
        } catch {
            self.error = .networkError(error)
            throw SupabaseError.networkError(error)
        }
    }

    /// Fetch a user profile by ID
    func fetchProfile(userId: UUID) async throws -> UserProfile {
        do {
            let profile: UserProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            return profile
        } catch {
            throw SupabaseError.profileNotFound
        }
    }

    /// Search for users by username
    /// - Parameter query: Search query (username)
    /// - Returns: Array of matching profiles (excludes private profiles unless already friends)
    func searchUsers(query: String) async throws -> [UserProfile] {
        guard !query.isEmpty else { return [] }
        guard let currentUserId = currentUser?.id else { return [] }

        // Search for users by username (case-insensitive partial match)
        let profiles: [UserProfile] = try await client
            .from("profiles")
            .select()
            .ilike("username", pattern: "%\(query)%")
            .limit(20)
            .execute()
            .value

        // Fetch accepted friendships for current user to check friend status
        let friendIds = await fetchFriendIds(for: currentUserId)

        // Filter: show public profiles OR private profiles that are friends
        let visibleProfiles = profiles.filter { profile in
            // Always show public profiles
            if !profile.isPrivate { return true }
            // Show private profiles if they're friends
            return friendIds.contains(profile.id)
        }

        return visibleProfiles
    }

    /// Fetch IDs of all accepted friends for a user
    private func fetchFriendIds(for userId: UUID) async -> Set<UUID> {
        do {
            // Fetch friendships where user is either user1 or user2 and status is accepted
            let friendships: [FriendshipRecord] = try await client
                .from("friendships")
                .select("user1_id, user2_id")
                .or("user1_id.eq.\(userId.uuidString),user2_id.eq.\(userId.uuidString)")
                .eq("status", value: "accepted")
                .execute()
                .value

            // Extract friend IDs (the other user in each friendship)
            var friendIds = Set<UUID>()
            for friendship in friendships {
                if friendship.user1Id == userId {
                    friendIds.insert(friendship.user2Id)
                } else {
                    friendIds.insert(friendship.user1Id)
                }
            }
            return friendIds
        } catch {
            AppLogger.warning("Failed to fetch friend IDs: \(error)", category: AppLogger.app)
            return []
        }
    }

    // MARK: - Validation Helpers

    /// Validate username format
    private func isValidUsername(_ username: String) -> Bool {
        let length = username.count
        guard length >= 3 && length <= 30 else { return false }

        let regex = "^[a-zA-Z0-9_]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: username)
    }
}

// MARK: - Helper Models

/// Lightweight friendship record for friend ID lookups
private struct FriendshipRecord: Codable {
    let user1Id: UUID
    let user2Id: UUID

    enum CodingKeys: String, CodingKey {
        case user1Id = "user1_id"
        case user2Id = "user2_id"
    }
}
