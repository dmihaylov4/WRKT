//
//  AppLogger.swift
//  WRKT
//
//  Centralized logging using Apple's unified logging system (os.Logger)
//  Provides structured, performant logging with privacy controls
//

import Foundation
import OSLog

/// Centralized logging utility for WRKT app
/// Uses Apple's unified logging system for better performance and debugging
enum AppLogger {

    // MARK: - Logger Categories

    /// App lifecycle and initialization
    static let app = Logger(subsystem: subsystem, category: "App")

    /// Data persistence and storage
    static let storage = Logger(subsystem: subsystem, category: "Storage")

    /// Workout tracking and sessions
    static let workout = Logger(subsystem: subsystem, category: "Workout")

    /// HealthKit integration
    static let health = Logger(subsystem: subsystem, category: "Health")

    /// Rewards and gamification
    static let rewards = Logger(subsystem: subsystem, category: "Rewards")

    /// UI and user interactions
    static let ui = Logger(subsystem: subsystem, category: "UI")

    /// Network and API calls
    static let network = Logger(subsystem: subsystem, category: "Network")

    /// Performance and analytics
    static let performance = Logger(subsystem: subsystem, category: "Performance")

    /// Statistics and data aggregation
    static let statistics = Logger(subsystem: subsystem, category: "Statistics")

    /// Database persistence operations
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    // MARK: - Configuration

    private static let subsystem = "com.dmihaylov.trak"

    // MARK: - Convenience Methods

    /// Log debug information (only visible in debug builds)
    static func debug(_ message: String, category: Logger? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let logger = category ?? app
        let fileName = (file as NSString).lastPathComponent
        logger.debug("[\(fileName):\(line)] \(function) - \(message)")
        #endif
    }

    /// Log informational messages
    static func info(_ message: String, category: Logger? = nil) {
        let logger = category ?? app
        logger.info("\(message)")
    }

    /// Log warnings that don't prevent functionality
    static func warning(_ message: String, category: Logger? = nil) {
        let logger = category ?? app
        logger.warning("⚠️ \(message)")
    }

    /// Log errors that affect functionality
    static func error(_ message: String, error: Error? = nil, category: Logger? = nil) {
        let logger = category ?? app
        if let error = error {
            logger.error("❌ \(message): \(error.localizedDescription)")
        } else {
            logger.error("❌ \(message)")
        }
    }

    /// Log critical errors that may cause crashes
    static func critical(_ message: String, error: Error? = nil, category: Logger? = nil) {
        let logger = category ?? app
        if let error = error {
            logger.critical("🚨 CRITICAL: \(message): \(error.localizedDescription)")
        } else {
            logger.critical("🚨 CRITICAL: \(message)")
        }
    }

    /// Log successful operations
    static func success(_ message: String, category: Logger? = nil) {
        let logger = category ?? app
        logger.info("✅ \(message)")
    }
}

// MARK: - Usage Examples
/*

 // Basic logging (uses default .app category)
 AppLogger.info("User logged in")
 AppLogger.error("Failed to fetch data", error: error)

 // Category-specific logging
 AppLogger.success("Workout saved", category: AppLogger.workout)
 AppLogger.warning("HealthKit sync delayed", category: AppLogger.health)

 // Debug logging (only in debug builds)
 AppLogger.debug("Processing \(count) items")

 // Critical errors
 AppLogger.critical("Database corrupted", error: error, category: AppLogger.storage)

 */
