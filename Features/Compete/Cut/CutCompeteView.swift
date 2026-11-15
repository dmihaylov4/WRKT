import SwiftUI

struct CutCompeteActions {
    var open: (CutCompeteItem.Target) -> Void = { _ in }
    var accept: (UUID) -> Void = { _ in }
    var decline: (UUID) -> Void = { _ in }
    var join: (UUID) -> Void = { _ in }
    var startBattle: () -> Void = {}
    var browse: () -> Void = {}
    var allPending: () -> Void = {}
    var retry: () -> Void = {}
}

/// The Compete tab: Battles and Challenges, each a title with its action and one raised panel of rows.
struct CutCompeteView: View {
    let model: CutCompeteModel
    /// Battles being accepted or declined, and challenges being joined.
    var processing: Set<UUID> = []
    var actions = CutCompeteActions()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.error {
                    CutCompeteErrorPanel(message: error, retry: actions.retry).padding(.bottom, 26)
                }
                CutPanelHeader("Battles") {
                    Button("New battle", action: actions.startBattle).buttonStyle(CutPillButtonStyle(.lime)).disabled(model.loading)
                }
                panel(model.battlesPanel, loadingLabel: "Loading battles") {
                    CutCompetePanelRows(model.invitations, processing: processing, actions: actions)
                    if model.showsAllInvitations {
                        CutHairline()
                        CutCompeteAllRow(title: "All invitations", count: model.invitationCount, action: actions.allPending)
                    }
                    if !model.invitations.isEmpty, !model.battles.isEmpty { CutHairline() }
                    CutCompetePanelRows(model.battles, processing: processing, actions: actions)
                }
                CutPanelHeader("Challenges") {
                    Button("Browse all", action: actions.browse).buttonStyle(CutPillButtonStyle(.outline))
                }
                .padding(.top, 26)
                panel(model.challengesPanel, loadingLabel: "Loading challenges") {
                    CutCompetePanelRows(model.challenges + model.recommended, processing: processing, actions: actions)
                }
                if !model.completed.isEmpty {
                    CutPanelHeader("Recent").padding(.top, 26)
                    CutPanel { CutCompetePanelRows(model.completed, processing: processing, actions: actions) }.padding(.top, 10)
                }
                if !model.summary.isEmpty {
                    CutPanelHeader("Summary").padding(.top, 26)
                    CutPanel {
                        ForEach(Array(model.summary.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { CutHairline() }
                            CutCompeteCountRow(label: row.label, value: row.value)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 60, system: 40))
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
    @ViewBuilder
    private func panel<Rows: View>(_ state: CutCompetePanelState, loadingLabel: String, @ViewBuilder rows: () -> Rows) -> some View {
        switch state {
        case .rows: CutPanel { rows() }.padding(.top, 10)
        case .loading: CutPanel { CutCompeteLoadingRow(label: loadingLabel) }.padding(.top, 10)
        case .empty(let title, let line): CutPanel { CutCompeteMessageRow(title: title, line: line) }.padding(.top, 10)
        case .hidden: EmptyView()
        }
    }
}

extension CutCompeteItem {
    var battleID: UUID? { if case .battle(let id) = id { id } else { nil } }
    var challengeID: UUID? { if case .challenge(let id) = id { id } else { nil } }
    var rowID: UUID { battleID ?? challengeID ?? UUID() }
}

// MARK: - Rows

/// Rows of a panel separated by hairlines.
struct CutCompetePanelRows: View {
    let items: [CutCompeteItem]
    var processing: Set<UUID> = []
    var actions = CutCompeteActions()
    init(_ items: [CutCompeteItem], processing: Set<UUID> = [], actions: CutCompeteActions = .init()) {
        self.items = items; self.processing = processing; self.actions = actions
    }
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { CutHairline() }
            CutCompeteRow(item: item, processing: processing.contains(item.rowID), actions: actions)
        }
    }
}

