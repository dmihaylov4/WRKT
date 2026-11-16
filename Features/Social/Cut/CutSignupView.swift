//
//  CutSignupView.swift
//  WRKT
//
//  Sign up: the title on the back button row, labelled fields (Username with its rule, Name,
//  Email, Password and its repeat), the password strength meter, the terms box and a lime Create
//  account. The terms box and the button sit at the bottom when there is room.
//

import SwiftUI

struct CutSignupActions {
    var back: () -> Void = {}
    var toggleTerms: () -> Void = {}
    var signUp: () -> Void = {}
}

struct CutSignupView: View {
    let model: CutSignupModel
    @Binding var form: CutSignupForm
    var actions = CutSignupActions()

    @FocusState private var focus: CutSignupField?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The title row scrolls with the form, so large text keeps the fields in view.
                    CutAuthTitleBar(title: CutSignupLogic.title, back: actions.back)
                    VStack(alignment: .leading, spacing: 0) {
                        fields.padding(.top, 24)
                        Spacer(minLength: 28)
                        bottom
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .frame(maxHeight: .infinity)
                }
                .padding(.bottom, 12)
                .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            CutAuthLabelled(label: "Username") {
                field("Username", \.username, kind: .username, .username, flagged: model.flagsUsername)
                CutAuthLine(model.usernameNote, tone: model.usernameNoteIsWarning ? .warning : .secondary)
            }
            CutAuthLabelled(label: "Name, optional") {
                field("Name", \.name, kind: .name, .name)
            }
            CutAuthLabelled(label: "Email") {
                field("you@example.com", \.email, kind: .email, .email, flagged: model.flagsEmail, label: "Email")
                if let message = model.emailMessage { CutAuthLine(message, tone: .warning) }
            }
            CutAuthLabelled(label: "Password") {
                field("At least 8 characters", \.password, kind: .newPassword, .password, label: "Password")
                if let strength = model.strength { CutSignupStrengthMeter(strength: strength) }
                field("Repeat password", \.confirm, kind: .newPassword, .confirm, submit: .done)
                if let mismatch = model.mismatchMessage { CutAuthLine(mismatch, tone: .error) }
            }
        }
    }

    private func field(_ prompt: String, _ path: WritableKeyPath<CutSignupForm, String>, kind: CutAuthFieldKind,
                       _ which: CutSignupField, flagged: Bool = false, label: String? = nil,
                       submit: SubmitLabel = .next) -> some View {
        CutAuthField(prompt: prompt, text: $form[dynamicMember: path], kind: kind, focus: $focus, field: which,
                     submitLabel: submit, isFlagged: flagged, accessibilityLabel: label) {
            focus = CutSignupLogic.next(after: which)
        }
    }

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: actions.toggleTerms) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(DS.Cut.Colors.ink)
                        .opacity(form.agreedToTerms ? 1 : 0)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(form.agreedToTerms ? DS.Cut.Colors.lime : .clear))
                        .overlay {
                            if !form.agreedToTerms {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5)
                            }
                        }
                    Text(CutSignupLogic.termsText)
                        .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CutSignupLogic.termsText))
            .accessibilityValue(Text(form.agreedToTerms ? "On" : "Off"))
            .accessibilityAddTraits(.isToggle)
            if let error = model.error {
                CutAuthLine(error, tone: .error)
            }
            CutAuthSubmitButton(title: CutSignupLogic.title, enabled: model.buttonEnabled, isLoading: model.isLoading) {
                focus = nil
                actions.signUp()
            }
        }
    }
}

/// Four short bars and a word (Weak, Fair, Good, Strong), as SignupView showed under the password.
private struct CutSignupStrengthMeter: View {
    let strength: CutSignupModel.Strength

    private var color: Color {
        switch strength.tone {
        case .weak: DS.Cut.Colors.destructive
        case .fair: DS.Status.warning
        case .good: DS.Cut.Colors.lime
        case .strong: DS.Status.success
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < strength.score ? color : DS.Cut.Colors.segmentTrack)
                        .frame(height: 4)
                }
            }
            Text(strength.label)
                .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(color)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Password strength"))
        .accessibilityValue(Text(strength.label))
    }
}
