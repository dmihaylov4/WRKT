import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreedToTerms = false
    @State private var errorMessage: String?
    @State private var hasUsernameError = false
    @State private var hasEmailError = false

    enum Field: Hashable {
        case email
        case username
        case displayName
        case password
        case confirmPassword
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 50))
                            .foregroundStyle(DS.Palette.marone)

                        Text("Create Account")
                            .font(.title.bold())
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 16)

                    // Form fields
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .padding()
                            .background(hasEmailError ? Color.red.opacity(0.1) : DS.Semantic.surface50)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(hasEmailError ? Color.red : Color.clear, lineWidth: 2)
                            )
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .username
                            }
                            .onChange(of: email) { _, _ in
                                if hasEmailError {
                                    hasEmailError = false
                                    errorMessage = nil
                                }
                            }

                        // Email validation feedback
                        if !email.isEmpty && !isValidEmail(email) {
                            Text("Please enter a valid email address")
                                .font(.caption)
                                .foregroundColor(DS.Status.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .padding()
                            .background(hasUsernameError ? Color.red.opacity(0.1) : DS.Semantic.surface50)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(hasUsernameError ? Color.red : Color.clear, lineWidth: 2)
                            )
                            .focused($focusedField, equals: .username)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .displayName
                            }
                            .onChange(of: username) { _, _ in
                                // Clear error when user edits username
                                if hasUsernameError {
                                    hasUsernameError = false
                                    errorMessage = nil
                                }
                            }

                        // Username validation feedback
                        if !username.isEmpty && !isValidUsername(username) {
                            Text("Username must be 3-30 characters (letters, numbers, underscore only)")
                                .font(.caption)
                                .foregroundColor(DS.Status.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TextField("Display Name (optional)", text: $displayName)
                            .textContentType(.name)
                            .padding()
                            .background(DS.Semantic.surface50)
                            .cornerRadius(10)
                            .focused($focusedField, equals: .displayName)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }

                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Password", text: $password)
                                .textContentType(.newPassword)
                                .padding()
                                .background(DS.Semantic.surface50)
                                .cornerRadius(10)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .confirmPassword
                                }

                            // Password strength indicator
                            if !password.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(0..<4) { index in
                                        Rectangle()
                                            .fill(index < passwordStrength ? strengthColor : Color(.systemGray5))
                                            .frame(height: 4)
                                    }
                                }
                                .cornerRadius(2)

                                Text(strengthText)
                                    .font(.caption)
                                    .foregroundColor(strengthColor)
                            }
                        }

                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(DS.Semantic.surface50)
                            .cornerRadius(10)
                            .focused($focusedField, equals: .confirmPassword)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }

                        // Password match indicator
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Terms agreement
                        Toggle(isOn: $agreedToTerms) {
                            Text("I agree to the Terms & Conditions")
                                .font(.subheadline)
                        }
                        .padding(.top, 8)

                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Sign up button
                        Button {
                            Task {
                                await handleSignup()
                            }
                        } label: {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Create Account")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSignup ? DS.Palette.marone : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .disabled(!canSignup || authService.isLoading)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    // MARK: - Validation

    private var canSignup: Bool {
        !email.isEmpty &&
        isValidEmail(email) &&
        !username.isEmpty &&
        isValidUsername(username) &&
        !password.isEmpty &&
        password == confirmPassword &&
        passwordStrength >= 2 &&
        agreedToTerms
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func isValidUsername(_ username: String) -> Bool {
        let length = username.count
        guard length >= 3 && length <= 30 else { return false }
        let regex = "^[a-zA-Z0-9_]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: username)
    }

    private var passwordStrength: Int {
        var strength = 0
        if password.count >= 8 { strength += 1 }
        if password.contains(where: { $0.isNumber }) { strength += 1 }
        if password.contains(where: { $0.isUppercase }) { strength += 1 }
        if password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) { strength += 1 }
        return strength
    }

    private var strengthColor: Color {
        switch passwordStrength {
        case 0...1: return DS.Status.error
        case 2: return DS.Status.warning
        case 3: return DS.Semantic.brand
        default: return DS.Status.success
        }
    }

    private var strengthText: String {
        switch passwordStrength {
        case 0...1: return "Weak"
        case 2: return "Fair"
        case 3: return "Good"
        default: return "Strong"
        }
    }

    // MARK: - Actions

    private func handleSignup() async {
        errorMessage = nil
        hasUsernameError = false
        hasEmailError = false

        // Dismiss keyboard
        focusedField = nil

        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        do {
            try await authService.signUp(
                email: email,
                password: password,
                username: username,
                displayName: displayName.isEmpty ? nil : displayName
            )

            // Success haptic
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)

            // Don't dismiss - let the parent view handle showing verification screen
            // The parent will check authService.needsEmailVerification

        } catch {
            // Error haptic
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)

            errorMessage = error.localizedDescription

            // Check if it's a username error and highlight the field
            if errorMessage?.contains("username") == true ||
               errorMessage?.contains("already taken") == true {
                hasUsernameError = true
            } else if errorMessage?.contains("email") == true {
                hasEmailError = true
            }
        }
    }
}

#Preview {
    SignupView()
        .environmentObject(SupabaseAuthService.shared)
}
