//
//  CutSettingsView.swift
//  WRKT
//
//  The Settings hub in the Cut language: a modest condensed title, then Social, Preferences,
//  Support, Debug (DEBUG builds only) and the account row as sentence-case sections of hairline
//  rows. Badge counts are lime numerals on the right; Log out is red text. Takes plain values,
//  bindings for the two Debug switches, and closures, so every state renders without services.
//
//  The CutSettings page, section, row and switch pieces at the end of this file are shared by
//  every Cut screen reached from Settings (Preferences, Apple Health, Data portability, Import
//  history, Diagnostics). They are candidates for DesignSystem/Cut.
//

import SwiftUI

struct CutSettingsActions {
    var openMyProfile: () -> Void = {}
    var openActivity: () -> Void = {}
    var openFriends: () -> Void = {}
    var openFriendRequests: () -> Void = {}
    var openFindFriends: () -> Void = {}
    var openPreferences: () -> Void = {}
    var openHealth: () -> Void = {}
    var openDataPortability: () -> Void = {}
    var openDiagnostics: () -> Void = {}
    var logIn: () -> Void = {}
    var logOut: () -> Void = {}
    /// A Debug button or page row (the two switches use the bindings instead).
    var debug: (CutSettingsModel.DebugRow) -> Void = { _ in }
}

struct CutSettingsView: View {
    let model: CutSettingsModel
    var roundedShapes: Binding<Bool> = .constant(false)
    var cutDesign: Binding<Bool> = .constant(true)
    var actions = CutSettingsActions()

    var body: some View {
        CutSettingsPage(title: model.title) {
            if model.showsSocial {
                CutSettingsSectionHeader("Social")
                CutSettingsLinkRow("My profile", action: actions.openMyProfile)
                CutSettingsLinkRow("Activity", value: model.activityBadge, valueTone: .lime,
                                   accessibilityValue: model.activityBadge.map { "\($0) new" },
                                   action: actions.openActivity)
                CutSettingsLinkRow("Friends", action: actions.openFriends)
                CutSettingsLinkRow("Friend requests", value: model.friendRequestBadge, valueTone: .lime,
                                   accessibilityValue: model.friendRequestBadge.map { "\($0) new" },
                                   action: actions.openFriendRequests)
                CutSettingsLinkRow("Find friends", action: actions.openFindFriends)
            }

            CutSettingsSectionHeader("Preferences")
            CutSettingsLinkRow("App preferences", action: actions.openPreferences)
            CutSettingsLinkRow("Apple Health", action: actions.openHealth)
            CutSettingsLinkRow("Data portability", action: actions.openDataPortability)

            CutSettingsSectionHeader("Support")
            CutSettingsLinkRow("Diagnostics", action: actions.openDiagnostics)

            if !model.debugRows.isEmpty {
                CutSettingsSectionHeader("Debug")
                ForEach(model.debugRows) { row in
                    debugRow(row)
                }
            }

            switch model.account {
            case .logIn:
                CutSettingsSectionHeader("Account")
                CutSettingsActionRow("Log in to enable social features", action: actions.logIn)
            case .logOut:
                CutSettingsSectionHeader("Account")
                CutSettingsActionRow("Log out", role: .destructive, action: actions.logOut)
            case .none:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func debugRow(_ row: CutSettingsModel.DebugRow) -> some View {
        switch row {
        case .roundedShapes:
            CutSettingsToggleRow(row.title, subtitle: row.subtitle, isOn: roundedShapes)
        case .cutDesign:
            CutSettingsToggleRow(row.title, subtitle: row.subtitle, isOn: cutDesign)
        default:
            if row.pushes {
                CutSettingsLinkRow(row.title, subtitle: row.subtitle) { actions.debug(row) }
            } else {
                CutSettingsActionRow(row.title, subtitle: row.subtitle) { actions.debug(row) }
            }
        }
    }
}

// MARK: - Shared Settings pieces

/// A Settings page: a plain list on the black ground with the title as its first row, set in
/// Hero.xs as on the record screens. The bar keeps only the back button (and the trailing
/// `accessory` beside the title, when given), so content never sits under a bar title.
/// A list rather than a scroll view so rows can carry swipe actions.
struct CutSettingsPage<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    var subtitleIsLime = false
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        List {
            Group {
                CutSettingsTitle(title: title, subtitle: subtitle, subtitleIsLime: subtitleIsLime, accessory: accessory)
                    .padding(.top, 8)
                content()
                // Clears the floating tab bar, as on Cut Me.
                Color.clear
                    .frame(height: DS.Redesign.tabBarClearance(legacy: 80, system: 60) + 24)
                    .accessibilityHidden(true)
            }
            .cutSettingsRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .workoutDetailScrollEdge()
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension CutSettingsPage where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, subtitleIsLime: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, subtitleIsLime: subtitleIsLime,
                  accessory: { EmptyView() }, content: content)
    }
}

/// The page title in condensed capitals (Hero.xs, 34 pt), an optional round menu button beside
/// it, and an optional status line under it.
struct CutSettingsTitle<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var subtitleIsLime = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                CutHeroText(CutHeroText.balancedLines(title), hero: .xs, minimumScaleFactor: 0.6)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                accessory()
                    .menuStyle(.button)
                    .buttonStyle(CutIconButtonStyle(diameter: DS.Cut.Metrics.minTouchTarget))
                    .fixedSize()
            }
            if let subtitle {
                Text(subtitle)
                    .font(DS.Cut.Typography.font(.secondary).weight(subtitleIsLime ? .semibold : .medium))
                    .foregroundStyle(subtitleIsLime ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Gutter insets, no system separator, black row background.
    func cutSettingsRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: DS.Cut.Metrics.gutter, bottom: 0, trailing: DS.Cut.Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Cut.Colors.background)
    }
}

