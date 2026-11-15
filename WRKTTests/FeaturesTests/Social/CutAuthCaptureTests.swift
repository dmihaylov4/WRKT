import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering of the Cut sign-in screens: no hosts, no auth service, no requests.
/// Every address is a fixture at example.com. Opt in with TEST_RUNNER_VOLIA_CAPTURE_WELCOME=1.
@MainActor
@Suite(.serialized)
struct CutAuthCaptureTests {
    nonisolated static let names = [
        "login-empty", "login-filled", "login-loading", "login-error", "login-ax", "login-ax-bottom",
        "signup-empty", "signup-valid", "signup-email-invalid", "signup-username-invalid", "signup-weak",
        "signup-mismatch", "signup-server-error", "signup-loading", "signup-ax", "signup-ax-bottom",
        "reset-empty", "reset-sending", "reset-sent", "reset-error",
        "newpassword-empty", "newpassword-mismatch", "newpassword-success"
    ]
    nonisolated static var selectedNames: [String] {
        guard let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"], names.contains(selected) else { return names }
        return [selected]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WELCOME"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        try await CutWelcomeCapture.render(name: name, settle: name.hasPrefix("reset") || name.hasPrefix("newpassword") ? 3 : 2) {
            makeScene(name)
        }
    }

    private enum F {
        static let email = "fixture@example.com"
        static let password = "Fixture12"
    }

    @ViewBuilder private func makeScene(_ name: String) -> some View {
        switch name {
        case "login-empty", "login-ax", "login-ax-bottom": login(email: "", password: "")
        case "login-filled": login(email: F.email, password: F.password)
        case "login-loading": login(email: F.email, password: F.password, loading: true)
        case "login-error": login(email: F.email, password: F.password, error: "Invalid login credentials")
        case _ where name.hasPrefix("signup"): signupScene(name)
        case _ where name.hasPrefix("reset"):
            login(email: "", password: "").sheet(isPresented: .constant(true)) { resetScene(name) }
        default:
            Color.black.ignoresSafeArea().sheet(isPresented: .constant(true)) { newPasswordScene(name) }
        }
    }

    private func login(email: String, password: String, loading: Bool = false, error: String? = nil) -> some View {
        NavigationStack {
            CutLoginView(model: CutLoginLogic.model(email: email, password: password, isLoading: loading, error: error),
                         email: .constant(email), password: .constant(password))
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func signupScene(_ name: String) -> some View {
        var form = CutSignupForm()
        var error: String?
        var flagged: CutSignupField?
        var loading = false
        switch name {
        case "signup-valid", "signup-loading", "signup-ax", "signup-ax-bottom":
            form = .init(username: "fixture_user", name: "Fixture", email: F.email, password: F.password, confirm: F.password, agreedToTerms: true)
            loading = name == "signup-loading"
        case "signup-email-invalid":
            form = .init(username: "fixture_user", name: "", email: "fixture@example", password: "", confirm: "", agreedToTerms: false)
        case "signup-username-invalid":
            form = .init(username: "fx", name: "", email: F.email, password: "", confirm: "", agreedToTerms: false)
        case "signup-weak":
            form = .init(username: "fixture_user", name: "", email: F.email, password: "fixture", confirm: "", agreedToTerms: true)
        case "signup-mismatch":
            form = .init(username: "fixture_user", name: "", email: F.email, password: F.password, confirm: "Fixture1", agreedToTerms: true)
        case "signup-server-error":
            form = .init(username: "fixture_user", name: "", email: F.email, password: F.password, confirm: F.password, agreedToTerms: true)
            error = "This username is already taken"
            flagged = .username
        default: break
        }
        return NavigationStack {
            CutSignupView(model: CutSignupLogic.model(form, isLoading: loading, error: error, flagged: flagged), form: .constant(form))
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func resetScene(_ name: String) -> some View {
        let email = name == "reset-empty" ? "" : F.email
        return CutResetPasswordView(
            model: CutPasswordLogic.reset(email: email, sentTo: name == "reset-sent" ? F.email : nil,
                                          isLoading: name == "reset-sending",
                                          error: name == "reset-error" ? CutPasswordLogic.resetError("Email rate limit exceeded") : nil),
            email: .constant(email))
    }

    private func newPasswordScene(_ name: String) -> some View {
        let password = name == "newpassword-empty" ? "" : "Fixture123"
        let confirm = name == "newpassword-mismatch" ? "Fixture12" : password
        return CutNewPasswordView(
            model: CutPasswordLogic.newPassword(password, confirm, updated: name == "newpassword-success", isLoading: false, error: nil),
            password: .constant(password), confirm: .constant(confirm))
    }
}
