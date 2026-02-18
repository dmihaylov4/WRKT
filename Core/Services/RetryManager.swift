//
//  RetryManager.swift
//  WRKT
//
//  Automatic retry with exponential backoff
//

import Foundation

/// Configuration for retry behavior
struct RetryConfiguration {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double

    /// Default configuration: 3 attempts with 1s, 2s, 4s delays
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 4.0,
        multiplier: 2.0
    )

    /// Aggressive retry for critical operations: 5 attempts
    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 8.0,
        multiplier: 2.0
    )

    /// Quick retry for non-critical operations: 2 attempts
    static let quick = RetryConfiguration(
        maxAttempts: 2,
        initialDelay: 0.5,
        maxDelay: 1.0,
        multiplier: 2.0
    )
}

/// Result of a retry operation
enum RetryResult<T> {
    case success(T)
    case failure(Error, attemptCount: Int)
}

/// Manager for automatic retry with exponential backoff
@MainActor
final class RetryManager {
    static let shared = RetryManager()

    private init() {}

    // MARK: - Public API

    /// Execute an operation with automatic retry
    /// - Parameters:
    ///   - config: Retry configuration
    ///   - shouldRetry: Optional closure to determine if error is retryable
    ///   - operation: Async operation to execute
    /// - Returns: Result of the operation
    func executeWithRetry<T>(
        config: RetryConfiguration = .default,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: @escaping () async throws -> T
    ) async -> RetryResult<T> {
        var attempt = 0
        var lastError: Error?

        while attempt < config.maxAttempts {
            attempt += 1

            do {
                let result = try await operation()
                return .success(result)
            } catch {
                lastError = error

                // Check if we should retry this error
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    return .failure(error, attemptCount: attempt)
                }

                // If this was the last attempt, don't delay
                if attempt >= config.maxAttempts {
                    break
                }

                // Calculate delay with exponential backoff
                let delay = calculateDelay(
                    attempt: attempt,
                    config: config
                )


                // Wait before next attempt
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // All retries exhausted
        let finalError = lastError ?? NSError(
            domain: "RetryManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error"]
        )

        return .failure(finalError, attemptCount: attempt)
    }

    /// Execute an operation with retry, throwing on failure
    /// - Parameters:
    ///   - config: Retry configuration
    ///   - shouldRetry: Optional closure to determine if error is retryable
    ///   - operation: Async operation to execute
    /// - Returns: Result of the operation
    /// - Throws: Error if all retries fail
    func executeWithRetryThrowing<T>(
        config: RetryConfiguration = .default,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let result = await executeWithRetry(
            config: config,
            shouldRetry: shouldRetry,
            operation: operation
        )

        switch result {
        case .success(let value):
            return value
        case .failure(let error, _):
            throw error
        }
    }

    // MARK: - Private Helpers

    private func calculateDelay(attempt: Int, config: RetryConfiguration) -> TimeInterval {
        // Exponential backoff: initialDelay * (multiplier ^ (attempt - 1))
        let delay = config.initialDelay * pow(config.multiplier, Double(attempt - 1))

        // Cap at max delay, then add jitter (50-100% of capped value)
        let cappedDelay = min(delay, config.maxDelay)
        return cappedDelay * (0.5 + Double.random(in: 0...0.5))
    }

    // MARK: - Retry Predicates

    /// Check if an error is retryable (network errors typically are)
    static func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError

        // Network errors are retryable
        if nsError.domain == NSURLErrorDomain {
            // Some network errors should not be retried
            let nonRetryableCodes: Set<Int> = [
                NSURLErrorBadURL,
                NSURLErrorUnsupportedURL,
                NSURLErrorUserCancelledAuthentication,
                NSURLErrorUserAuthenticationRequired
            ]

            return !nonRetryableCodes.contains(nsError.code)
        }

        // Check error description for retryable keywords
        let desc = error.localizedDescription.lowercased()
        let retryableKeywords = [
            "network",
            "connection",
            "timeout",
            "unreachable",
            "unavailable",
            "timed out",
            "offline"
        ]

        return retryableKeywords.contains { desc.contains($0) }
    }
}

// MARK: - Convenience Extensions

extension RetryManager {
    /// Retry a network fetch operation
    func fetchWithRetry<T>(
        config: RetryConfiguration = .default,
        _ operation: @escaping () async throws -> T
    ) async -> RetryResult<T> {
        await executeWithRetry(
            config: config,
            shouldRetry: { RetryManager.isRetryable($0) },
            operation: operation
        )
    }

    /// Retry an upload operation with aggressive config
    func uploadWithRetry<T>(
        _ operation: @escaping () async throws -> T
    ) async -> RetryResult<T> {
        await executeWithRetry(
            config: .aggressive,
            shouldRetry: { RetryManager.isRetryable($0) },
            operation: operation
        )
    }
}
