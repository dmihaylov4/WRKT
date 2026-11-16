//
//  CutSignupModel.swift
//  WRKT
//
//  The Cut sign up screen. Every rule and message is SignupView's: the email pattern, the username
//  rule (3 to 30 letters, numbers or underscores), the four-point password strength with Fair or
//  better required, matching passwords, the terms box, and which field a server error points at.
//  Fields are in the mock's order and Return moves down them in that order.
//

import Foundation

enum CutSignupField: Hashable, CaseIterable {
    case username, name, email, password, confirm
}

struct CutSignupForm: Equatable {
    var username = ""
    var name = ""
    var email = ""
    var password = ""
    var confirm = ""
    var agreedToTerms = false
}

struct CutSignupModel: Equatable {
    enum StrengthTone: Equatable { case weak, fair, good, strong }

    struct Strength: Equatable {
        /// 0 to 4: one point each for 8 characters, a number, a capital and a symbol.
        var score: Int
        var label: String
        var tone: StrengthTone
    }

    /// The line under Username: the rule, or SignupView's message once the name breaks it.
    var usernameNote: String
    var usernameNoteIsWarning: Bool
    var emailMessage: String?
    var mismatchMessage: String?
    /// Nil while the password is empty, as legacy hid the meter.
    var strength: Strength?
    var canSignUp: Bool
    var buttonEnabled: Bool
    var isLoading: Bool
    var error: String?
    var flagsUsername: Bool
    var flagsEmail: Bool
}

enum CutSignupLogic {
    static let title = "Create account"
    static let usernameRule = "3 to 30 letters, numbers or underscores."
    static let termsText = "I agree to the terms and conditions"

    // Legacy messages, word for word.
    static let emailInvalidMessage = "Please enter a valid email address"
    static let usernameInvalidMessage = "Username must be 3-30 characters (letters, numbers, underscore only)"
    static let mismatchMessage = "Passwords do not match"

    /// SignupView.isValidUsername.
    static func isValidUsername(_ username: String) -> Bool {
        let length = username.count
        guard length >= 3 && length <= 30 else { return false }
        return NSPredicate(format: "SELF MATCHES %@", "^[a-zA-Z0-9_]+$").evaluate(with: username)
    }

    /// SignupView.passwordStrength.
    static func passwordStrength(_ password: String) -> Int {
        var strength = 0
        if password.count >= 8 { strength += 1 }
        if password.contains(where: { $0.isNumber }) { strength += 1 }
        if password.contains(where: { $0.isUppercase }) { strength += 1 }
        if password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) { strength += 1 }
        return strength
    }

    static func strength(_ password: String) -> CutSignupModel.Strength? {
        guard !password.isEmpty else { return nil }
        let score = passwordStrength(password)
        switch score {
        case 0...1: return .init(score: score, label: "Weak", tone: .weak)
        case 2: return .init(score: score, label: "Fair", tone: .fair)
        case 3: return .init(score: score, label: "Good", tone: .good)
        default: return .init(score: score, label: "Strong", tone: .strong)
        }
    }

    /// SignupView.canSignup.
    static func canSignUp(_ form: CutSignupForm) -> Bool {
        !form.email.isEmpty &&
        CutAuthValidation.isValidEmail(form.email) &&
        !form.username.isEmpty &&
        isValidUsername(form.username) &&
        !form.password.isEmpty &&
        form.password == form.confirm &&
        passwordStrength(form.password) >= 2 &&
        form.agreedToTerms
    }

    static func emailMessage(_ email: String) -> String? {
        !email.isEmpty && !CutAuthValidation.isValidEmail(email) ? emailInvalidMessage : nil
    }

    static func usernameMessage(_ username: String) -> String? {
        !username.isEmpty && !isValidUsername(username) ? usernameInvalidMessage : nil
    }

    static func mismatch(_ password: String, _ confirm: String) -> String? {
        !confirm.isEmpty && password != confirm ? mismatchMessage : nil
    }

    /// The field a server error points at, as SignupView decided it (case sensitive, as before).
    static func flaggedField(for message: String) -> CutSignupField? {
        if message.contains("username") || message.contains("already taken") { return .username }
        if message.contains("email") { return .email }
        return nil
    }

    /// Return moves to the next field; on the last one it closes the keyboard.
    static func next(after field: CutSignupField) -> CutSignupField? {
        let all = CutSignupField.allCases
        guard let index = all.firstIndex(of: field), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    static func model(_ form: CutSignupForm, isLoading: Bool, error: String?, flagged: CutSignupField?) -> CutSignupModel {
        let usernameMessage = usernameMessage(form.username)
        let can = canSignUp(form)
        return .init(
            usernameNote: usernameMessage ?? usernameRule,
            usernameNoteIsWarning: usernameMessage != nil,
            emailMessage: emailMessage(form.email),
            mismatchMessage: mismatch(form.password, form.confirm),
            strength: strength(form.password),
            canSignUp: can,
            buttonEnabled: can && !isLoading,
            isLoading: isLoading,
            error: error,
            flagsUsername: flagged == .username,
            flagsEmail: flagged == .email
        )
    }
}
