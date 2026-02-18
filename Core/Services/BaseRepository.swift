import Foundation
import Supabase

/// Base repository protocol defining common repository operations
protocol RepositoryProtocol {
    associatedtype Entity: Codable

    /// The Supabase table name this repository manages
    var tableName: String { get }

    /// The Supabase client for database operations
    var client: SupabaseClient { get }

    /// The query cache for performance optimization
    var cache: QueryCache { get }
}

/// Base repository class providing common CRUD operations and utilities
@MainActor
class BaseRepository<T: Codable> {

    // MARK: - Properties

    let client: SupabaseClient
    let cache: QueryCache
    let tableName: String

    /// Log prefix for consistent logging (e.g., "Post", "Friendship")
    private let logPrefix: String

    // MARK: - Initialization

    init(
        tableName: String,
        logPrefix: String,
        client: SupabaseClient = SupabaseClientWrapper.shared.client,
        cache: QueryCache = QueryCache.shared
    ) {
        self.tableName = tableName
        self.logPrefix = logPrefix
        self.client = client
        self.cache = cache
    }

    // MARK: - Logging

    /// Log an info message with consistent formatting
    nonisolated func logInfo(_ message: String, emoji: String = "ℹ️") {
        print("\(emoji) [\(logPrefix)] \(message)")
    }

    /// Log a success message with consistent formatting
    nonisolated func logSuccess(_ message: String) {
        print("✅ [\(logPrefix)] \(message)")
    }

    /// Log an error message with consistent formatting
    nonisolated func logError(_ message: String, error: Error? = nil) {
        if let error = error {
            print("❌ [\(logPrefix)] \(message): \(error)")
        } else {
            print("❌ [\(logPrefix)] \(message)")
        }
    }

    /// Log a warning message with consistent formatting
    nonisolated func logWarning(_ message: String) {
        print("⚠️ [\(logPrefix)] \(message)")
    }

    // MARK: - CRUD Operations

    /// Fetch all records with optional filtering
    func fetchAll(
        limit: Int? = nil,
        offset: Int? = nil,
        orderBy: String? = nil,
        ascending: Bool = false
    ) async throws -> [T] {
        logInfo("Fetching all records", emoji: "📥")

        let baseQuery = client.from(tableName).select()

        let result: [T]

        // Build query based on parameters
        if let orderBy = orderBy, let limit = limit, let offset = offset {
            result = try await baseQuery
                .order(orderBy, ascending: ascending)
                .limit(limit)
                .range(from: offset, to: offset + limit - 1)
                .execute().value
        } else if let orderBy = orderBy, let limit = limit {
            result = try await baseQuery
                .order(orderBy, ascending: ascending)
                .limit(limit)
                .execute().value
        } else if let orderBy = orderBy {
            result = try await baseQuery
                .order(orderBy, ascending: ascending)
                .execute().value
        } else if let limit = limit, let offset = offset {
            result = try await baseQuery
                .limit(limit)
                .range(from: offset, to: offset + limit - 1)
                .execute().value
        } else if let limit = limit {
            result = try await baseQuery
                .limit(limit)
                .execute().value
        } else {
            result = try await baseQuery.execute().value
        }

        logSuccess("Fetched \(result.count) records")
        return result
    }

    /// Fetch a single record by ID
    func fetchById(_ id: UUID, cacheKey: String? = nil) async throws -> T? {
        logInfo("Fetching record: \(id)", emoji: "🔍")

        // Try cache first if cache key provided
        if let cacheKey = cacheKey, let cached: T = cache.get(cacheKey) {
            logSuccess("Cache hit for record: \(id)")
            return cached
        }

        let result: [T] = try await client
            .from(tableName)
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value

        guard let record = result.first else {
            logWarning("Record not found: \(id)")
            return nil
        }

        // Cache the result if cache key provided
        if let cacheKey = cacheKey {
            cache.set(cacheKey, value: record, ttl: .userProfiles)
        }

        logSuccess("Fetched record: \(id)")
        return record
    }

    /// Create a new record
    func create<E: Encodable>(_ data: E) async throws -> T {
        logInfo("Creating new record", emoji: "📝")

        let result: T = try await client
            .from(tableName)
            .insert(data)
            .select()
            .single()
            .execute()
            .value

        logSuccess("Created new record")
        return result
    }

