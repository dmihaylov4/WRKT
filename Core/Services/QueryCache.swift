//
//  QueryCache.swift
//  WRKT
//
//  In-memory query result caching with TTL
//

import Foundation

/// Cached value with expiration
private struct CachedValue<T> {
    let value: T
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Time-to-live configurations for different data types
struct CacheTTL {
    let seconds: TimeInterval

    /// Feed posts: 5 minutes (frequent updates expected)
    static let feedPosts = CacheTTL(seconds: 5 * 60)

    /// User profiles: 15 minutes (rarely change)
    static let userProfiles = CacheTTL(seconds: 15 * 60)

    /// Friends list: 10 minutes (occasional changes)
    static let friendsList = CacheTTL(seconds: 10 * 60)

    /// Notifications: 2 minutes (need fresh data)
    static let notifications = CacheTTL(seconds: 2 * 60)

    /// Post details: 5 minutes
    static let postDetails = CacheTTL(seconds: 5 * 60)

    /// User stats: 30 minutes (expensive to calculate)
    static let userStats = CacheTTL(seconds: 30 * 60)

    /// Custom TTL
    static func custom(seconds: TimeInterval) -> CacheTTL {
        CacheTTL(seconds: seconds)
    }
}

/// In-memory cache for query results with automatic expiration
@MainActor
final class QueryCache {
    static let shared = QueryCache()

    private var cache: [String: Any] = [:]
    private let lock = NSLock()

    private init() {
        // Start cleanup timer
        startCleanupTimer()
    }

    // MARK: - Public API

    /// Get cached value if exists and not expired
    func get<T>(_ key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached = cache[key] as? CachedValue<T> else {
            return nil
        }

        if cached.isExpired {
            cache.removeValue(forKey: key)
            return nil
        }

        return cached.value
    }

    /// Set cached value with TTL
    func set<T>(_ key: String, value: T, ttl: CacheTTL) {
        lock.lock()
        defer { lock.unlock() }

        let expiresAt = Date().addingTimeInterval(ttl.seconds)
        cache[key] = CachedValue(value: value, expiresAt: expiresAt)

    }

    /// Remove specific cache entry
    func invalidate(_ key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
    }

    /// Remove all cache entries matching prefix
    func invalidatePrefix(_ prefix: String) {
        lock.lock()
        defer { lock.unlock() }

        let keysToRemove = cache.keys.filter { $0.hasPrefix(prefix) }
        keysToRemove.forEach { cache.removeValue(forKey: $0) }

    }

    /// Clear all cache
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        let count = cache.count
        cache.removeAll()

    }

    /// Get cache statistics
    func stats() -> CacheStats {
        lock.lock()
        defer { lock.unlock() }

        let totalEntries = cache.count
        var expiredEntries = 0
        var totalSize = 0

        for (_, value) in cache {
            if let cached = value as? any CachedValueProtocol {
                if cached.isExpiredValue {
                    expiredEntries += 1
                }
            }
            // Rough size estimation
            totalSize += MemoryLayout.size(ofValue: value)
        }

        return CacheStats(
            totalEntries: totalEntries,
            expiredEntries: expiredEntries,
            estimatedSizeBytes: totalSize
        )
    }

    // MARK: - Helper Methods

    /// Fetch with cache (fetch from cache or execute fetch function)
    func fetchWithCache<T>(
        key: String,
        ttl: CacheTTL,
        fetch: () async throws -> T
    ) async throws -> T {
        // Check cache first
        if let cached: T = get(key) {
            return cached
        }

        // Cache miss - fetch from source
        let value = try await fetch()

        // Store in cache
        set(key, value: value, ttl: ttl)

        return value
    }

    // MARK: - Cache Key Generators

    static func feedKey(userId: String, cursor: String?) -> String {
        if let cursor = cursor {
            return "feed:\(userId):\(cursor)"
        }
        return "feed:\(userId):initial"
    }

    static func profileKey(userId: String) -> String {
        "profile:\(userId)"
    }

    static func friendsListKey(userId: String) -> String {
        "friends:\(userId)"
    }

    static func notificationsKey(userId: String) -> String {
        "notifications:\(userId)"
    }

    static func postDetailsKey(postId: String) -> String {
        "post:\(postId)"
    }

    static func userStatsKey(userId: String) -> String {
        "stats:\(userId)"
    }

    static func postLikesKey(postId: String) -> String {
        "likes:\(postId)"
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        // Clean up expired entries every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpired()
            }
        }
    }

    private func cleanupExpired() {
        lock.lock()
        defer { lock.unlock() }

        let initialCount = cache.count

        cache = cache.filter { _, value in
            if let cached = value as? any CachedValueProtocol {
                return !cached.isExpiredValue
            }
            return true
        }

        let removed = initialCount - cache.count
        if removed > 0 {
        }
    }
}

// MARK: - Supporting Types

struct CacheStats {
    let totalEntries: Int
    let expiredEntries: Int
    let estimatedSizeBytes: Int

    var hitRate: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(totalEntries - expiredEntries) / Double(totalEntries)
    }
}

// Protocol for checking expiration on any cached value type
private protocol CachedValueProtocol {
    var isExpiredValue: Bool { get }
}

extension CachedValue: CachedValueProtocol {
    var isExpiredValue: Bool {
        isExpired
    }
}

// MARK: - Convenience Extensions

extension QueryCache {
    /// Invalidate all feed caches
    func invalidateAllFeeds() {
        invalidatePrefix("feed:")
    }

    /// Invalidate all profile caches
    func invalidateAllProfiles() {
        invalidatePrefix("profile:")
    }

    /// Invalidate all friends list caches
    func invalidateAllFriendsLists() {
        invalidatePrefix("friends:")
    }

    /// Invalidate all notification caches
    func invalidateAllNotifications() {
        invalidatePrefix("notifications:")
    }

    /// Invalidate cache for specific user (all related data)
    func invalidateUser(_ userId: String) {
        invalidate(QueryCache.profileKey(userId: userId))
        invalidate(QueryCache.friendsListKey(userId: userId))
        invalidate(QueryCache.notificationsKey(userId: userId))
        invalidate(QueryCache.userStatsKey(userId: userId))
        invalidatePrefix("feed:\(userId)")
    }

    /// Invalidate cache for specific post (all related data)
    func invalidatePost(_ postId: String) {
        invalidate(QueryCache.postDetailsKey(postId: postId))
        invalidate(QueryCache.postLikesKey(postId: postId))
        invalidateAllFeeds() // Post might appear in multiple feeds
    }
}
