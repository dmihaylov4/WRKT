import Foundation

struct CutCompeteItem: Equatable, Identifiable {
    enum Target: Hashable { case battle(UUID), challenge(UUID) }
    var id: Target
    var title: String
    var subtitle: String
    var value: String? = nil
    var trailing: String? = nil
    var fraction: Double? = nil
    var incoming = false
    var plateTier: Int? = nil
    var barSkinID: Int? = nil
    var reward: String? = nil
}
struct CutCompeteModel: Equatable {
    var loading = false
    var error: String?
    var pending: [CutCompeteItem] = []
    var pendingCount = 0
    var active: [CutCompeteItem] = []
    var recommended: [CutCompeteItem] = []
    var completed: [CutCompeteItem] = []
    var summary: [CutBattleDetailModel.Row] = []
}
enum CutCompeteLogic {
    static func model(pending: [CutCompeteItem], battles: [CutCompeteItem], challenges: [CutCompeteItem],
                      available: [CutCompeteItem], completedBattles: [CutCompeteItem], completedChallenges: [CutCompeteItem],
                      loading: Bool, error: String?) -> CutCompeteModel {
        let incoming = pending.filter(\.incoming)
        let counts = [("Active challenges", challenges.count), ("Active battles", battles.count),
                      ("Challenges completed", completedChallenges.count), ("Battles completed", completedBattles.count)]
            .filter { $0.1 > 0 }.map { CutBattleDetailModel.Row(label: $0.0, value: "\($0.1)") }
        return .init(loading: loading, error: error, pending: Array(incoming.prefix(3)), pendingCount: incoming.count,
                     active: Array(battles.prefix(5)) + Array(challenges.prefix(5)), recommended: Array(available.prefix(3)),
                     completed: Array(completedChallenges.prefix(2)) + Array(completedBattles.prefix(2)), summary: counts.count >= 2 ? counts : [])
    }
    static func battle(_ facts: CutBattleFacts, unit: WeightUnit, locale: Locale = .current, now: Date = Date()) -> CutCompeteItem {
        let model = CutBattleDetailLogic.model(facts, unit: unit, locale: locale, now: now)
        let pending = facts.status == .pending
        return .init(id: .battle(facts.id), title: facts.opponent, subtitle: model.type,
                     value: pending ? (facts.isOpponent ? "Invitation" : "Invite sent") : "\(model.ownScore) : \(model.otherScore) \(model.unit)",
                     trailing: pending ? "\(model.details.first?.value ?? "")" : facts.status == .completed ? model.status : model.time,
                     fraction: facts.status == .active ? model.split : nil, incoming: pending && facts.isOpponent,
                     plateTier: facts.type.winnerPlateTierID)
    }
    /// A failed or cancelled refresh must retain the last loaded snapshot, including an empty success.
    static func refreshed<Value>(_ previous: Value, candidate: Value, failed: Bool) -> Value { failed ? previous : candidate }
}
