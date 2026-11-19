//
//  CutSettingsView.swift
//  WRKT
//
//  The Settings hub in the Cut language ("Settings A"): the title beside the back button, then
//  Social, Preferences, Support, Debug (DEBUG builds only) and the account row, each headed by a
//  lime condensed title over hairline rows. Counts are small lime badges; Log out is red text. Takes plain values,
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
    /// A Debug button or page row (the switches use the bindings instead).
    var debug: (CutSettingsModel.DebugRow) -> Void = { _ in }
}

struct CutSettingsView: View {
    let model: CutSettingsModel
    var roundedShapes: Binding<Bool> = .constant(false)
    var cutDesign: Binding<Bool> = .constant(true)
    var yearAward3D: Binding<Bool> = .constant(true)
    var actions = CutSettingsActions()

    var body: some View {
        CutSettingsPage(title: model.title) {
            if model.showsSocial {
                CutSettingsSectionHeader("Social", isFirst: true)
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

            CutSettingsSectionHeader("Preferences", isFirst: !model.showsSocial)
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
        case .yearAward3D:
            CutSettingsToggleRow(row.title, subtitle: row.subtitle, isOn: yearAward3D)
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

/// A Settings page: a plain list on the black ground. The title shares the bar with the back
/// button (condensed capitals, 34 pt) and the round `accessory`, when given, sits at the bar's
/// trailing end; the status line, when given, leads the list. At accessibility text sizes the
/// title and accessory return to the list, where they can wrap. Rows draw a hairline under
/// themselves except the last row of a section (before a header, a footer or the end).
/// A list rather than a scroll view so rows can carry swipe actions.
struct CutSettingsPage<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    var subtitleIsLime = false
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    private var titleInBar: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        List {
            Group {
                if !titleInBar {
                    CutSettingsTitle(title: title, subtitle: subtitle, subtitleIsLime: subtitleIsLime, accessory: accessory)
                        .padding(.top, 8)
                } else if let subtitle {
                    CutSettingsSubtitle(text: subtitle, isLime: subtitleIsLime)
                        .padding(.top, 4)
                }
                Group(subviews: content()) { subviews in
                    let roles = subviews.map { $0.containerValues.cutSettingsRole }
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                        subview.environment(\.cutSettingsRowHairline, CutSettingsLayout.showsHairline(at: index, roles: roles))
                    }
                }
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .modifier(CutSettingsTitleBar(isShown: titleInBar, hasAccessory: Accessory.self != EmptyView.self) {
            Text(title)
                .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.xs.size, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: titleWidth, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        } accessory: {
            accessory()
                .labelStyle(.iconOnly)
                .tint(DS.Cut.Colors.textPrimary)
        })
    }

    /// A leading bar item is sized to its content, so the title gets a set width beside the back
    /// button: long titles shrink instead of clipping.
    private var titleWidth: CGFloat? {
        guard width > 0 else { return nil }
        // The bar moves a leading item wider than about half the bar into its overflow menu,
        // so the trailing button's room is kept even when the page has none.
        return max(120, width - 32 - 44 - 14 - 56)
    }
}

extension CutSettingsPage where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, subtitleIsLime: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, subtitleIsLime: subtitleIsLime,
                  accessory: { EmptyView() }, content: content)
    }
}

/// The page title and its round button as bar items. On iOS 26 the title draws without the
/// bar's glass; the button keeps it, so it matches the back button beside the title.
private struct CutSettingsTitleBar<Title: View, Accessory: View>: ViewModifier {
    let isShown: Bool
    let hasAccessory: Bool
    @ViewBuilder var title: () -> Title
    @ViewBuilder var accessory: () -> Accessory

    func body(content: Content) -> some View {
        if !isShown {
            content
        } else if #available(iOS 26, *) {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { title() }
                    .sharedBackgroundVisibility(.hidden)
                if hasAccessory {
                    ToolbarItem(placement: .topBarTrailing) { accessory() }
                }
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { title() }
                if hasAccessory {
                    ToolbarItem(placement: .topBarTrailing) { accessory() }
                }
            }
        }
    }
}

/// What a list item is to the hairline rule.
enum CutSettingsItemRole: Sendable { case row, header, footer }

extension ContainerValues {
    @Entry var cutSettingsRole: CutSettingsItemRole = .row
}

extension EnvironmentValues {
    /// False on the last row of a section, which sits on the ground without a hairline.
    @Entry var cutSettingsRowHairline: Bool = true
}

