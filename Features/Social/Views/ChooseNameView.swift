//
//  ChooseNameView.swift
//  WRKT
//
//  The Choose your name step and the gate that shows it. SocialNameGate wraps every social
//  surface (the Social tab, every post composer, the social rows in settings): while the signed-in
//  profile still has the server's made-up name (ProfileNamePolicy), the step stands in for the
//  content, and once the name is saved the content appears in its place. Signed out, local mode
//  and real names pass straight through. Training never goes through the gate.
//
//  The legacy screen follows OAuthUsernameSetupView's look; the Cut screen is CutChooseNameHost.
//  Both run the same ChooseNameController.
//

import SwiftUI

/// Shows `content`, or the Choose your name step while the signed-in profile has a made-up name.
struct SocialNameGate<Content: View>: View {
    @ObservedObject private var authService: SupabaseAuthService
    private let surface: SocialNameSurface
    private let close: (() -> Void)?
    private let content: () -> Content

    /// `close` adds a close button to the step, for when it stands in for a sheet's content.
    init(_ surface: SocialNameSurface,
         authService: SupabaseAuthService = AppDependencies.shared.authService,
         close: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.surface = surface
        self._authService = ObservedObject(wrappedValue: authService)
        self.close = close
        self.content = content
    }

    var body: some View {
        if let profile = authService.currentUser?.profile, surface.isBlocked(for: profile) {
            ChooseNameView(profile: profile, authService: authService, close: close)
                // One step per account: a different account gets a fresh form.
                .id(profile.id)
        } else {
            content()
        }
    }
}

extension ChooseNameController {
    /// The app's wiring: the auth service saves and signs out, NetworkMonitor says whether a save
    /// can be sent, and Apple's name from the first sign-in, if it never reached the profile,
    /// fills the Name field.
    static func live(profile: UserProfile, authService: SupabaseAuthService) -> ChooseNameController {
        ChooseNameController(
            profile: profile,
            suggestedDisplayName: PendingAppleName.value(for: profile.id),
            save: { username, displayName in
                try await authService.chooseName(username: username, displayName: displayName)
            },
            signOut: { try await authService.signOut() },
            isOnline: { NetworkMonitor.shared.isConnected }
        )
    }
}

struct ChooseNameView: View {
    @State private var controller: ChooseNameController
    private let close: (() -> Void)?

    init(profile: UserProfile, authService: SupabaseAuthService, close: (() -> Void)? = nil) {
        _controller = State(initialValue: .live(profile: profile, authService: authService))
        self.close = close
    }

    var body: some View {
        if DS.Redesign.cutEnabled {
            CutChooseNameHost(controller: controller, close: close)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        @Bindable var controller = controller
        return ChooseNameLegacyForm(
            model: controller.model,
            form: $controller.form,
            actions: ChooseNameActions(
                close: close,
                save: { Task { await save() } },
                signOut: { Task { await controller.signOut() } }
            )
        )
    }

    private func save() async {
        if await controller.submit() {
            Haptics.success()
        } else if controller.failure != nil {
            Haptics.error()
        }
    }
}

/// The legacy screen: the logo, title and line, two fields in the sign-in field style, the
/// messages, the accent Save and continue, and Sign out. It scrolls, for large text.
struct ChooseNameLegacyForm: View {
    let model: ChooseNameModel
    @Binding var form: ChooseNameForm
    var actions = ChooseNameActions()

    @FocusState private var focus: ChooseNameField?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let close = actions.close {
                    HStack {
                        Button(ChooseNameLogic.closeTitle, action: close)
                            .dsFont(.body)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .frame(minHeight: 44)
                        Spacer()
                    }
                }

                header

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(ChooseNameLogic.displayNamePrompt, text: $form.displayName)
                            .textContentType(.name)
                            .loginFieldStyle(isFocused: focus == .displayName)
                            .focused($focus, equals: .displayName)
                            .submitLabel(.next)
                            .onSubmit { focus = ChooseNameLogic.next(after: .displayName) }
                            .accessibilityLabel(Text(ChooseNameLogic.displayNameLabel))
                        if let message = model.displayNameMessage {
                            note(message, color: DS.Status.warning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(ChooseNameLogic.usernamePrompt, text: $form.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .loginFieldStyle(isFocused: focus == .username)
                            .overlay {
                                if model.flagsUsername {
                                    DS.RoleShape(.card, legacy: ChamferedRectangle(.large))
                                        .stroke(DS.Status.error, lineWidth: 2)
                                        .allowsHitTesting(false)
                                }
                            }
                            .focused($focus, equals: .username)
                            .submitLabel(.done)
                            .onSubmit {
                                focus = nil
                                if model.buttonEnabled { actions.save() }
                            }
                            .accessibilityLabel(Text(ChooseNameLogic.usernameLabel))
                        note(model.usernameNote, color: model.usernameNoteIsWarning ? DS.Status.warning : DS.Semantic.textSecondary)
                    }

                    if let error = model.error {
                        note(error, color: DS.Status.error)
                            .accessibilityLabel(Text("Error: \(error)"))
                    }

                    saveButton

                    Button {
                        focus = nil
                        actions.signOut()
                    } label: {
                        Group {
                            if model.isSigningOut {
                                ProgressView().tint(DS.Semantic.textSecondary)
                            } else {
                                Text(ChooseNameLogic.signOutTitle).dsFont(.body, weight: .semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .disabled(model.isSaving || model.isSigningOut)
                    .accessibilityLabel(Text(model.isSigningOut ? "\(ChooseNameLogic.signOutTitle), working" : ChooseNameLogic.signOutTitle))
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Semantic.surface.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            Text(ChooseNameLogic.title)
                .font(DS.Typography.custom(size: 26, weight: .bold, relativeTo: .title))
                .foregroundStyle(DS.Semantic.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(ChooseNameLogic.intro)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveButton: some View {
        Button {
            focus = nil
            actions.save()
        } label: {
            Group {
                if model.isSaving {
                    ProgressView().tint(.black)
                } else {
                    Text(ChooseNameLogic.saveTitle)
                        .font(DS.Typography.custom(size: 20, weight: .bold, relativeTo: .headline))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 12)
            .background(model.canSave ? DS.Theme.accent : DS.Semantic.surface50, in: DS.RoleShape(.control, legacy: ChamferedRectangle(.large)))
            .foregroundColor(model.canSave ? .black : DS.Semantic.textSecondary)
            .overlay(
                DS.RoleShape(.control, legacy: ChamferedRectangle(.large))
                    .stroke(model.canSave ? DS.Theme.accent : DS.Semantic.border, lineWidth: 1)
            )
        }
        .disabled(!model.buttonEnabled)
        .accessibilityLabel(Text(model.isSaving ? "\(ChooseNameLogic.saveTitle), working" : ChooseNameLogic.saveTitle))
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .dsFont(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
