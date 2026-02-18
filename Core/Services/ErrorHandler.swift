//
//  ErrorHandler.swift
//  WRKT
//
//  Centralized error handling with user-friendly messages
//

import Foundation

/// User-friendly error with actionable message
struct UserFriendlyError: Error, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let suggestion: String?
    let isRetryable: Bool
    let originalError: Error?

    init(
        title: String,
        message: String,
        suggestion: String? = nil,
        isRetryable: Bool = true,
        originalError: Error? = nil
    ) {
        self.title = title
        self.message = message
        self.suggestion = suggestion
        self.isRetryable = isRetryable
        self.originalError = originalError
    }
}

/// Centralized error handler for converting technical errors to user-friendly messages
final class ErrorHandler {
    static let shared = ErrorHandler()

    private init() {}

    // MARK: - Public API

    /// Convert any error to a user-friendly error
    func handleError(_ error: Error, context: ErrorContext = .general) -> UserFriendlyError {
        // Check if already user-friendly
        if let userError = error as? UserFriendlyError {
            return userError
        }

        // Parse error based on context
        switch context {
        case .feed:
            return handleFeedError(error)
        case .post:
            return handlePostError(error)
        case .imageUpload:
            return handleImageUploadError(error)
        case .authentication:
            return handleAuthError(error)
        case .friendship:
            return handleFriendshipError(error)
        case .notification:
            return handleNotificationError(error)
        case .challenges:
            return handleChallengesError(error)
        case .battles:
            return handleBattlesError(error)
        case .general:
            return handleGeneralError(error)
        }
    }

    /// Log error for debugging
    func logError(_ error: Error, context: ErrorContext) {

        if let userError = error as? UserFriendlyError,
           let original = userError.originalError {
        }
    }

    // MARK: - Context-Specific Handlers

