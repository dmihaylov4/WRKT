//
//  SetNewPasswordView.swift
//  WRKT
//
//  View for setting a new password after clicking reset link
//

import SwiftUI

struct SetNewPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: SupabaseAuthService

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordUpdated = false
    @State private var errorMessage: String?

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var isValidPassword: Bool {
        newPassword.count >= 8
    }

    private var canSubmit: Bool {
        isValidPassword && passwordsMatch && !authService.isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if passwordUpdated {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Password Updated!")
                            .font(.title2.bold())

                        Text("Your password has been successfully changed. You can now log in with your new password.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            authService.needsPasswordReset = false
                            dismiss()
                        } label: {
                            Text("Done")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(DS.Palette.marone)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal, 32)
                } else {
                    // Input state
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 50))
                            .foregroundStyle(DS.Palette.marone)

                        Text("Set New Password")
                            .font(.title2.bold())

                        Text("Enter your new password below. Make sure it's at least 8 characters long.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)

                        SecureField("New Password", text: $newPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                        // Validation messages
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: isValidPassword ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(isValidPassword ? .green : .secondary)
                                Text("At least 8 characters")
                                    .font(.caption)
                                    .foregroundStyle(isValidPassword ? .primary : .secondary)
                            }

                            if !confirmPassword.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(passwordsMatch ? Color.green : Color.red)
                                    Text(passwordsMatch ? "Passwords match" : "Passwords don't match")
                                        .font(.caption)
                                        .foregroundColor(passwordsMatch ? .primary : .red)
                                    
                
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task {
                                await handleUpdatePassword()
                            }
                        } label: {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Update Password")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSubmit ? DS.Palette.marone : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .disabled(!canSubmit)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .padding(.top, 60)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authService.needsPasswordReset = false
                        dismiss()
                    }
                }
            }
        }
    }

    private func handleUpdatePassword() async {
        errorMessage = nil

        do {
            try await authService.updatePassword(newPassword: newPassword)
            withAnimation {
                passwordUpdated = true
            }
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

#Preview {
    SetNewPasswordView()
        .environmentObject(SupabaseAuthService.shared)
}