/// A sentence-case section title at body size with the hairline that tops its first row.
struct CutSettingsSectionHeader: View {
    let title: String
    var isFirst = false

    init(_ title: String, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle(title)
            CutHairline()
        }
        .padding(.top, isFirst ? 24 : 36)
    }
}

/// Explanatory copy under a section, in secondary text.
struct CutSettingsFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .cutFont(.secondary)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }
}

/// A row that opens a page or sheet: title, optional value on the right, chevron.
struct CutSettingsLinkRow: View {
    let title: String
    var value: String?
    var valueTone: CutHairlineRow.ValueTone = .secondary
    var subtitle: String?
    var accessibilityValue: String?
    let action: () -> Void

    init(_ title: String, value: String? = nil, valueTone: CutHairlineRow.ValueTone = .secondary,
         subtitle: String? = nil, accessibilityValue: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.valueTone = valueTone
        self.subtitle = subtitle
        self.accessibilityValue = accessibilityValue
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CutSettingsRowLayout(title: title, subtitle: subtitle) {
                if let value {
                    Text(value)
                        .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                        .foregroundStyle(valueTone == .lime ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel(Text(accessibilityValue ?? value))
                }
            } accessory: {
                CutSettingsChevron()
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// A row that acts in place: title only, red when destructive.
struct CutSettingsActionRow: View {
    let title: String
    var subtitle: String?
    var role: ButtonRole?
    var systemImage: String?
    let action: () -> Void

    init(_ title: String, subtitle: String? = nil, role: ButtonRole? = nil, systemImage: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.role = role
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            CutSettingsRowLayout(title: title, subtitle: subtitle,
                                 titleColor: role == .destructive ? CutSettingsColors.destructive : DS.Cut.Colors.textPrimary) {
                EmptyView()
            } accessory: {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// A switch row: lime when on, with an optional explanation under the title.
struct CutSettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isOn) {
                CutSettingsRowText(title: title, subtitle: subtitle)
            }
            .tint(DS.Cut.Colors.lime)
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
    }
}

/// A choice between a few options: the chosen one as the value, a menu with a check to change it.
struct CutSettingsChoiceRow<Value: Hashable>: View {
    let title: String
    let options: [CutSettingsOption<Value>]
    @Binding var selection: Value

    init(_ title: String, options: [CutSettingsOption<Value>], selection: Binding<Value>) {
        self.title = title
        self.options = options
        self._selection = selection
    }

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } label: {
            CutSettingsRowLayout(title: title) {
                Text(selectedLabel)
                    .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            } accessory: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(selectedLabel))
        .accessibilityAddTraits(.isButton)
    }
}

/// One option of a choice row.
struct CutSettingsOption<Value: Hashable>: Identifiable, Hashable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// A value row: title on the left, the value as plain secondary text on the right.
struct CutSettingsValueRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        CutSettingsRowLayout(title: title) {
            Text(value)
                .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The row frame every Settings row shares: title (and subtitle) on the left, the value and an
/// accessory (chevron, switch glyph) on the right, 50 pt minimum, bottom hairline. At
/// accessibility sizes the value drops under the title instead of squeezing it; the accessory
/// stays on the right.
struct CutSettingsRowLayout<Value: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    var titleColor: Color = DS.Cut.Colors.textPrimary
    @ViewBuilder var value: () -> Value
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        CutSettingsRowText(title: title, subtitle: subtitle, titleColor: titleColor)
                        value()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    CutSettingsRowText(title: title, subtitle: subtitle, titleColor: titleColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    value()
                }
                accessory()
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension CutSettingsRowLayout where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, titleColor: Color = DS.Cut.Colors.textPrimary,
         @ViewBuilder value: @escaping () -> Value) {
        self.init(title: title, subtitle: subtitle, titleColor: titleColor, value: value, accessory: { EmptyView() })
    }
}

/// Title over an optional secondary line; both wrap rather than truncate.
struct CutSettingsRowText: View {
    let title: String
    var subtitle: String?
    var titleColor: Color = DS.Cut.Colors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .cutFont(.title)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CutSettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .accessibilityHidden(true)
    }
}

enum CutSettingsColors {
    /// The system red batch 3 uses for destructive text and outlines.
    static let destructive = Color.red
}

/// An outlined red pill, as batch 3's Delete workout: a destructive action that is not a row.
struct CutSettingsDestructiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Cut.Typography.font(.buttonCompact).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(CutSettingsColors.destructive)
            .padding(.horizontal, 18)
            .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
            .overlay(Capsule().strokeBorder(CutSettingsColors.destructive.opacity(0.6), lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
