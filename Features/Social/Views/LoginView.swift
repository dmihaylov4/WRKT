import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: SupabaseAuthService
    @StateObject private var settings = AppSettings.shared
    @FocusState private var focusedField: Field?

    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false
    @State private var showEmailVerification = false
    @State private var errorMessage: String?

    enum Field: Hashable {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // App logo/title
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(DS.Palette.marone)

                    Text("WRKT Social")
                        .font(.largeTitle.bold())
                }
                .padding(.bottom, 40)

                // Login form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(DS.Semantic.surface50)
                        .cornerRadius(10)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(DS.Semantic.surface50)
                        .cornerRadius(10)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            if canLogin {
                                Task {
                                    await handleLogin()
                                }
                            }
                        }

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Login button
                    Button {
                        Task {
                            await handleLogin()
                        }
                    } label: {
                        Group {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Log In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canLogin ? DS.Palette.marone : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    }
                    .disabled(!canLogin || authService.isLoading)

                    // Forgot password
                    Button {
                        showForgotPassword = true
                    } label: {
                        Text("Forgot password?")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)

                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 8)

                // Skip social features button
                Button {
                    skipSocialFeatures()
                } label: {
                    HStack {
                        Image(systemName: "person.slash")
                            .font(.body)

                        Text("Don't use social features")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 32)

                // Explanation text
                Text("You can enable social features later in settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Sign up link
                HStack {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)
                    NavigationLink {
                        SignupView()
                    } label: {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focusedField = nil // Dismiss keyboard on tap
            }
            .sheet(isPresented: $showEmailVerification) {
                EmailVerificationView()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onChange(of: authService.needsEmailVerification) { _, needsVerification in
                showEmailVerification = needsVerification
            }
            .onReceive(authService.$currentUser) { newUser in
                // Dismiss login view when user becomes logged in (e.g., after email verification)
                if newUser != nil {
                    dismiss()
                }
            }
        }
    }

    private var canLogin: Bool {
        !email.isEmpty && !password.isEmpty && isValidEmail(email)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func handleLogin() async {
        errorMessage = nil

        // Dismiss keyboard
        focusedField = nil

        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        do {
            try await authService.signIn(email: email, password: password)

            // Success haptic
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)

            // Dismiss login sheet on success
            dismiss()
        } catch {
            // Error haptic
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)

            errorMessage = error.localizedDescription
        }
    }

    private func skipSocialFeatures() {
        settings.enableLocalMode()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    LoginView()
        .environmentObject(SupabaseAuthService.shared)
}
