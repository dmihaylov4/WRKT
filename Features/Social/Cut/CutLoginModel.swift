//
//  CutLoginModel.swift
//  WRKT
//
//  The Cut log in screen: the mark, one big line, Apple and Google, email and password, Log in,
//  Forgot password, and at the bottom Create an account and Use the app without an account.
//  Every rule is LoginView's: Log in needs an email that passes the same pattern and a password;
//  the provider buttons and Log in are off while a request runs.
//

import Foundation

/// The email pattern LoginView and SignupView check, unchanged.
enum CutAuthValidation {
    nonisolated static let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"

    static func isValidEmail(_ email: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", emailPattern).evaluate(with: email)
    }
}

enum CutLoginField: Hashable { case email, password }

struct CutLoginModel: Equatable {
    var title: String
    var line: String
    /// LoginView.canLogin: the form is complete.
    var canLogIn: Bool
    /// Log in can be pressed: complete and nothing running.
    var logInEnabled: Bool
    /// Apple and Google can be pressed: nothing running.
    var providersEnabled: Bool
    var isLoading: Bool
    var error: String?
}

enum CutLoginLogic {
    static let title = "Train with friends"
    static let line = "Log in to share workouts and compete."
    static let divider = "or with email"
    static let logIn = "Log in"
    static let forgotPassword = "Forgot password?"
    static let createAccount = "Create an account"
    static let withoutAccount = "Use the app without an account"

    /// LoginView.canLogin.
    static func canLogIn(email: String, password: String) -> Bool {
        !email.isEmpty && !password.isEmpty && CutAuthValidation.isValidEmail(email)
    }

    static func model(email: String, password: String, isLoading: Bool, error: String?) -> CutLoginModel {
        let complete = canLogIn(email: email, password: password)
        return .init(title: title, line: line, canLogIn: complete, logInEnabled: complete && !isLoading,
                     providersEnabled: !isLoading, isLoading: isLoading, error: error)
    }

    /// Return on the email field moves to the password field.
    static func next(after field: CutLoginField) -> CutLoginField? {
        field == .email ? .password : nil
    }

    /// Return on the password field logs in only when the form is complete, as legacy did.
    static func submitsFromPassword(email: String, password: String) -> Bool {
        canLogIn(email: email, password: password)
    }
}
