//
//  CutPasswordModel.swift
//  WRKT
//
//  The two password sheets. Reset password (ForgotPasswordView): an email with an @ enables Send
//  reset link; the same friendly messages for rate limits and unknown accounts; then a "check your
//  email" state naming the address. Set new password (SetNewPasswordView): at least 8 characters
//  and a matching repeat, the same checklist, then a success state.
//

import Foundation

struct CutResetPasswordModel: Equatable {
    enum Stage: Equatable {
        case form
        /// The request went out for this address.
        case sent(email: String)
    }

    var stage: Stage
    var title: String
    var subtitle: String
    /// ForgotPasswordView.canSend.
    var canSend: Bool
    var sendEnabled: Bool
    var isLoading: Bool
    var error: String?
}

struct CutNewPasswordModel: Equatable {
    struct Check: Equatable {
        enum State: Equatable { case pending, met, failed }
        var text: String
        var state: State
    }

    var isUpdated: Bool
    var title: String
    var subtitle: String
    /// The legacy checklist: "At least 8 characters", then match or mismatch once the repeat is typed.
    var checks: [Check]
    var canSubmit: Bool
    var isLoading: Bool
    var error: String?
}

enum CutPasswordLogic {
    // MARK: Reset

    static let resetTitle = "Reset password"
    static let resetLine = "We will email you a link to set a new one."
    static let sendTitle = "Send reset link"
    static let sentTitle = "Check your email"
    static let sentLine = "We've sent password reset instructions to:"
    static let rateLimitMessage = "Too many attempts. Please wait a few minutes before trying again."
    static let noAccountMessage = "No account found with this email address."

    /// ForgotPasswordView.canSend.
    static func canSendReset(_ email: String) -> Bool {
        !email.isEmpty && email.contains("@")
    }

    /// ForgotPasswordView's friendlier messages for two known failures; anything else as it came.
    static func resetError(_ description: String) -> String {
        let text = description.lowercased()
        if text.contains("rate limit") { return rateLimitMessage }
        if text.contains("not found") || text.contains("no user") { return noAccountMessage }
        return description
    }

    static func reset(email: String, sentTo: String?, isLoading: Bool, error: String?) -> CutResetPasswordModel {
        if let sentTo {
            return .init(stage: .sent(email: sentTo), title: sentTitle, subtitle: sentLine,
                         canSend: false, sendEnabled: false, isLoading: false, error: nil)
        }
        let can = canSendReset(email)
        return .init(stage: .form, title: resetTitle, subtitle: resetLine, canSend: can,
                     sendEnabled: can && !isLoading, isLoading: isLoading, error: error)
    }

    // MARK: New password

    static let newTitle = "Set new password"
    static let newLine = "Choose a new password for your account."
    static let updateTitle = "Update password"
    static let updatedTitle = "Password updated"
    static let updatedLine = "Your password has been successfully changed. You can now log in with your new password."
    static let lengthCheck = "At least 8 characters"
    static let matchCheck = "Passwords match"
    static let mismatchCheck = "Passwords don't match"

    /// SetNewPasswordView.isValidPassword.
    static func isLongEnough(_ password: String) -> Bool { password.count >= 8 }

    /// SetNewPasswordView.passwordsMatch.
    static func passwordsMatch(_ password: String, _ confirm: String) -> Bool {
        !password.isEmpty && password == confirm
    }

    /// SetNewPasswordView.canSubmit.
    static func canSubmit(_ password: String, _ confirm: String, isLoading: Bool) -> Bool {
        isLongEnough(password) && passwordsMatch(password, confirm) && !isLoading
    }

    static func newPassword(_ password: String, _ confirm: String, updated: Bool, isLoading: Bool, error: String?) -> CutNewPasswordModel {
        if updated {
            return .init(isUpdated: true, title: updatedTitle, subtitle: updatedLine, checks: [],
                         canSubmit: false, isLoading: false, error: nil)
        }
        var checks = [CutNewPasswordModel.Check(text: lengthCheck, state: isLongEnough(password) ? .met : .pending)]
        if !confirm.isEmpty {
            let match = passwordsMatch(password, confirm)
            checks.append(.init(text: match ? matchCheck : mismatchCheck, state: match ? .met : .failed))
        }
        return .init(isUpdated: false, title: newTitle, subtitle: newLine, checks: checks,
                     canSubmit: canSubmit(password, confirm, isLoading: isLoading), isLoading: isLoading, error: error)
    }
}
