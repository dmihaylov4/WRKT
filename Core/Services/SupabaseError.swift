import Foundation

enum SupabaseError: LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case networkError(Error)
    case serverError(String)
    case usernameTaken
    case invalidUsername
    case profileNotFound
    case emailNotVerified
    case custom(message: String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to perform this action"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .usernameTaken:
            return "This username is already taken"
        case .invalidUsername:
            return "Username must be 3-30 characters (letters, numbers, underscore only)"
        case .profileNotFound:
            return "Profile not found"
        case .emailNotVerified:
            return "Please verify your email address before continuing"
        case .custom(let message):
            return message
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