    private func handleFeedError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Can't Load Feed",
                message: "Please check your internet connection and try again.",
                suggestion: "Make sure you're connected to WiFi or cellular data.",
                isRetryable: true,
                originalError: error
            )
        }

        if isAuthError(error) {
            return UserFriendlyError(
                title: "Session Expired",
                message: "Your session has expired. Please log in again.",
                suggestion: nil,
                isRetryable: false,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Can't Load Feed",
            message: "Something went wrong while loading your feed.",
            suggestion: "Try again in a moment.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handlePostError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Can't Share Workout",
                message: "Please check your internet connection and try again.",
                suggestion: "Your workout will be saved locally and you can share it later.",
                isRetryable: true,
                originalError: error
            )
        }

        let errorDesc = error.localizedDescription
        if errorDesc.contains("storage") || errorDesc.contains("upload") {
            return UserFriendlyError(
                title: "Upload Failed",
                message: "We couldn't upload your workout images.",
                suggestion: "Try again with fewer or smaller images.",
                isRetryable: true,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Can't Share Workout",
            message: "Something went wrong while sharing your workout.",
            suggestion: "Please try again.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleImageUploadError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Upload Failed",
                message: "Please check your internet connection.",
                suggestion: "Try uploading when you have a stronger connection.",
                isRetryable: true,
                originalError: error
            )
        }

        let errorDesc = error.localizedDescription.lowercased()

        if errorDesc.contains("size") || errorDesc.contains("large") {
            return UserFriendlyError(
                title: "Image Too Large",
                message: "The image you selected is too large to upload.",
                suggestion: "Try selecting a smaller image or reducing its size.",
                isRetryable: false,
                originalError: error
            )
        }

        if errorDesc.contains("format") || errorDesc.contains("type") {
            return UserFriendlyError(
                title: "Invalid Image Format",
                message: "The image format is not supported.",
                suggestion: "Please select a JPEG or PNG image.",
                isRetryable: false,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Upload Failed",
            message: "We couldn't upload your image.",
            suggestion: "Please try again with a different image.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleAuthError(_ error: Error) -> UserFriendlyError {
        let errorDesc = error.localizedDescription.lowercased()

        if errorDesc.contains("invalid") && errorDesc.contains("credentials") {
            return UserFriendlyError(
                title: "Incorrect Login",
                message: "The email or password you entered is incorrect.",
                suggestion: "Check your credentials and try again.",
                isRetryable: false,
                originalError: error
            )
        }

        if errorDesc.contains("email") && errorDesc.contains("exists") {
            return UserFriendlyError(
                title: "Email Already Used",
                message: "An account with this email already exists.",
                suggestion: "Try logging in instead, or use a different email.",
                isRetryable: false,
                originalError: error
            )
        }

        if errorDesc.contains("password") && errorDesc.contains("weak") {
            return UserFriendlyError(
                title: "Weak Password",
                message: "Your password must be at least 8 characters long.",
                suggestion: "Use a mix of letters, numbers, and symbols.",
                isRetryable: false,
                originalError: error
            )
        }

        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Connection Error",
                message: "Can't connect to the server.",
                suggestion: "Check your internet connection and try again.",
                isRetryable: true,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Authentication Error",
            message: "Something went wrong during authentication.",
            suggestion: "Please try again.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleFriendshipError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Connection Error",
                message: "Can't process friend request right now.",
                suggestion: "Check your connection and try again.",
                isRetryable: true,
                originalError: error
            )
        }

        let errorDesc = error.localizedDescription.lowercased()

        if errorDesc.contains("already") && errorDesc.contains("friend") {
            return UserFriendlyError(
                title: "Already Friends",
                message: "You're already friends with this person.",
                suggestion: nil,
                isRetryable: false,
                originalError: error
            )
        }

        if errorDesc.contains("pending") {
            return UserFriendlyError(
                title: "Request Pending",
                message: "A friend request is already pending.",
                suggestion: nil,
                isRetryable: false,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Friend Request Failed",
            message: "Something went wrong with the friend request.",
            suggestion: "Please try again.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleNotificationError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Can't Load Notifications",
                message: "Please check your internet connection.",
                suggestion: nil,
                isRetryable: true,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Can't Load Notifications",
            message: "Something went wrong loading your notifications.",
            suggestion: "Try again in a moment.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleChallengesError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Can't Load Challenges",
                message: "Please check your internet connection and try again.",
                suggestion: nil,
                isRetryable: true,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Challenge Error",
            message: "Something went wrong with this challenge.",
            suggestion: "Please try again.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleBattlesError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Can't Load Battles",
                message: "Please check your internet connection and try again.",
                suggestion: nil,
                isRetryable: true,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Battle Error",
            message: "Something went wrong with this battle.",
            suggestion: "Please try again.",
            isRetryable: true,
            originalError: error
        )
    }

    private func handleGeneralError(_ error: Error) -> UserFriendlyError {
        if isNetworkError(error) {
            return UserFriendlyError(
                title: "Connection Error",
                message: "Please check your internet connection and try again.",
                suggestion: nil,
                isRetryable: true,
                originalError: error
            )
        }

        return UserFriendlyError(
            title: "Something Went Wrong",
            message: "An unexpected error occurred.",
            suggestion: "Please try again.",
            isRetryable: true,
            originalError: error
        )
    }

    // MARK: - Error Classification

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // Check for URLError codes
        if nsError.domain == NSURLErrorDomain {
            return true
        }

        // Check error description
        let desc = error.localizedDescription.lowercased()
        return desc.contains("network") ||
               desc.contains("internet") ||
               desc.contains("connection") ||
               desc.contains("offline") ||
               desc.contains("timed out") ||
               desc.contains("unreachable")
    }

    private func isAuthError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        return desc.contains("unauthorized") ||
               desc.contains("unauthenticated") ||
               desc.contains("token") ||
               desc.contains("session")
    }
}

// MARK: - Error Context

enum ErrorContext: String {
    case feed = "Feed"
    case post = "Post"
    case imageUpload = "ImageUpload"
    case authentication = "Auth"
    case friendship = "Friendship"
    case notification = "Notification"
    case challenges = "Challenges"
    case battles = "Battles"
    case general = "General"
}
