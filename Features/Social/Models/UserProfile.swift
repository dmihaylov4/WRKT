import Foundation

/// User profile stored in Supabase
struct UserProfile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var username: String
    var displayName: String?
    var avatarUrl: String?
    var bio: String?
    var isPrivate: Bool
    var autoPostPRs: Bool
    var autoPostCardio: Bool
    var birthYear: Int?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case bio
        case isPrivate = "is_private"
        case autoPostPRs = "auto_post_prs"
        case autoPostCardio = "auto_post_cardio"
        case birthYear = "birth_year"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        username: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        bio: String? = nil,
        isPrivate: Bool = false,
        autoPostPRs: Bool = true,
        autoPostCardio: Bool = true,
        birthYear: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.isPrivate = isPrivate
        self.autoPostPRs = autoPostPRs
        self.autoPostCardio = autoPostCardio
        self.birthYear = birthYear
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        autoPostPRs = try container.decode(Bool.self, forKey: .autoPostPRs)
        autoPostCardio = try container.decodeIfPresent(Bool.self, forKey: .autoPostCardio) ?? true
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Calculate max HR from birth year (220 - age), or default 190 if no birth year set
    var maxHR: Int {
        guard let birthYear else { return 190 }
        let age = Calendar.current.component(.year, from: Date()) - birthYear
        guard age > 0, age < 120 else { return 190 }
        return 220 - age
    }
}

/// Local auth state
struct AuthUser: Identifiable, Sendable {
    let id: UUID
    let email: String
    var profile: UserProfile?
}
