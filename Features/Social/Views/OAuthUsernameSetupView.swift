import SwiftUI

struct OAuthUsernameSetupView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var username = ""
    @State private var displayName = ""
    @State private var errorMessage: String?

    enum Field: Hashable {
        case username
        case displayName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                VStack(spacing: 8) {
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)

                    Text("Choose a username")
                        .font(DS.Typography.custom(size: 26, weight: .bold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("This is how other users will find you.")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 8)

                VStack(spacing: 14) {
                    TextField("Username (required)", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .loginFieldStyle(isFocused: focusedField == .username)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .displayName
                        }

                    TextField("Display name (optional)", text: $displayName)
                        .textContentType(.name)
                        .loginFieldStyle(isFocused: focusedField == .displayName)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.go)
                        .onSubmit {
                            if canContinue {
                                Task {
                                    await handleContinue()
                                }
                            }
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .dsFont(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            await handleContinue()
                        }
                    } label: {
                        Group {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Continue")
                                    .font(DS.Typography.custom(size: 20, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(canContinue ? DS.Theme.accent : DS.Semantic.surface50, in: DS.RoleShape(.control, legacy: ChamferedRectangle(.large)))
                        .foregroundColor(canContinue ? .black : DS.Semantic.textSecondary)
                        .overlay(
                            DS.RoleShape(.control, legacy: ChamferedRectangle(.large))
                                .stroke(canContinue ? DS.Theme.accent : DS.Semantic.border, lineWidth: 1)
                        )
                    }
                    .disabled(!canContinue || authService.isLoading)
                }
                .padding(.horizontal, 38)

                Spacer()
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .onTapGesture {
                focusedField = nil
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Task {
                            await cancelSetup()
                        }
                    }
                    .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var canContinue: Bool {
        username.count >= 3 && isValidUsername(username)
    }

    private func isValidUsername(_ value: String) -> Bool {
        let regex = "^[a-zA-Z0-9_]{3,30}$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: value)
    }

    private func handleContinue() async {
        errorMessage = nil
        focusedField = nil

        do {
            try await authService.createOAuthProfile(
                username: username,
                displayName: displayName.trimmingCharacters(in: .whitespaces)
            )
            Haptics.success()
            dismiss()
        } catch SupabaseError.usernameTaken {
            errorMessage = "This username is already taken"
            Haptics.error()
        } catch SupabaseError.invalidUsername {
            errorMessage = "Username must be 3-30 characters: letters, numbers, or underscore only"
            Haptics.error()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func cancelSetup() async {
        try? await authService.signOut()
        dismiss()
    }
}

#Preview {
    OAuthUsernameSetupView()
        .environmentObject(SupabaseAuthService.shared)
}
