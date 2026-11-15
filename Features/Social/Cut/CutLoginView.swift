//
//  CutLoginView.swift
//  WRKT
//
//  Log in: the lime mark, "Train with friends", one line, Apple and Google, "or with email", the
//  two fields, Log in and Forgot password; Create an account and Use the app without an account sit
//  at the bottom when there is room and scroll with the rest when there is not.
//

import SwiftUI

struct CutLoginActions {
    var logIn: () -> Void = {}
    var apple: () -> Void = {}
    var google: () -> Void = {}
    var forgotPassword: () -> Void = {}
    var createAccount: () -> Void = {}
    var useWithoutAccount: () -> Void = {}
}

struct CutLoginView: View {
    let model: CutLoginModel
    @Binding var email: String
    @Binding var password: String
    var actions = CutLoginActions()

    @FocusState private var focus: CutLoginField?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    providers.padding(.top, 28)
                    CutAuthDivider(text: CutLoginLogic.divider).padding(.top, 22)
                    fields.padding(.top, 18)
                    submit.padding(.top, 18)
                    Spacer(minLength: 28)
                    bottom
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(minHeight: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            VMarkShape()
                .fill(DS.Cut.Colors.lime)
                .frame(width: 44, height: 26)
                .accessibilityLabel(Text("VOLIA"))
            CutWelcomeHero(text: model.title, size: 56)
            Text(model.line)
                .font(DS.Typography.custom(size: 18, weight: .medium, relativeTo: .body))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providers: some View {
        VStack(spacing: 10) {
            CutAppleSignInButton(isEnabled: model.providersEnabled) {
                focus = nil
                actions.apple()
            }
            .frame(height: CutAuthMetrics.rowHeight)
            CutGoogleSignInButton(isEnabled: model.providersEnabled) {
                focus = nil
                actions.google()
            }
        }
    }

    private var fields: some View {
        VStack(spacing: 10) {
            CutAuthField(prompt: "Email", text: $email, kind: .email, focus: $focus, field: .email,
                         submitLabel: .next) { focus = CutLoginLogic.next(after: .email) }
            CutAuthField(prompt: "Password", text: $password, kind: .password, focus: $focus, field: .password,
                         submitLabel: .go) {
                if CutLoginLogic.submitsFromPassword(email: email, password: password) { logIn() }
            }
            if let error = model.error {
                CutAuthLine(error, tone: .error).padding(.top, 2)
            }
        }
    }

    private var submit: some View {
        VStack(spacing: 6) {
            CutAuthSubmitButton(title: CutLoginLogic.logIn, enabled: model.logInEnabled, isLoading: model.isLoading, action: logIn)
            Button(CutLoginLogic.forgotPassword) {
                focus = nil
                actions.forgotPassword()
            }
            .buttonStyle(CutQuietButtonStyle(destructive: false))
        }
    }

    private var bottom: some View {
        VStack(spacing: 10) {
            Button(CutLoginLogic.createAccount) {
                focus = nil
                actions.createAccount()
            }
            .buttonStyle(CutPillButtonStyle(.outline, size: .compact))
            Button {
                focus = nil
                actions.useWithoutAccount()
            } label: {
                Text(CutLoginLogic.withoutAccount)
                    .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: DS.Cut.Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func logIn() {
        focus = nil
        actions.logIn()
    }
}
