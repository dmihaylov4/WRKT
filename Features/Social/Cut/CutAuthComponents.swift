//
//  CutAuthComponents.swift
//  WRKT
//
//  Pieces shared by the Cut sign-in screens: the filled text field, a labelled field, the error
//  line, the lime submit button with its spinner, and the two provider buttons. Sign in with Apple
//  is the system button; Sign in with Google uses Google's own logo from the GoogleSignIn SDK on a
//  pill in Google's dark theme colours. Both are 54 pt pills.
//

import AuthenticationServices
import SwiftUI
import UIKit

enum CutAuthMetrics {
    /// Height of the provider buttons and the text fields.
    static let rowHeight: CGFloat = 54
}

/// What a field holds; sets the autofill content type, keyboard and capitalisation as legacy did.
enum CutAuthFieldKind: Equatable {
    case email, username, name, password, newPassword

    var isSecure: Bool { self == .password || self == .newPassword }
}

/// A filled, rounded text or secure field. A flagged field (the server named it) gets a red outline.
struct CutAuthField<Focus: Hashable>: View {
    let prompt: String
    @Binding var text: String
    let kind: CutAuthFieldKind
    let focus: FocusState<Focus?>.Binding
    let field: Focus
    var submitLabel: SubmitLabel = .next
    var fill: Color = DS.Cut.SheetLevel.base.surface
    var isFlagged = false
    var accessibilityLabel: String?
    var onSubmit: () -> Void = {}

    var body: some View {
        input
            .font(DS.Typography.custom(size: 18, weight: .medium, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .tint(DS.Cut.Colors.lime)
            .focused(focus, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: CutAuthMetrics.rowHeight)
            // Taps on the padding around the text focus the field too.
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
                .onTapGesture { focus.wrappedValue = field })
            .overlay {
                if isFlagged {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DS.Cut.Colors.destructive, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(Text(accessibilityLabel ?? prompt))
    }

    @ViewBuilder private var input: some View {
        let placeholder = Text(prompt).foregroundStyle(DS.Cut.Colors.textSecondary)
        switch kind {
        case .email:
            TextField(prompt, text: $text, prompt: placeholder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
        case .username:
            TextField(prompt, text: $text, prompt: placeholder)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
        case .name:
            TextField(prompt, text: $text, prompt: placeholder)
                .textContentType(.name)
        case .password:
            SecureField(prompt, text: $text, prompt: placeholder)
                .textContentType(.password)
        case .newPassword:
            SecureField(prompt, text: $text, prompt: placeholder)
                .textContentType(.newPassword)
        }
    }
}

/// A plain label above a field, with an optional line under it.
struct CutAuthLabelled<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CutPlannerLabel(label)
            content()
        }
    }
}

/// One supporting or error line, never under 15 pt.
struct CutAuthLine: View {
    enum Tone { case primary, secondary, warning, error }
    let text: String
    var tone: Tone = .secondary

    init(_ text: String, tone: Tone = .secondary) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch tone {
        case .primary: DS.Cut.Colors.textPrimary
        case .secondary: DS.Cut.Colors.textSecondary
        case .warning: DS.Status.warning
        case .error: DS.Cut.Colors.destructive
        }
    }
}

/// The lime submit pill. Grey while the form is incomplete; lime with a spinner while it works.
struct CutAuthSubmitButton: View {
    let title: String
    let enabled: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(DS.Cut.Colors.ink) }
            }
        }
        .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
        .disabled(!enabled && !isLoading)
        .allowsHitTesting(enabled && !isLoading)
        .accessibilityLabel(Text(isLoading ? "\(title), working" : title))
    }
}

/// The round back button with a condensed capital title on the same row.
struct CutAuthTitleBar: View {
    let title: String
    let back: () -> Void

    var body: some View {
        CutPlannerTopBar(leading: .back, action: back) {
            Text(title)
                .font(DS.Cut.Typography.condensed(size: 34, relativeTo: .title))
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - Provider buttons

/// Apple's own Sign in with Apple button (white, for a dark background), as a 54 pt pill.
/// Apple lets the corner radius change; the label and logo are the system's. A tap runs the same
/// request and nonce handling the legacy screen used, through `action`.
struct CutAppleSignInButton: UIViewRepresentable {
    var isEnabled = true
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: .white)
        button.cornerRadius = CutAuthMetrics.rowHeight / 2
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.5
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

/// Sign in with Google in Google's dark theme (fill #131314, 1 pt #8E918F outline, #E3E3E3 text)
/// with the standard "G" logo shipped in the GoogleSignIn SDK. Pill shape, as Google allows.
struct CutGoogleSignInButton: View {
    var isEnabled = true
    let action: () -> Void

    /// Google's branding colours for a dark button; not app tokens on purpose.
    private enum Brand {
        static let fill = Color(hex: "#131314")
        static let stroke = Color(hex: "#8E918F")
        static let text = Color(hex: "#E3E3E3")
    }

    /// The "G" logo the SDK's own GIDSignInButton draws, from the SDK's resource bundle.
    static let logo: UIImage? = {
        guard let url = Bundle.main.url(forResource: "GoogleSignIn_GoogleSignIn", withExtension: "bundle"),
              let bundle = Bundle(url: url) else { return nil }
        return UIImage(named: "google", in: bundle, with: nil)
    }()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let logo = Self.logo {
                    Image(uiImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text("Sign in with Google")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Brand.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: CutAuthMetrics.rowHeight)
            .background(Capsule().fill(Brand.fill))
            .overlay(Capsule().strokeBorder(Brand.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(CutAuthPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text("Sign in with Google"))
    }
}

private struct CutAuthPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// "or with email" between two hairlines.
struct CutAuthDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Rectangle().fill(DS.Cut.Colors.hairline).frame(height: DS.Cut.Metrics.hairline)
            Text(text)
                .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize()
            Rectangle().fill(DS.Cut.Colors.hairline).frame(height: DS.Cut.Metrics.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}
