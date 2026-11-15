import Foundation

struct CutBattleFacts: Equatable {
    var id: UUID
    var type: BattleType
    var status: BattleStatus
    var opponent: String
    var ownScore: Double
    var otherScore: Double
    var isChallenger: Bool
    var isOpponent: Bool
    var start: Date
    var end: Date
    var targetMetric: String? = nil
}

struct CutBattleDetailModel: Equatable {
    enum State: Equatable { case pending, incoming, active, expired, won, lost, tied, declined, cancelled }
    enum Operation: Equatable { case accept, exit }
    struct Row: Equatable, Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }
    struct Reward: Equatable, Identifiable {
        var id: Int
        var title: String
        var name: String
        var weight: Double
        var weightText: String
        var xp: String
        var liftID: String?
        var engraving: String
    }
    var id: UUID
    var type: String
    var opponent: String
    var state: State
    var status: String
    var time: String
    var ownScore: String
    var otherScore: String
    var unit: String
    var lead: String
    var isLeading: Bool
    var split: Double
    var accepts: Bool
    var exit: String?
    var exitLabel: String? { accepts ? "Decline" : exit }
    var confirmation: String
    var details: [Row]
    var rewards: [Reward]
}

enum CutCompeteFormat {
    static func personName(displayName: String?, username: String) -> String {
        guard let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return username }
        return displayName
    }
    static func battleTitle(_ type: BattleType) -> String {
        type == .consistency ? "Workout days" : type.displayName
    }
    static func number(_ value: Double, decimals: Int = 0, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value.isFinite ? value : 0)) ?? "0"
    }
    static func score(_ score: Double, type: BattleType, unit: WeightUnit, locale: Locale) -> String {
        let value = type == .volume ? unit.displayValue(score) : score
        if type == .volume, abs(value) >= 1000 { return number(value / 1000, decimals: 1, locale: locale) + "k" }
        return number(value, decimals: type == .runningDistance ? 1 : 0, locale: locale)
    }
    static func unit(_ type: BattleType, weight: WeightUnit) -> String {
        switch type {
        case .volume, .pr: return weight.label
        case .workoutCount: return "workouts"
        case .consistency: return "days"
        case .exercise: return "reps"
        case .runningDistance: return "km"
        }
    }
    static func remaining(end: Date, now: Date, calendar: Calendar) -> String {
        guard end > now else { return "Ended" }
        let days = calendar.dateComponents([.day], from: now, to: end).day ?? 0
        if days > 0 { return days == 1 ? "1 day left" : "\(days) days left" }
        let hours = Int(end.timeIntervalSince(now) / 3600)
        return hours > 0 ? (hours == 1 ? "1 hour left" : "\(hours) hours left") : "Less than 1 hour left"
    }
}

enum CutBattleDetailLogic {
    static func model(_ facts: CutBattleFacts, unit: WeightUnit, locale: Locale = .current,
                      now: Date = Date(), calendar: Calendar = .current) -> CutBattleDetailModel {
        let state = presentationState(facts, now: now)
        let status = Self.status(state)
        let scoreUnit = CutCompeteFormat.unit(facts.type, weight: unit)
        let participant = facts.isChallenger || facts.isOpponent
        let exit = participant && [.pending, .active].contains(facts.status)
            ? (facts.status == .active ? "Leave Battle" : facts.isOpponent ? "Decline Battle" : "Cancel Battle") : nil
        let confirmation = facts.status == .active
            ? "Leaving cancels this battle for both you and \(facts.opponent). Scores will stop updating."
            : facts.isOpponent ? "Decline this battle invitation from \(facts.opponent)?" : "Cancel this battle invitation to \(facts.opponent)?"
        let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        let duration = calendar.dateComponents([.day], from: facts.start, to: facts.end).day ?? 0
        return .init(id: facts.id, type: CutCompeteFormat.battleTitle(facts.type), opponent: facts.opponent, state: state, status: status,
                     time: facts.status == .active ? CutCompeteFormat.remaining(end: facts.end, now: now, calendar: calendar) : status,
                     ownScore: CutCompeteFormat.score(facts.ownScore, type: facts.type, unit: unit, locale: locale),
                     otherScore: CutCompeteFormat.score(facts.otherScore, type: facts.type, unit: unit, locale: locale), unit: scoreUnit,
                     lead: lead(facts, unit: unit, locale: locale), isLeading: facts.ownScore > facts.otherScore, split: split(facts),
                     accepts: facts.status == .pending && facts.isOpponent, exit: exit, confirmation: confirmation,
                     details: [.init(label: "Duration", value: "\(duration) days"), .init(label: "Start", value: facts.start.formatted(dateStyle)),
                               .init(label: "End", value: facts.end.formatted(dateStyle))], rewards: rewards(type: facts.type, target: facts.targetMetric, unit: unit, locale: locale))
    }
    static func presentationState(_ facts: CutBattleFacts, now: Date) -> CutBattleDetailModel.State {
        let state: CutBattleDetailModel.State
        switch facts.status {
        case .pending: state = facts.isOpponent ? .incoming : .pending
        case .active: state = facts.end <= now ? .expired : .active
        case .completed: state = facts.ownScore == facts.otherScore ? .tied : facts.ownScore > facts.otherScore ? .won : .lost
        case .declined: state = .declined
        case .cancelled: state = .cancelled
        }
        return state
    }
    static func status(_ state: CutBattleDetailModel.State) -> String {
        let status: String
        switch state {
        case .pending: status = "Invite sent"
        case .incoming: status = "Battle invitation"
        case .active: status = "Active"
        case .expired: status = "Ended"
        case .won: status = "You won"
        case .lost: status = "You lost"
        case .tied: status = "Tied"
        case .declined: status = "Invitation declined"
        case .cancelled: status = "Cancelled"
        }
        return status
    }
    static func lead(_ facts: CutBattleFacts, unit: WeightUnit, locale: Locale) -> String {
        let difference = abs(facts.ownScore - facts.otherScore)
        let scoreUnit = CutCompeteFormat.unit(facts.type, weight: unit)
        return difference == 0 ? "Tied" : "\(facts.ownScore > facts.otherScore ? "You lead" : "Opponent leads") by \(CutCompeteFormat.score(difference, type: facts.type, unit: unit, locale: locale)) \(scoreUnit)"
    }
    static func split(_ facts: CutBattleFacts) -> Double {
        let total = max(facts.ownScore, 0) + max(facts.otherScore, 0)
        return total > 0 ? max(0, min(1, facts.ownScore / total)) : 0.5
    }
    static func rewards(type: BattleType, target: String?, unit: WeightUnit, locale: Locale) -> [CutBattleDetailModel.Reward] {
        [(type.participationPlateTierID, "Complete", 20.0, "+200 XP"), (type.winnerPlateTierID, "Win", 35.0, "+400 XP")].map { id, title, weight, xp in
            .init(id: id, title: title, name: PlateTier.all.first { $0.id == id }?.name ?? "Plate", weight: weight,
                  weightText: CutCompeteFormat.number(unit.displayValue(weight), locale: locale) + " " + unit.label, xp: xp,
                  liftID: title == "Complete" && type == .exercise ? target : nil,
                  engraving: title == "Win" ? type.winnerEngravingText : type.displayName)
        }
    }
}
