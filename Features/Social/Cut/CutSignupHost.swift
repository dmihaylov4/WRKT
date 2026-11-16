//
//  CutSignupHost.swift
//  WRKT
//
//  Wires the Cut sign up screen exactly as SignupView did: the same signUp call and haptics, the
//  same error text and highlighted field, cleared when that field is edited. It does not dismiss on
//  success: the log in screen underneath shows email verification, as before.
//

import SwiftUI
import UIKit

struct CutSignupHost: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @Environment(\.dismiss) private var dismiss

    @State private var form = CutSignupForm()
    @State private var errorMessage: String?
    @State private var flagged: CutSignupField?

    var body: some View {
        CutSignupView(
            model: CutSignupLogic.model(form, isLoading: authService.isLoading, error: errorMessage, flagged: flagged),
            form: $form,
            actions: CutSignupActions(
                back: { dismiss() },
                toggleTerms: { form.agreedToTerms.toggle() },
                signUp: { Task { await handleSignup() } }
            )
        )
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: form.email) { _, _ in
            if flagged == .email {
                flagged = nil
                errorMessage = nil
            }
        }
        .onChange(of: form.username) { _, _ in
            if flagged == .username {
                flagged = nil
                errorMessage = nil
            }
        }
    }

    private func handleSignup() async {
        errorMessage = nil
        flagged = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await authService.signUp(
                email: form.email,
                password: form.password,
                username: form.username,
                displayName: form.name.isEmpty ? nil : form.name
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            let message = error.localizedDescription
            errorMessage = message
            flagged = CutSignupLogic.flaggedField(for: message)
        }
    }
}
