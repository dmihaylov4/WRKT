import SwiftUI

/// The new battle sheet: who, what and how long on one screen, then one line and the button.
struct CutCreateBattleView: View {
    let model: CutCreateBattleModel
    @Binding var draft: CutCreateBattleDraft
    var choose: (UUID) -> Void = { _ in }
    var openAll: () -> Void = {}
    var send: () -> Void = {}
    var close: () -> Void = {}
    @State private var showingRewards: Bool

    init(model: CutCreateBattleModel, draft: Binding<CutCreateBattleDraft>, choose: @escaping (UUID) -> Void = { _ in }, openAll: @escaping () -> Void = {},
         send: @escaping () -> Void = {}, close: @escaping () -> Void = {}, showingRewards: Bool = false) {
        self.model = model; _draft = draft; self.choose = choose; self.openAll = openAll; self.send = send; self.close = close
        _showingRewards = State(initialValue: showingRewards)
    }

    var body: some View {
        CutSheet("New battle", close: close) {
            VStack(alignment: .leading, spacing: 0) {
                label("Against").padding(.top, 10)
                friendsRow.padding(.top, 10)
                label("Compete on").padding(.top, 24)
                CutCreateBattleTypeGrid(selected: draft.type) { draft.type = $0 }
                    .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 10)
                Text(model.rule).font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(DS.Cut.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 10)
                label("For").padding(.top, 24)
                CutCreateBattleDurations(selected: draft.duration) { draft.duration = $0 }
                    .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 10)
            }
            .padding(.bottom, 24)
        } footer: {
            VStack(spacing: 10) {
                Button { showingRewards = true } label: {
                    (Text(model.footnote) + Text(" ") + Text(Image(systemName: "info.circle")))
                        .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(model.footnote))
                .accessibilityHint(Text("Shows both rewards"))
                .popover(isPresented: $showingRewards) { rewards }
                Button(action: send) {
                    ZStack {
                        Text(model.sendTitle).opacity(model.creating ? 0 : 1)
                        if model.creating { ProgressView().tint(DS.Cut.Colors.ink) }
                    }
                }
                .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                // Disabled (grey) until an opponent is chosen; while sending it stays lime with a spinner.
                .disabled(!model.canSend && !model.creating)
                .allowsHitTesting(!model.creating)
                .accessibilityLabel(Text(model.creating ? "Sending invitation" : model.sendTitle))
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .headline))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
    }

    private var friendsRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                if model.friendsState == .loading {
                    ProgressView().tint(DS.Cut.Colors.textSecondary).frame(width: 60, height: 60).accessibilityLabel(Text("Loading friends"))
                }
                ForEach(model.picks) { friend in
                    let selected = friend.id == model.selectedID
                    Button { choose(friend.id) } label: {
                        CutCreateBattlePick(title: friend.shortName, selected: selected) {
                            CutCompeteAvatar(initials: friend.initials, url: friend.avatarURL, size: 60)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(friend.name))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button(action: openAll) {
                    CutCreateBattlePick(title: "All", selected: false) {
                        Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold))
                            .frame(width: 60, height: 60)
                            .overlay(Circle().strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("All friends"))
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private var rewards: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rewards").font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .headline)).accessibilityAddTraits(.isHeader)
            CutBattleRewardRows(rewards: model.rewards)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .padding(20)
        .frame(minWidth: 300, alignment: .leading)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(DS.Cut.SheetLevel.stacked.surface)
    }
}

/// One circle in the friends row with its first name beneath; the chosen one has a lime ring.
private struct CutCreateBattlePick<Circle_: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder var circle: () -> Circle_
    var body: some View {
        VStack(spacing: 6) {
            circle()
                .overlay { if selected { Circle().strokeBorder(DS.Cut.Colors.lime, lineWidth: 3) } }
            Text(title)
                .font(DS.Typography.custom(size: 15, weight: selected ? .bold : .medium, relativeTo: .subheadline))
                .foregroundStyle(selected ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 64)
        .contentShape(Rectangle())
    }
}

/// The battle types as a two-column grid of rounded tiles; the selected tile is lime.
struct CutCreateBattleTypeGrid: View {
    let selected: BattleType
    let select: (BattleType) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cutSheetLevel) private var level
    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CutCreateBattleLogic.types, id: \.self) { type in
                let isSelected = type == selected
                Button { select(type) } label: {
                    Text(CutCompeteFormat.battleTitle(type))
                        .font(DS.Typography.custom(size: 17, weight: isSelected ? .bold : .semibold, relativeTo: .body))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(isSelected ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? DS.Cut.Colors.lime : level.control))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The durations as one segmented control; at large text sizes the segments stack.
struct CutCreateBattleDurations: View {
    let selected: Int
    let select: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cutSheetLevel) private var level
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(CutCreateBattleLogic.durations, id: \.self) { days in
                let isSelected = days == selected
                Button { select(days) } label: {
                    Text("\(days) days")
                        .font(DS.Typography.custom(size: 17, weight: isSelected ? .bold : .semibold, relativeTo: .body))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.black : DS.Cut.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(isSelected ? Color.white : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(level.control))
    }
}

/// The all-friends sheet, one step lighter than the new battle sheet beneath it.
struct CutBattleOpponentView: View {
    let model: CutBattleOpponentModel
    @Binding var query: String
    var select: (UUID) -> Void = { _ in }
    var retry: () -> Void = {}
    var findFriends: () -> Void = {}
    var close: () -> Void = {}
    var body: some View {
        CutSheet("Against", level: .stacked, close: close) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .loading:
                    ProgressView().tint(DS.Cut.Colors.textSecondary).frame(maxWidth: .infinity, minHeight: 120).accessibilityLabel(Text("Loading friends"))
                case .failed(let error):
                    message(error)
                    Button("Try again", action: retry).buttonStyle(CutPillButtonStyle(.outline)).padding(.top, 14)
                case .empty:
                    message("No friends yet. Add friends to challenge them.")
                    Button("Find friends", action: findFriends).buttonStyle(CutPillButtonStyle(.lime)).padding(.top, 14)
                case .noResults, .loaded:
                    CutSheetSearchField(prompt: "Search friends", query: $query).padding(.top, 6)
                    if model.state == .noResults {
                        message("No friends match \u{201C}\(query)\u{201D}").padding(.top, 16)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { CutHairline() }
                            row(friend)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.bottom, 24)
        }
    }
    private func message(_ text: String) -> some View {
        Text(text).font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }
    private func row(_ friend: CutBattleOpponent) -> some View {
        let selected = friend.id == model.selectedID
        return Button { select(friend.id) } label: {
            HStack(spacing: 14) {
                CutCompeteAvatar(initials: friend.initials, url: friend.avatarURL, size: 44)
                Text(friend.name).font(DS.Typography.custom(size: 18, weight: selected ? .bold : .semibold, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(DS.Cut.Colors.lime).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(friend.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A filled, fully rounded search field on a sheet.
struct CutSheetSearchField: View {
    let prompt: String
    @Binding var query: String
    @Environment(\.cutSheetLevel) private var level
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.Cut.Colors.textSecondary).accessibilityHidden(true)
            TextField(prompt, text: $query, prompt: Text(prompt).foregroundStyle(DS.Cut.Colors.textSecondary))
                .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(DS.Cut.Colors.textSecondary) }
                    .buttonStyle(.plain).frame(width: 44, height: 44).accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Capsule().fill(level.control))
    }
}
