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
            VStack(spacing: 18) {
                Spacer(minLength: 18)

                VStack(spacing: 12) {
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 82, height: 82)

                   
                }
                .padding(.bottom, 10)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .loginFieldStyle(isFocused: focusedField == .email)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .loginFieldStyle(isFocused: focusedField == .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            if canLogin {
                                Task {
                                    await handleLogin()
                                }
                            }
                        }

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .dsFont(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

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
                                    .font(DS.Typography.custom(size: 20, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(canLogin ? DS.Theme.accent : DS.Semantic.surface50, in: ChamferedRectangle(.large))
                        .foregroundColor(canLogin ? .black : DS.Semantic.textSecondary)
                        .overlay(ChamferedRectangle(.large).stroke(canLogin ? DS.Theme.accent : DS.Semantic.border, lineWidth: 1))
                    }
                    .disabled(!canLogin || authService.isLoading)

                    Button {
                        showForgotPassword = true
                    } label: {
                        Text("Forgot password?")
                            .dsFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Theme.accent)
                    }
                }
                .padding(.horizontal, 38)

                Spacer(minLength: 18)

                HStack(spacing: 18) {
                    Rectangle()
                        .fill(DS.Semantic.border)
                        .frame(height: 1)

                    Text("or")
                        .dsFont(.caption, weight: .medium)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Rectangle()
                        .fill(DS.Semantic.border)
                        .frame(height: 1)
                }
                .padding(.horizontal, 38)

                Button {
                    skipSocialFeatures()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .dsFont(.body)

                        Text("Don't use social features")
                            .dsFont(.subheadline, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(DS.Theme.accent)
                    .background(DS.Semantic.card, in: ChamferedRectangle(.large))
                    .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
                }
                .padding(.horizontal, 38)

                Text("You can enable social features later in settings")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 38)

                HStack(spacing: 8) {
                    Text("Don't have an account?")
                        .foregroundColor(DS.Semantic.textSecondary)
                    NavigationLink {
                        SignupView()
                    } label: {
                        Text("Sign Up")
                            .fontWeight(.bold)
                            .foregroundStyle(DS.Theme.accent)
                    }
                }
                .font(DS.Typography.custom(size: 18, weight: .regular))
                .padding(.bottom, 22)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
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

private struct LoginFieldStyle: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(DS.Typography.custom(size: 18, weight: .regular))
            .foregroundStyle(DS.Semantic.textPrimary)
            .tint(DS.Theme.accent)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(isFocused ? DS.Theme.accent : DS.Semantic.border, lineWidth: isFocused ? 1.5 : 1)
            )
    }
}

private extension View {
    func loginFieldStyle(isFocused: Bool) -> some View {
        modifier(LoginFieldStyle(isFocused: isFocused))
    }
}

#Preview {
    LoginView()
        .environmentObject(SupabaseAuthService.shared)
}
