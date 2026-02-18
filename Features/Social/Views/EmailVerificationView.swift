import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @Environment(\.dismiss) private var dismiss

    @State private var isResending = false
    @State private var showResendSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 80))
                .foregroundStyle(DS.Palette.marone)

            // Title
            Text("Verify Your Email")
                .font(.title.bold())

            // Subtitle
            Text("We sent a verification link to:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Email
            if let email = authService.signupEmail {
                Text(email)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Semantic.brand)
            }

            // Instructions
            VStack(spacing: 12) {
                Text("Click the link in the email to verify your account and start using WRKT.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("After verifying, return here and we'll log you in automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Resend button
            VStack(spacing: 16) {
                if showResendSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Verification email sent!")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button {
                    Task {
                        await resendVerification()
                    }
                } label: {
                    if isResending {
                        ProgressView()
                            .tint(DS.Palette.marone)
                    } else {
                        Text("Resend Verification Email")
                            .fontWeight(.medium)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(DS.Semantic.textPrimary)
                .cornerRadius(10)
                .disabled(isResending)

                Button {
                    dismiss()
                } label: {
                    Text("Back to Login")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(DS.Palette.marone)
                .foregroundColor(.black)
                .cornerRadius(10)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .onReceive(authService.$currentUser) { newUser in
            // Dismiss when user becomes logged in (verification succeeded)
            if newUser != nil {
                dismiss()
            }
        }
        .onReceive(authService.$needsEmailVerification) { needsVerification in
            // Dismiss when verification is no longer needed
            if !needsVerification {
                dismiss()
            }
        }
    }

    private func resendVerification() async {
        isResending = true
        errorMessage = nil
        showResendSuccess = false

        defer { isResending = false }

        do {
            try await authService.resendVerificationEmail()
            showResendSuccess = true
            Haptics.success()

            // Hide success message after 3 seconds
            Task {
                try? await Task.sleep(for: .seconds(3))
                showResendSuccess = false
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

#Preview {
    EmailVerificationView()
        .environmentObject(SupabaseAuthService.shared)
}
