import Foundation

enum PostType: String, Codable, Sendable, Hashable {
    case workout = "workout"
    case weeklyProgress = "weekly_progress"
    case battle = "battle"
    case shared = "shared"
}

struct VRPartnerSummary: Codable, Sendable, Equatable, Hashable {
    let distanceM: Double
    let durationS: Int
    let paceSecPerKm: Int?
    let avgHR: Int?

    enum CodingKeys: String, CodingKey {
        case distanceM = "distance_m"
        case durationS = "duration_s"
        case paceSecPerKm = "pace_sec_per_km"
        case avgHR = "avg_hr"
    }
}

struct PostParticipant: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let workoutData: CompletedWorkout?
    let vrStats: VRPartnerSummary?
    let joinedAt: Date
    let removedAt: Date?
    var profile: UserProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case workoutData = "workout_data"
        case vrStats = "vr_stats"
        case joinedAt = "joined_at"
        case removedAt = "removed_at"
        case profile
    }
}

struct WeeklyPostStats: Codable, Sendable, Equatable, Hashable {
    let weekStart: Date
    let totalVolumeKg: Double
    let totalExercises: Int
    let totalSets: Int
    let strengthDaysDone: Int
    let strengthTarget: Int
    let activeMinutesDone: Int
    let activeMinutesTarget: Int
    let streak: Int
    let superStreak: Int
}

extension WeeklyProgressStats {
    func asPostStats() -> WeeklyPostStats {
        WeeklyPostStats(
            weekStart: weekStart,
            totalVolumeKg: totalVolumeKg,
            totalExercises: totalExercises,
            totalSets: totalSets,
            strengthDaysDone: strengthDaysDone,
            strengthTarget: strengthTarget,
            activeMinutesDone: activeMinutesDone,
            activeMinutesTarget: activeMinutesTarget,
            streak: streak,
            superStreak: superStreak
        )
    }
}

/// Post visibility options
enum PostVisibility: String, Codable, Sendable, Hashable {
    case publicPost = "public"
    case friends = "friends"
    case privatePost = "private"

    var displayName: String {
        switch self {
        case .publicPost: return "Public"
        case .friends: return "Friends"
        case .privatePost: return "Private"
        }
    }

    var icon: String {
        switch self {
        case .publicPost: return "globe"
        case .friends: return "person.2.fill"
        case .privatePost: return "lock.fill"
        }
    }
}

/// Image attached to a post with privacy settings
struct PostImage: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let storagePath: String  // e.g., "workout-images-public/user-id/img.jpg"
    let isPublic: Bool       // true = visible to all, false = only owner sees

    enum CodingKeys: String, CodingKey {
        case id
        case storagePath = "storage_path"
        case isPublic = "is_public"
    }

    init(id: UUID = UUID(), storagePath: String, isPublic: Bool) {
        self.id = id
        self.storagePath = storagePath
        self.isPublic = isPublic
    }

    /// Check if this is a private image
    var isPrivate: Bool {
        !isPublic
    }

    /// Check if this is a legacy full URL (not a storage path)
    var isLegacyURL: Bool {
        storagePath.starts(with: "http://") || storagePath.starts(with: "https://")
    }

    /// Generated route/map snapshots must be distinguishable from user photos.
    /// Match path components and generated prefixes, not arbitrary words like "maple".
    var isGeneratedMapImage: Bool {
        let lower = storagePath.lowercased()
        return lower.contains("/route_map_")
            || lower.contains("/map_")
            || lower.contains("_route_map_")
            || lower.contains("_map_")
    }

    /// Get the bucket name from the storage path
    var bucketName: String {
        if isLegacyURL {
            // Legacy URLs - extract bucket from URL
            if storagePath.contains("/user-images/") {
                return "user-images"
            }
            return "user-images"  // Default for old posts
        }

        if storagePath.hasPrefix("workout-images-public/") {
            return "workout-images-public"
        } else if storagePath.hasPrefix("workout-images-private/") {
            return "workout-images-private"
        } else {
            // Default to public
            return "workout-images-public"
        }
    }

    /// Get the file path within the bucket (removes bucket prefix)
    var filePath: String {
        if isLegacyURL {
            // Legacy full URL - extract just the path portion
            // Format: https://project.supabase.co/storage/v1/object/public/user-images/userId/file.jpg
            if let range = storagePath.range(of: "/user-images/") {
                return String(storagePath[range.upperBound...])
            }
            return storagePath  // Fallback - return as-is
        }

        if storagePath.hasPrefix("workout-images-public/") {
            return String(storagePath.dropFirst("workout-images-public/".count))
        } else if storagePath.hasPrefix("workout-images-private/") {
            return String(storagePath.dropFirst("workout-images-private/".count))
        } else {
            // Return as-is for other formats
            return storagePath
        }
    }
}

