import SwiftUI

struct CutCreateBattleView: View {
    let model: CutCreateBattleModel
    @Binding var draft: CutCreateBattleDraft
    var chooseOpponent: () -> Void = {}
    var send: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: chooseOpponent) {
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.opponent).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                                if let handle = model.handle { Text(handle).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right").font(.system(size: 15))
                        }.frame(minHeight: 50).padding(.vertical, 12).contentShape(Rectangle())
                        CutHairline()
                    }
                }.buttonStyle(.plain)
                CutCompeteSectionTitle("Battle type")
                ForEach(CutCreateBattleLogic.types, id: \.self) { type in
                    Button { draft.type = type } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(CutCompeteFormat.battleTitle(type)).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                                Spacer(minLength: 12)
                                if draft.type == type { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) }
                            }.frame(minHeight: 50).contentShape(Rectangle())
                            if draft.type == type {
                                Text(model.rule).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.bottom, 12)
                            }
                            CutHairline()
                        }
                    }.buttonStyle(.plain).accessibilityAddTraits(draft.type == type ? .isSelected : [])
                }
                CutCompeteSectionTitle("Duration")
                CutCompeteFilterRow(options: CutCreateBattleLogic.durations.map { "\($0) days" }, selected: CutCreateBattleLogic.durations.firstIndex(of: draft.duration) ?? 1) {
                    draft.duration = CutCreateBattleLogic.durations[$0]
                }.padding(.horizontal, -DS.Cut.Metrics.gutter)
                Text("Starts when accepted").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.top, 8)
                DisclosureGroup { CutBattleRewardRows(rewards: model.rewards) } label: { CutCompeteDisclosureLabel("Rewards") }.tint(DS.Cut.Colors.textSecondary).padding(.top, 20)
                CutHairline()
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 8).padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: send) {
                ZStack { Text("Send Battle Invite").opacity(model.creating ? 0 : 1); if model.creating { ProgressView().tint(DS.Cut.Colors.ink) } }
            }.buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)).disabled(!model.canSend).accessibilityLabel("Send Battle Invite")
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 12)
                .background(DS.Cut.Colors.background)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}

struct CutBattleOpponentView: View {
    let model: CutBattleOpponentModel
    @Binding var query: String
    var select: (UUID) -> Void = { _ in }
    var retry: () -> Void = {}
    var findFriends: () -> Void = {}
    @State private var contentHeight: CGFloat = 400
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                switch model.state {
                case .loading: ProgressView().accessibilityLabel("Loading friends")
                case .failed(let error):
                    Text(error).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                    Button("Try Again", action: retry).buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                case .empty:
                    Text("No friends yet").font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                    Button("Find Friends", action: findFriends).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                case .noResults, .loaded:
                    HStack {
                        TextField("Search friends", text: $query, prompt: Text("Search friends").foregroundStyle(DS.Cut.Colors.textSecondary)).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        if !query.isEmpty { Button("Clear search", systemImage: "xmark") { query = "" }.labelStyle(.iconOnly).frame(width: 44, height: 44) }
                    }.frame(minHeight: 50)
                    CutHairline()
                    if model.state == .noResults { Text("No results").font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).padding(.vertical, 16) }
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { friend in
                            Button { select(friend.id) } label: {
                                HStack(spacing: 12) {
                                    CutSocialAvatar(initials: String(friend.username.prefix(1)).uppercased(), url: friend.avatarURL, size: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.title).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                                        if let handle = friend.handle { Text(handle).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary) }
                                    }
                                    Spacer(minLength: 8)
                                    if friend.id == model.selectedID { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) }
                                }.frame(minHeight: 50).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityAddTraits(friend.id == model.selectedID ? .isSelected : [])
                            CutHairline()
                        }
                    }
                }
            }.padding(DS.Cut.Metrics.gutter)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(min(650, max(260, contentHeight + 80))), .large]).presentationDragIndicator(.visible)
    }
}
