//
//  CutPasswordHost.swift
//  WRKT
//
//  Wires the two password sheets exactly as the legacy views did. Reset: the same resetPassword
//  call and messages, Done and close dismiss, and the sheet closes itself when a password recovery
//  link arrives. Set new password: the same updatePassword call and haptics; close and Done clear
//  needsPasswordReset and dismiss; the sheet cannot be swiped away, as the legacy full screen
//  cover could not.
//

import SwiftUI

struct CutResetPasswordHost: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: SupabaseAuthService

    @State private var email = ""
    @State private var sentTo: String?
    @State private var errorMessage: String?

    var body: some View {
        CutResetPasswordView(
            model: CutPasswordLogic.reset(email: email, sentTo: sentTo, isLoading: authService.isLoading, error: errorMessage),
            email: $email,
            send: { Task { await handleResetPassword() } },
            done: { dismiss() },
            close: { dismiss() }
        )
        .onReceive(authService.$needsPasswordReset) { needsReset in
            // Dismiss when the password recovery deep link is handled.
            if needsReset {
                dismiss()
            }
        }
    }

    private func handleResetPassword() async {
        errorMessage = nil
        do {
            try await authService.resetPassword(email: email)
            withAnimation { sentTo = email }
        } catch {
            errorMessage = CutPasswordLogic.resetError(error.localizedDescription)
        }
    }
}

struct CutNewPasswordHost: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: SupabaseAuthService

    @State private var password = ""
    @State private var confirm = ""
    @State private var updated = false
    @State private var errorMessage: String?

    var body: some View {
        CutNewPasswordView(
            model: CutPasswordLogic.newPassword(password, confirm, updated: updated, isLoading: authService.isLoading, error: errorMessage),
            password: $password,
            confirm: $confirm,
            update: { Task { await handleUpdatePassword() } },
            done: finish,
            close: finish
        )
        .interactiveDismissDisabled()
    }

    /// Done and Cancel both did this in SetNewPasswordView.
    private func finish() {
        authService.needsPasswordReset = false
        dismiss()
    }

    private func handleUpdatePassword() async {
        errorMessage = nil
        do {
            try await authService.updatePassword(newPassword: password)
            withAnimation { updated = true }
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
