import SwiftUI

struct CutBattleDetailHost: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel
    var wrapInNavigationStack = true
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    @State private var processing = false
    private var live: BattleWithParticipants {
        if let selected = viewModel.selectedBattle, selected.id == battle.id { return selected }
        return battle
    }
    private var model: CutBattleDetailModel {
        CutBattleDetailLogic.model(.init(live, userID: deps.authService.currentUser?.id), unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg)
    }
    var body: some View {
        if wrapInNavigationStack { NavigationStack { content } } else { content }
    }
    private var content: some View {
        CutBattleDetailView(model: model, processing: processing, actions: .init(accept: {
            Task { await accept() }
        }, exit: { Task { await exit() } }))
        .navigationTitle(model.opponent).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(DS.Cut.Colors.lime) } }
        .task { await viewModel.refreshSelectedBattle() }
    }
    private func accept() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        if await viewModel.acceptBattle(live.battle) { dismiss() }
    }
    private func exit() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        let current = live.battle
        let incoming = current.status == .pending && current.opponentId == deps.authService.currentUser?.id
        let success = incoming ? await viewModel.declineBattle(current) : await viewModel.cancelBattle(current)
        if success { dismiss() }
    }
}

extension CutBattleFacts {
    init(_ value: BattleWithParticipants, userID: UUID?) {
        let b = value.battle
        self.init(id: b.id, type: b.battleType, status: b.status,
                  opponent: value.opponentProfile.displayName ?? value.opponentProfile.username,
                  ownScore: userID.map { NSDecimalNumber(decimal: b.score(for: $0)).doubleValue } ?? 0,
                  otherScore: userID.map { NSDecimalNumber(decimal: b.opponentScore(for: $0)).doubleValue } ?? 0,
                  isChallenger: userID == b.challengerId, isOpponent: userID == b.opponentId,
                  start: b.startDate, end: b.endDate, targetMetric: b.targetMetric)
    }
}
