import Foundation
import SwiftUI
import Kingfisher

/// Service for managing image caching with Kingfisher
/// Provides centralized configuration for image loading and caching
@MainActor
final class ImageCacheService {
    static let shared = ImageCacheService()

    private init() {
        configureCache()
    }

    /// Configure Kingfisher cache settings
    private func configureCache() {
        // Set memory cache limit (50MB)
        KingfisherManager.shared.cache.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024

        // Set disk cache limit (100MB)
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = 100 * 1024 * 1024

        // Set cache expiration (7 days)
        KingfisherManager.shared.cache.diskStorage.config.expiration = .days(7)

        // Set download timeout (30 seconds)
        KingfisherManager.shared.downloader.downloadTimeout = 30.0
    }

    /// Clear all cached images
    func clearCache() {
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
    }

    /// Clear expired cached images
    func clearExpiredCache() {
        KingfisherManager.shared.cache.cleanExpiredDiskCache()
    }

    /// Get cache size in bytes
    func getCacheSize() async -> UInt {
        do {
            return try await KingfisherManager.shared.cache.diskStorageSize
        } catch {
            return 0
        }
    }
}

// MARK: - Placeholder Images

enum PlaceholderImage {
    static let avatar = Image(systemName: "person.circle.fill")
    static let workout = Image(systemName: "photo")
    static let general = Image(systemName: "photo.fill")
}
