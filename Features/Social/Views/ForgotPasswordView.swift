import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: SupabaseAuthService

    @State private var email = ""
    @State private var emailSent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if emailSent {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Check Your Email")
                            .font(.title2.bold())

                        Text("We've sent password reset instructions to:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text(email)
                            .font(.subheadline.bold())

                        Button {
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
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 50))
                            .foregroundStyle(DS.Palette.marone)

                        Text("Reset Password")
                            .font(.title2.bold())

                        Text("Enter your email address and we'll send you instructions to reset your password.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task {
                                await handleResetPassword()
                            }
                        } label: {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Send Reset Link")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSend ? DS.Palette.marone : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .disabled(!canSend || authService.isLoading)
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
                        dismiss()
                    }
                }
            }
            .onReceive(authService.$needsPasswordReset) { needsReset in
                // Dismiss when password recovery deep link is handled
                if needsReset {
                    dismiss()
                }
            }
        }
    }

    private var canSend: Bool {
        !email.isEmpty && email.contains("@")
    }

    private func handleResetPassword() async {
        errorMessage = nil

        do {
            try await authService.resetPassword(email: email)
            withAnimation {
                emailSent = true
            }
        } catch {
            // Provide user-friendly error messages
            let errorText = error.localizedDescription.lowercased()
            if errorText.contains("rate limit") {
                errorMessage = "Too many attempts. Please wait a few minutes before trying again."
            } else if errorText.contains("not found") || errorText.contains("no user") {
                errorMessage = "No account found with this email address."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
        .environmentObject(SupabaseAuthService.shared)
}