/// Workout post shared on the social feed
struct WorkoutPost: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    var caption: String?
    let workoutData: CompletedWorkout
    var workoutDataList: [CompletedWorkout]?
    var images: [PostImage]?  // NEW: Replaces imageUrls with privacy support
    var visibility: PostVisibility
    var likesCount: Int
    var commentsCount: Int
    let createdAt: Date
    var updatedAt: Date
    var postType: PostType
    var weeklyStats: WeeklyPostStats?
    var battleStats: BattlePostStats?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case caption
        case workoutData = "workout_data"
        case workoutDataList = "workout_data_list"
        case images
        case imageUrls = "image_urls"  // Keep for backward compatibility
        case visibility
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case postType = "post_type"
        case weeklyStats = "weekly_stats"
        case battleStats = "battle_stats"
    }

    // MARK: - Initializers

    /// Memberwise initializer for creating posts programmatically
    init(
        id: UUID = UUID(),
        userId: UUID,
        caption: String? = nil,
        workoutData: CompletedWorkout,
        images: [PostImage]? = nil,
        visibility: PostVisibility = .publicPost,
        likesCount: Int = 0,
        commentsCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        workoutDataList: [CompletedWorkout]? = nil,
        postType: PostType = .workout,
        weeklyStats: WeeklyPostStats? = nil,
        battleStats: BattlePostStats? = nil
    ) {
        self.id = id
        self.userId = userId
        self.caption = caption
        self.workoutData = workoutData
        self.workoutDataList = workoutDataList
        self.images = images
        self.postType = postType
        self.weeklyStats = weeklyStats
        self.battleStats = battleStats
        self.visibility = visibility
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        visibility = try container.decode(PostVisibility.self, forKey: .visibility)
        likesCount = try container.decode(Int.self, forKey: .likesCount)
        commentsCount = try container.decode(Int.self, forKey: .commentsCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        workoutDataList = try container.decodeIfPresent([CompletedWorkout].self, forKey: .workoutDataList)

        // Handle images with backward compatibility for imageUrls
        if let newImages = try? container.decode([PostImage].self, forKey: .images) {
            // New format with PostImage objects
            images = newImages
        } else if let legacyUrls = try? container.decode([String].self, forKey: .imageUrls) {
            // Legacy format - convert URLs to PostImage objects (assume public)
            images = legacyUrls.map { url in
                PostImage(storagePath: url, isPublic: true)
            }
        } else {
            images = nil
        }

        // Handle workout_data - it might be Base64 encoded string or a JSONB object
        if let base64String = try? container.decode(String.self, forKey: .workoutData) {
            // It's stored as a Base64 encoded string - decode it

            guard let decodedData = Data(base64Encoded: base64String) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .workoutData,
                    in: container,
                    debugDescription: "Could not decode Base64 string"
                )
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                workoutData = try decoder.decode(CompletedWorkout.self, from: decodedData)
            } catch {
                throw error
            }
        } else {
            // It's stored as a JSONB object - decode directly

            do {
                workoutData = try container.decode(CompletedWorkout.self, forKey: .workoutData)
            } catch {
                throw error
            }
        }

        postType = (try? container.decode(PostType.self, forKey: .postType)) ?? .workout
        weeklyStats = try? container.decodeIfPresent(WeeklyPostStats.self, forKey: .weeklyStats)
        battleStats = try? container.decodeIfPresent(BattlePostStats.self, forKey: .battleStats)
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encode(workoutData, forKey: .workoutData)
        try container.encodeIfPresent(workoutDataList, forKey: .workoutDataList)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encode(postType, forKey: .postType)
        try container.encodeIfPresent(weeklyStats, forKey: .weeklyStats)
        try container.encodeIfPresent(battleStats, forKey: .battleStats)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(likesCount, forKey: .likesCount)
        try container.encode(commentsCount, forKey: .commentsCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Computed Properties

    var isMultiWorkout: Bool {
        (workoutDataList?.count ?? 0) > 1
    }

    var allWorkouts: [CompletedWorkout] {
        if let workoutDataList, !workoutDataList.isEmpty {
            return workoutDataList
        }
        return [workoutData]
    }

    var exerciseCount: Int {
        workoutData.entries.count
    }

    var totalSets: Int {
        workoutData.entries.reduce(0) { $0 + $1.sets.count }
    }

    var totalVolume: Double {
        workoutData.entries.reduce(0.0) { total, entry in
            total + entry.sets.reduce(0.0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
        }
    }

    var duration: TimeInterval? {
        guard let startedAt = workoutData.startedAt else { return nil }
        return workoutData.date.timeIntervalSince(startedAt)
    }

    var durationFormatted: String {
        guard let duration = duration else { return "Unknown" }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

/// Post with author information
struct PostWithAuthor: Identifiable, Sendable, Hashable {
    let id: UUID
    var post: WorkoutPost
    let author: UserProfile
    var isLikedByCurrentUser: Bool = false
    var partners: [PostParticipant] = []

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: post.createdAt, relativeTo: Date())
    }

    // Implement Hashable based on ID only
    static func == (lhs: PostWithAuthor, rhs: PostWithAuthor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Post comment
struct PostComment: Codable, Identifiable, Sendable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    let parentCommentID: UUID?  // NEW: For nested replies

    // Populated from joins (not stored in DB directly)
    var author: UserProfile?
    var replies: [PostComment]?  // NEW: Child comments
    var mentions: [CommentMention]?  // NEW: Tagged users

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case parentCommentID = "parent_comment_id"
        // Note: author, replies, mentions are NOT in CodingKeys
        // They are populated manually in the repository layer
    }

    // MARK: - Initializers

    /// Memberwise initializer for creating comments programmatically
    init(
        id: UUID = UUID(),
        postId: UUID,
        userId: UUID,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        parentCommentID: UUID? = nil,
        author: UserProfile? = nil,
        replies: [PostComment]? = nil,
        mentions: [CommentMention]? = nil
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentCommentID = parentCommentID
        self.author = author
        self.replies = replies
        self.mentions = mentions
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        postId = try container.decode(UUID.self, forKey: .postId)
        userId = try container.decode(UUID.self, forKey: .userId)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        parentCommentID = try container.decodeIfPresent(UUID.self, forKey: .parentCommentID)

        // These are populated manually in the repository layer
        author = nil
        replies = nil
        mentions = nil
    }
}

/// Comment mention (user tagged in a comment)
struct CommentMention: Codable, Identifiable, Sendable {
    let id: UUID
    let commentID: UUID
    let mentionedUserID: UUID
    let createdAt: Date

    // Populated from join
    var mentionedUser: UserProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case commentID = "comment_id"
        case mentionedUserID = "mentioned_user_id"
        case createdAt = "created_at"
        // Note: mentionedUser is NOT in CodingKeys
        // It is populated manually in the repository layer
    }

    // MARK: - Initializers

    /// Memberwise initializer for creating mentions programmatically
    init(
        id: UUID = UUID(),
        commentID: UUID,
        mentionedUserID: UUID,
        createdAt: Date = Date(),
        mentionedUser: UserProfile? = nil
    ) {
        self.id = id
        self.commentID = commentID
        self.mentionedUserID = mentionedUserID
        self.createdAt = createdAt
        self.mentionedUser = mentionedUser
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        commentID = try container.decode(UUID.self, forKey: .commentID)
        mentionedUserID = try container.decode(UUID.self, forKey: .mentionedUserID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // This is populated manually in the repository layer
        mentionedUser = nil
    }
}

/// Comment with author information
struct CommentWithAuthor: Identifiable, Sendable {
    let id: UUID
    let comment: PostComment
    let author: UserProfile

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: comment.createdAt, relativeTo: Date())
    }
}

/// Post like
struct PostLike: Codable, Identifiable, Sendable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}