/// One panel row. Battles carry an avatar and score; challenges carry progress or a Join pill.
struct CutCompeteRow: View {
    let item: CutCompeteItem
    var processing = false
    var actions = CutCompeteActions()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        switch item.kind {
        case .battle, .sent: battleButton.padding(.vertical, 14)
        case .invitation:
            VStack(alignment: .leading, spacing: 14) {
                battleButton
                CutCompeteInvitationButtons(processing: processing, accept: { actions.accept(item.rowID) }, decline: { actions.decline(item.rowID) })
            }
            .padding(.top, 14).padding(.bottom, 16)
        case .challenge, .completedChallenge: challengeButton
        case .available: availableRow
        }
    }
    private func open() { actions.open(item.id) }

    private var battleButton: some View {
        Button(action: open) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) { avatar; titleText }
                        lineText
                        if item.score != nil { scoreText(size: 28) }
                    }
                } else {
                    HStack(spacing: 12) {
                        avatar
                        VStack(alignment: .leading, spacing: 2) { titleText; lineText }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if item.score != nil { scoreText(size: 28).layoutPriority(1) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([item.title, item.line, item.spokenValue].filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
    }

    private var challengeButton: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                if dynamicTypeSize.isAccessibilitySize {
                    titleText
                    if item.score != nil { scoreText(size: 24) }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        titleText.frame(maxWidth: .infinity, alignment: .leading)
                        if item.score != nil { scoreText(size: 24).layoutPriority(1) }
                    }
                }
                if let fraction = item.fraction { CutSplitBar(fraction: fraction, height: 6) }
                lineText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([item.title, item.spokenValue, item.line].filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
    }

    private var availableRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) { titleText; lineText }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            Button { actions.join(item.rowID) } label: {
                ZStack {
                    Text("Join").opacity(processing ? 0 : 1)
                    if processing { ProgressView().tint(DS.Cut.Colors.lime) }
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(CutPillButtonStyle(.outlineLime))
            .allowsHitTesting(!processing)
            .accessibilityLabel(Text("Join " + item.title))
        }
        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
        .padding(.vertical, 14)
    }

    private var avatar: some View {
        CutCompeteAvatar(initials: item.initials ?? "", url: item.avatarURL, size: 44)
    }
    private var titleText: some View {
        Text(item.title).font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var lineText: some View {
        Text(item.line).font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(item.lineIsLime ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func scoreText(size: CGFloat) -> some View {
        CutCompeteScoreText(score: item.score ?? "", rest: item.scoreRest, size: size)
    }
}

/// A score or progress in condensed numerals with the other side dimmed ("12.4k : 9.8k", "6 / 20").
struct CutCompeteScoreText: View {
    let score: String
    var rest: String?
    var size: CGFloat = 28
    var body: some View {
        (Text(score) + Text(rest.map { " " + $0 } ?? "").foregroundStyle(DS.Cut.Colors.textTertiary))
            .font(DS.Cut.Typography.condensed(size: size, relativeTo: .title2))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

/// Accept (white) and Decline (outline) side by side, stacked at large text sizes.
struct CutCompeteInvitationButtons: View {
    /// Both buttons are disabled while either action runs.
    let processing: Bool
    /// Which button shows the spinner; the tab does not know which, so it spins Accept as before.
    var declineOperation = false
    var accept: () -> Void
    var decline: () -> Void
    var inset: CGFloat = DS.Cut.Metrics.panelRowPadding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button(action: accept) {
                ZStack {
                    Text("Accept").opacity(processing && !declineOperation ? 0 : 1)
                    if processing && !declineOperation { ProgressView().tint(.black) }
                }
            }
            .buttonStyle(CutPillButtonStyle(.white, fillsWidth: true))
            .accessibilityLabel(Text("Accept"))
            Button(action: decline) {
                ZStack {
                    Text("Decline").opacity(declineOperation ? 0 : 1)
                    if declineOperation { ProgressView().tint(DS.Cut.Colors.textPrimary) }
                }
            }
            .buttonStyle(CutPillButtonStyle(.outline, fillsWidth: true))
            .accessibilityLabel(Text("Decline"))
        }
        // Keep each pill's look while it works: block taps instead of greying them out.
        .allowsHitTesting(!processing)
        .padding(.horizontal, inset)
    }
}

/// An avatar: the photo, or two initials on a grey (or lime, for the viewer) circle.
struct CutCompeteAvatar: View {
    let initials: String
    var url: String?
    var size: CGFloat = 44
    var isViewer = false
    @Environment(\.cutSheetLevel) private var level
    var body: some View {
        if let url, !url.isEmpty {
            CutSocialAvatar(initials: initials, url: url, size: size)
        } else {
            Text(initials)
                .font(DS.Typography.custom(size: size >= 56 ? 18 : 16, weight: .bold, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isViewer ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
                .padding(4)
                .frame(width: size, height: size)
                .background(Circle().fill(isViewer ? DS.Cut.Colors.lime : level.control))
                .accessibilityHidden(true)
        }
    }
}

struct CutCompeteAllRow: View {
    let title: String
    let count: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)").font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.Cut.Colors.textSecondary).accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(title), \(count)"))
    }
}

struct CutCompeteMessageRow: View {
    let title: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
            Text(line).font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline)).foregroundStyle(DS.Cut.Colors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

struct CutCompeteLoadingRow: View {
    let label: String
    var body: some View {
        ProgressView().tint(DS.Cut.Colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .accessibilityLabel(Text(label))
    }
}

struct CutCompeteErrorPanel: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        CutPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(message).font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: retry).buttonStyle(CutPillButtonStyle(.outline))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
            .padding(.vertical, 16)
        }
    }
}

struct CutCompeteCountRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body)).monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