    /// Update a record by ID
    func update<E: Encodable>(id: UUID, data: E) async throws -> T {
        logInfo("Updating record: \(id)", emoji: "✏️")

        let result: T = try await client
            .from(tableName)
            .update(data)
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        logSuccess("Updated record: \(id)")
        return result
    }

    /// Update a record by ID (no return value)
    func updateVoid<E: Encodable>(id: UUID, data: E) async throws {
        logInfo("Updating record: \(id)", emoji: "✏️")

        try await client
            .from(tableName)
            .update(data)
            .eq("id", value: id.uuidString)
            .execute()

        logSuccess("Updated record: \(id)")
    }

    /// Delete a record by ID
    func delete(id: UUID) async throws {
        logInfo("Deleting record: \(id)", emoji: "🗑️")

        try await client
            .from(tableName)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        logSuccess("Deleted record: \(id)")
    }

    /// Delete multiple records matching a filter
    func deleteWhere(column: String, value: String) async throws {
        logInfo("Deleting records where \(column) = \(value)", emoji: "🗑️")

        try await client
            .from(tableName)
            .delete()
            .eq(column, value: value)
            .execute()

        logSuccess("Deleted records where \(column) = \(value)")
    }

    // MARK: - Query Helpers

    /// Execute a custom query builder
    func executeQuery<Result: Decodable>(_ queryBuilder: @escaping (PostgrestQueryBuilder) -> PostgrestFilterBuilder) async throws -> [Result] {
        let query = queryBuilder(client.from(tableName))
        return try await query.execute().value
    }

    /// Check if a record exists
    func exists(id: UUID) async throws -> Bool {
        let result: [T] = try await client
            .from(tableName)
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value

        return !result.isEmpty
    }

    /// Count records matching a filter
    func count(column: String? = nil, value: String? = nil) async throws -> Int {
        var query = client
            .from(tableName)
            .select(head: true, count: .exact)

        if let column = column, let value = value {
            query = query.eq(column, value: value)
        }

        let response = try await query.execute()
        return response.count ?? 0
    }

    // MARK: - Batch Operations

    /// Fetch multiple records by IDs in a single query
    func fetchByIds(_ ids: [UUID]) async throws -> [T] {
        guard !ids.isEmpty else { return [] }

        logInfo("Fetching \(ids.count) records by IDs", emoji: "📥")

        let result: [T] = try await client
            .from(tableName)
            .select()
            .in("id", values: ids.map { $0.uuidString })
            .execute()
            .value

        logSuccess("Fetched \(result.count) records")
        return result
    }

    /// Batch fetch user profiles with individual caching (common pattern)
    func fetchProfilesBatched(_ userIds: [UUID]) async throws -> [UserProfile] {
        guard !userIds.isEmpty else { return [] }

        // Check cache for each profile
        var profiles: [UserProfile] = []
        var uncachedIds: [UUID] = []

        for userId in userIds {
            let cacheKey = QueryCache.profileKey(userId: userId.uuidString)
            if let cached: UserProfile = cache.get(cacheKey) {
                profiles.append(cached)
            } else {
                uncachedIds.append(userId)
            }
        }

        // Fetch uncached profiles in a single batch query
        if !uncachedIds.isEmpty {
            let fetchedProfiles: [UserProfile] = try await client
                .from("profiles")
                .select()
                .in("id", values: uncachedIds.map { $0.uuidString })
                .execute()
                .value

            // Cache each fetched profile individually
            for profile in fetchedProfiles {
                let cacheKey = QueryCache.profileKey(userId: profile.id.uuidString)
                cache.set(cacheKey, value: profile, ttl: .userProfiles)
            }

            profiles.append(contentsOf: fetchedProfiles)
        }

        logSuccess("Fetched \(profiles.count) profiles (\(profiles.count - uncachedIds.count) from cache)")
        return profiles
    }

    // MARK: - Cache Management

    /// Invalidate cache for a specific key
    func invalidateCache(_ key: String) {
        cache.invalidate(key)
        logInfo("Invalidated cache: \(key)", emoji: "💾")
    }

    /// Invalidate all caches matching a prefix
    func invalidateCachePrefix(_ prefix: String) {
        cache.invalidatePrefix(prefix)
        logInfo("Invalidated cache prefix: \(prefix)", emoji: "💾")
    }
}
