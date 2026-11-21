//
//  CutChooseNameView.swift
//  WRKT
//
//  Choose your name, in the Cut sign up look: the title (with a close button when the step opens
//  over a composer), one supporting line, labelled Name and Username fields with sign up's
//  username rule, the error line, a lime Save and continue, and a plain Sign out. Everything
//  scrolls, so the largest text sizes keep every control reachable.
//

import SwiftUI

struct ChooseNameActions {
    var close: (() -> Void)?
    var save: () -> Void = {}
    var signOut: () -> Void = {}
}

struct CutChooseNameView: View {
    let model: ChooseNameModel
    @Binding var form: ChooseNameForm
    var actions = ChooseNameActions()

    @FocusState private var focus: ChooseNameField?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleRow
                    VStack(alignment: .leading, spacing: 0) {
                        CutAuthLine(ChooseNameLogic.intro)
                            .padding(.top, 12)
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

    @ViewBuilder private var titleRow: some View {
        if let close = actions.close {
            CutPlannerTopBar(leading: .close, action: close) { title }
        } else {
            title
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 8)
        }
    }

    private var title: some View {
        Text(ChooseNameLogic.title)
            .font(DS.Cut.Typography.condensed(size: 34, relativeTo: .title))
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            CutAuthLabelled(label: ChooseNameLogic.displayNameLabel) {
                CutAuthField(prompt: ChooseNameLogic.displayNamePrompt, text: $form.displayName, kind: .name,
                             focus: $focus, field: .displayName, accessibilityLabel: ChooseNameLogic.displayNameLabel) {
                    focus = ChooseNameLogic.next(after: .displayName)
                }
                if let message = model.displayNameMessage { CutAuthLine(message, tone: .warning) }
            }
            CutAuthLabelled(label: ChooseNameLogic.usernameLabel) {
                CutAuthField(prompt: ChooseNameLogic.usernamePrompt, text: $form.username, kind: .username,
                             focus: $focus, field: .username, submitLabel: .done, isFlagged: model.flagsUsername,
                             accessibilityLabel: ChooseNameLogic.usernameLabel) {
                    focus = nil
                    if model.buttonEnabled { actions.save() }
                }
                .autocorrectionDisabled()
                CutAuthLine(model.usernameNote, tone: model.usernameNoteIsWarning ? .warning : .secondary)
            }
        }
    }

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = model.error {
                CutAuthLine(error, tone: .error)
                    .accessibilityLabel(Text("Error: \(error)"))
            }
            CutAuthSubmitButton(title: ChooseNameLogic.saveTitle, enabled: model.buttonEnabled, isLoading: model.isSaving) {
                focus = nil
                actions.save()
            }
            Button {
                focus = nil
                actions.signOut()
            } label: {
                ZStack {
                    Text(ChooseNameLogic.signOutTitle).opacity(model.isSigningOut ? 0 : 1)
                    if model.isSigningOut { ProgressView().tint(DS.Cut.Colors.textPrimary) }
                }
            }
            .buttonStyle(CutPillButtonStyle(.outline, size: .regular, fillsWidth: true))
            .disabled(model.isSaving || model.isSigningOut)
            .accessibilityLabel(Text(model.isSigningOut ? "\(ChooseNameLogic.signOutTitle), working" : ChooseNameLogic.signOutTitle))
        }
    }
}