enum CutSettingsLayout {
    /// A row draws its hairline only when another row follows it in the same section.
    static func showsHairline(at index: Int, roles: [CutSettingsItemRole]) -> Bool {
        guard roles.indices.contains(index), roles[index] == .row else { return false }
        let next = index + 1
        return roles.indices.contains(next) && roles[next] == .row
    }
}

/// The hairline under a Settings row, unless it is the last row of its section.
struct CutSettingsRowHairline: View {
    @Environment(\.cutSettingsRowHairline) private var isShown

    var body: some View {
        if isShown { CutHairline() }
    }
}

/// The status line under the title: secondary text, or lime when it reports progress.
struct CutSettingsSubtitle: View {
    let text: String
    var isLime = false

    var body: some View {
        Text(text)
            .font(DS.Cut.Typography.font(.secondary).weight(isLime ? .semibold : .medium))
            .foregroundStyle(isLime ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The page title in condensed capitals (Hero.xs, 34 pt), an optional round menu button beside
/// it, and an optional status line under it: the in-list title at accessibility text sizes.
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
                CutSettingsSubtitle(text: subtitle, isLime: subtitleIsLime)
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

/// A section title: lime condensed capitals at 22 pt, more space above than below, no hairline,
/// so it never reads as a row.
struct CutSettingsSectionHeader: View {
    let title: String
    var isFirst = false

    init(_ title: String, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }

    var body: some View {
        Text(title)
            .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3))
            .textCase(.uppercase)
            .foregroundStyle(DS.Cut.Colors.lime)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isFirst ? 20 : 30)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            .containerValue(\.cutSettingsRole, .header)
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
            .containerValue(\.cutSettingsRole, .footer)
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
                    if valueTone == .lime {
                        CutSettingsBadge(text: value)
                            .accessibilityLabel(Text(accessibilityValue ?? value))
                    } else {
                        Text(value)
                            .font(CutSettingsType.value)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityLabel(Text(accessibilityValue ?? value))
                    }
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
                                 titleColor: role == .destructive ? CutSettingsColors.destructive : DS.Cut.Colors.textPrimary,
                                 titleWeight: role == .destructive ? .semibold : .medium) {
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
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            CutSettingsRowHairline()
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
                    .font(CutSettingsType.value)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            } accessory: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CutSettingsColors.chevron)
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
                .font(CutSettingsType.value)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The row frame every Settings row shares: title (and subtitle) on the left, the value and an
/// accessory (chevron, switch glyph) on the right, 50 pt minimum, a hairline under it unless it
/// ends its section. At
/// accessibility sizes the value drops under the title instead of squeezing it; the accessory
/// stays on the right.
struct CutSettingsRowLayout<Value: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    var titleColor: Color = DS.Cut.Colors.textPrimary
    var titleWeight: DS.Typography.Weight = .medium
    @ViewBuilder var value: () -> Value
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        CutSettingsRowText(title: title, subtitle: subtitle, titleColor: titleColor, titleWeight: titleWeight)
                        value()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    CutSettingsRowText(title: title, subtitle: subtitle, titleColor: titleColor, titleWeight: titleWeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    value()
                }
                accessory()
            }
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            CutSettingsRowHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension CutSettingsRowLayout where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, titleColor: Color = DS.Cut.Colors.textPrimary,
         titleWeight: DS.Typography.Weight = .medium, @ViewBuilder value: @escaping () -> Value) {
        self.init(title: title, subtitle: subtitle, titleColor: titleColor, titleWeight: titleWeight, value: value,
                  accessory: { EmptyView() })
    }
}

/// Title (18 pt medium) over an optional secondary line; both wrap rather than truncate.
struct CutSettingsRowText: View {
    let title: String
    var subtitle: String?
    var titleColor: Color = DS.Cut.Colors.textPrimary
    var titleWeight: DS.Typography.Weight = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.custom(size: 18, weight: titleWeight, relativeTo: .body))
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
            .foregroundStyle(CutSettingsColors.chevron)
            .accessibilityHidden(true)
    }
}

/// A count on a row ("3" on Activity): a small lime pill with ink digits.
struct CutSettingsBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Typography.custom(size: 15, weight: .bold, relativeTo: .subheadline, monospacedDigits: true))
            .foregroundStyle(DS.Cut.Colors.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(Capsule().fill(DS.Cut.Colors.lime))
    }
}

enum CutSettingsType {
    /// Trailing values ("Connected", "kg"): 16 pt secondary text.
    static var value: Font { DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout, monospacedDigits: true) }
}

enum CutSettingsColors {
    /// The system red batch 3 uses for destructive text and outlines.
    static let destructive = Color.red
    /// The row chevron: quieter than the values beside it.
    static let chevron = DS.Palette.gray400
}
