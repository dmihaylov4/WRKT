import Foundation

struct CutCompeteItem: Equatable, Identifiable {
    enum Target: Hashable { case battle(UUID), challenge(UUID) }
    var id: Target
    var title: String
    var subtitle: String
    var value: String? = nil
    var trailing: String? = nil
    var note: String? = nil
    var progressLabel: String? = nil
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
        let pending = facts.status == .pending
        let own = CutCompeteFormat.score(facts.ownScore, type: facts.type, unit: unit, locale: locale)
        let other = CutCompeteFormat.score(facts.otherScore, type: facts.type, unit: unit, locale: locale)
        let scoreUnit = CutCompeteFormat.unit(facts.type, weight: unit)
        let status = CutBattleDetailLogic.status(CutBattleDetailLogic.presentationState(facts, now: now))
        let time = facts.status == .active ? CutCompeteFormat.remaining(end: facts.end, now: now, calendar: .current) : status
        let duration = Calendar.current.dateComponents([.day], from: facts.start, to: facts.end).day ?? 0
        return .init(id: .battle(facts.id), title: facts.opponent, subtitle: CutCompeteFormat.battleTitle(facts.type),
                     value: pending ? (facts.isOpponent ? "Invitation" : "Invite sent") : "You \(own) : \(other) \(scoreUnit)",
                     trailing: pending ? "\(duration) days" : facts.status == .completed ? status : time + " · " + CutBattleDetailLogic.lead(facts, unit: unit, locale: locale),
                     fraction: facts.status == .active ? CutBattleDetailLogic.split(facts) : nil, incoming: pending && facts.isOpponent,
                     plateTier: facts.type.winnerPlateTierID)
    }

    static func challenge(_ facts: CutChallengeFacts, unit: WeightUnit, locale: Locale = .current, now: Date = Date(), showsDescription: Bool = false) -> CutCompeteItem {
        let suffix = CutChallengeDetailLogic.suffix(facts, unit: unit)
        let goal = CutChallengeDetailLogic.amount(facts.goal, facts: facts, unit: unit, locale: locale) + " " + suffix
        let progress = facts.current.map { CutChallengeDetailLogic.amount($0, facts: facts, unit: unit, locale: locale) + " / " + goal }
        let time = facts.completed ? "Completed" : facts.evergreen ? "Ongoing" : CutCompeteFormat.remaining(end: facts.end, now: now, calendar: .current)
        let participation = facts.participantCount > 0 ? "\(CutCompeteFormat.number(Double(facts.participantCount), locale: locale)) competing" : facts.current == nil ? goal : nil
        var item = CutCompeteItem(id: .challenge(facts.id), title: facts.title,
            subtitle: [facts.type.displayName, facts.difficulty].compactMap { $0 }.joined(separator: " · "), value: progress,
            trailing: [time, participation].compactMap { $0 }.joined(separator: " · "),
            note: showsDescription ? facts.description : nil, progressLabel: "\(facts.percentage)%",
            fraction: facts.current == nil ? nil : max(0, min(1, Double(facts.percentage) / 100)))
        switch facts.reward {
        case .skin(let id, let name): item.barSkinID = id; item.reward = name + " bar skin"
        case .plate(let id, let name): item.plateTier = id; item.reward = name + " plate"
        case nil: break
        }
        return item
    }
    /// A failed or cancelled refresh must retain the last loaded snapshot, including an empty success.
    static func refreshed<Value>(_ previous: Value, candidate: Value, failed: Bool) -> Value { failed ? previous : candidate }
}
