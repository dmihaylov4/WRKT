//
//  CutPasswordView.swift
//  WRKT
//
//  Reset password and Set new password as Cut form sheets: grey surface, large title top left,
//  round close top right, sized to their content, one lime button at the bottom.
//

import SwiftUI

enum CutPasswordField: Hashable { case email, password, confirm }

struct CutResetPasswordView: View {
    let model: CutResetPasswordModel
    @Binding var email: String
    var send: () -> Void = {}
    var done: () -> Void = {}
    var close: () -> Void = {}

    @FocusState private var focus: CutPasswordField?

    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, close: close) {
            VStack(alignment: .leading, spacing: 8) {
                switch model.stage {
                case .form:
                    CutAuthLabelled(label: "Email") {
                        CutAuthField(prompt: "you@example.com", text: $email, kind: .email, focus: $focus, field: .email,
                                     submitLabel: .return, fill: DS.Cut.SheetLevel.base.control, accessibilityLabel: "Email")
                    }
                    if let error = model.error { CutAuthLine(error, tone: .error) }
                case .sent(let address):
                    Text(address)
                        .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 24)
        } footer: {
            Group {
                switch model.stage {
                case .form:
                    CutAuthSubmitButton(title: CutPasswordLogic.sendTitle, enabled: model.sendEnabled, isLoading: model.isLoading) {
                        focus = nil
                        send()
                    }
                case .sent:
                    Button("Done", action: done)
                        .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

struct CutNewPasswordView: View {
    let model: CutNewPasswordModel
    @Binding var password: String
    @Binding var confirm: String
    var update: () -> Void = {}
    var done: () -> Void = {}
    var close: () -> Void = {}

    @FocusState private var focus: CutPasswordField?

    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, close: close) {
            if !model.isUpdated {
                VStack(alignment: .leading, spacing: 10) {
                    CutAuthLabelled(label: "New password") {
                        CutAuthField(prompt: "New password", text: $password, kind: .newPassword, focus: $focus, field: .password,
                                     submitLabel: .return, fill: DS.Cut.SheetLevel.base.control)
                        CutAuthField(prompt: "Repeat password", text: $confirm, kind: .newPassword, focus: $focus, field: .confirm,
                                     submitLabel: .return, fill: DS.Cut.SheetLevel.base.control)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.checks, id: \.text) { check in
                            CutNewPasswordCheckRow(check: check)
                        }
                    }
                    .padding(.top, 2)
                    if let error = model.error { CutAuthLine(error, tone: .error) }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            } else {
                Color.clear.frame(height: 12)
            }
        } footer: {
            Group {
                if model.isUpdated {
                    Button("Done", action: done)
                        .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                } else {
                    CutAuthSubmitButton(title: CutPasswordLogic.updateTitle, enabled: model.canSubmit, isLoading: model.isLoading) {
                        focus = nil
                        update()
                    }
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

private struct CutNewPasswordCheckRow: View {
    let check: CutNewPasswordModel.Check

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            CutAuthLine(check.text, tone: check.state == .failed ? .error : check.state == .met ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(check.state == .met ? "Done" : check.state == .failed ? "Not yet" : ""))
    }

    private var icon: String {
        switch check.state {
        case .met: "checkmark.circle.fill"
        case .pending: "circle"
        case .failed: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch check.state {
        case .met: DS.Status.success
        case .pending: DS.Cut.Colors.textSecondary
        case .failed: DS.Cut.Colors.destructive
        }
    }
}
