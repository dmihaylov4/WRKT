//
//  CutLoginHost.swift
//  WRKT
//
//  Wires the Cut log in screen exactly as LoginView did: the same SupabaseAuthService calls and
//  haptics, the same error text, the email verification and OAuth username sheets on the same
//  triggers, the reset password sheet, the sign up screen pushed in the same NavigationStack,
//  dismissal when a user appears, and "Use the app without an account" turning on local mode.
//

import AuthenticationServices
import SwiftUI
import UIKit

struct CutLoginHost: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: SupabaseAuthService
    @StateObject private var settings = AppSettings.shared

    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false
    @State private var showEmailVerification = false
    @State private var showSignup = false
    @State private var errorMessage: String?
    @State private var showUsernameSetup = false

    var body: some View {
        NavigationStack {
            CutLoginView(
                model: CutLoginLogic.model(email: email, password: password, isLoading: authService.isLoading, error: errorMessage),
                email: $email,
                password: $password,
                actions: CutLoginActions(
                    logIn: { Task { await handleLogin() } },
                    apple: { Task { await handleAppleSignIn() } },
                    google: { Task { await handleGoogleSignIn() } },
                    forgotPassword: { showForgotPassword = true },
                    createAccount: { showSignup = true },
                    useWithoutAccount: useWithoutAccount
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSignup) {
                SignupView()
            }
            .sheet(isPresented: $showEmailVerification) {
                EmailVerificationView()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
            .onChange(of: authService.needsEmailVerification) { _, needsVerification in
                showEmailVerification = needsVerification
            }
            .sheet(isPresented: $showUsernameSetup, onDismiss: {
                if authService.currentUser != nil {
                    dismiss()
                }
            }) {
                OAuthUsernameSetupView()
                    .environmentObject(authService)
            }
            .onReceive(authService.$currentUser) { newUser in
                // Dismiss when a user is signed in (for example after email verification).
                if newUser != nil {
                    dismiss()
                }
            }
        }
    }

    // MARK: Actions (LoginView's, unchanged)

    private func handleLogin() async {
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await authService.signIn(email: email, password: password)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleSignIn() async {
        errorMessage = nil
        guard let window = activeWindow else { return }
        do {
            try await authService.signInWithApple(presenting: window)
            if authService.needsUsernameSetup {
                showUsernameSetup = true
            } else {
                dismiss()
            }
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func handleGoogleSignIn() async {
        errorMessage = nil
        guard let rootViewController = activeWindow?.rootViewController else { return }
        let presenter = topPresentedViewController(from: rootViewController)
        do {
            try await authService.signInWithGoogle(presenting: presenter)
            if authService.needsUsernameSetup {
                showUsernameSetup = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private func topPresentedViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topPresentedViewController(from: presented)
        }
        return viewController
    }

    private func useWithoutAccount() {
        settings.enableLocalMode()
        Haptics.success()
        dismiss()
    }
}
