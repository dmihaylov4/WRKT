import SwiftUI

struct CutBattleDetailHost: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel
    var wrapInNavigationStack = true
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    @State private var operation: CutBattleDetailModel.Operation?
    private var live: BattleWithParticipants {
        if let selected = viewModel.selectedBattle, selected.id == battle.id { return selected }
        return battle
    }
    private var model: CutBattleDetailModel {
        CutBattleDetailLogic.model(.init(live, userID: deps.authService.currentUser?.id), unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg)
    }
    var body: some View {
        // Presented as a sheet it is the Cut sheet; pushed from the feed it keeps the back button.
        if wrapInNavigationStack {
            view(inSheet: true)
        } else {
            view(inSheet: false).navigationTitle(model.opponent).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        }
    }
    private func view(inSheet: Bool) -> some View {
        CutBattleDetailView(model: model, operation: operation, actions: .init(accept: {
            Task { await accept() }
        }, exit: { Task { await exit() } }, close: { dismiss() }), inSheet: inSheet)
        .task { await viewModel.refreshSelectedBattle() }
    }
    private func accept() async {
        guard operation == nil else { return }
        operation = .accept
        defer { operation = nil }
        if await viewModel.acceptBattle(live.battle) { dismiss() }
    }
    private func exit() async {
        guard operation == nil else { return }
        operation = .exit
        defer { operation = nil }
        let current = live.battle
        let incoming = current.status == .pending && current.opponentId == deps.authService.currentUser?.id
        let success = incoming ? await viewModel.declineBattle(current) : await viewModel.cancelBattle(current)
        if success { dismiss() }
    }
}

extension CutBattleFacts {
    init(_ value: BattleWithParticipants, userID: UUID?) {
        let b = value.battle
        // Prefer the signed-in user's ID; fall back to the value's own idea of who the viewer is.
        let own = userID.map { $0 == b.challengerId ? value.challenger : value.opponent } ?? value.userProfile
        self.init(id: b.id, type: b.battleType, status: b.status,
                  opponent: CutCompeteFormat.personName(displayName: value.opponentProfile.displayName, username: value.opponentProfile.username),
                  ownScore: userID.map { NSDecimalNumber(decimal: b.score(for: $0)).doubleValue } ?? 0,
                  otherScore: userID.map { NSDecimalNumber(decimal: b.opponentScore(for: $0)).doubleValue } ?? 0,
                  isChallenger: userID == b.challengerId, isOpponent: userID == b.opponentId,
                  start: b.startDate, end: b.endDate, targetMetric: b.targetMetric,
                  ownName: CutCompeteFormat.personName(displayName: own.displayName, username: own.username),
                  ownAvatarURL: own.avatarUrl, opponentAvatarURL: value.opponentProfile.avatarUrl)
    }
}
