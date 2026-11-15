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
    var ownName: String = "You"
    var ownAvatarURL: String? = nil
    var opponentAvatarURL: String? = nil
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
    struct Side: Equatable {
        var name: String
        var initials: String
        var avatarURL: String?
        var score: String
    }
    var id: UUID
    var state: State
    /// "You vs Yulia"
    var title: String
    /// One line under the title: type and end ("Volume lifted, ends Friday").
    var subtitle: String
    var opponent: String
    var own: Side
    var other: Side
    var unit: String
    /// The two big scores and the split bar appear once the battle has started.
    var showsScores: Bool
    var split: Double
    /// The one bold line: lead, tie or result.
    var headline: String
    var headlineIsLime: Bool
    var accepts: Bool
    /// Destructive action and its confirmation, when the viewer may take it.
    var exit: String?
    var exitLabel: String? { accepts ? "Decline" : exit }
    var confirmation: String
    /// Dates and rewards, shown in the inner panel.
    var details: [Row]
    var rewards: [Reward]
}

enum CutCompeteFormat {
    /// The one name shown for a person: the display name, or the username when there is none.
    static func personName(displayName: String?, username: String) -> String {
        guard let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return username }
        return displayName
    }
    /// The first word of a name, for tight places ("Challenge Yulia").
    static func shortName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
    /// Two letters for an avatar without a photo: the first letters of the first two words,
    /// or the first two letters of a single word.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "." }).map(String.init)
        if words.count >= 2 { return (words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String((words.first ?? "").prefix(2)).uppercased()
    }
    static func battleTitle(_ type: BattleType) -> String {
        switch type {
        case .volume: "Volume lifted"
        case .workoutCount: "Workouts"
        case .consistency: "Workout days"
        case .pr: "Records"
        case .runningDistance: "Running distance"
        case .exercise: "Exercise"
        }
    }
    /// What a battle is about, inside a sentence ("7 days of workouts").
    static func battleNoun(_ type: BattleType) -> String {
        switch type {
        case .volume: "volume"
        case .workoutCount: "workouts"
        case .consistency: "workout days"
        case .pr: "records"
        case .runningDistance: "running"
        case .exercise: "exercise"
        }
    }
    /// The one rule line for a battle type.
    static func rule(_ type: BattleType) -> String {
        switch type {
        case .volume: "Most weight lifted in total wins."
        case .workoutCount: "Most workouts logged wins."
        case .consistency: "Most days with a workout wins."
        case .pr: "Most personal records set wins."
        case .runningDistance: "Most running distance logged wins."
        case .exercise: "Best performance on the exercise wins."
        }
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
    /// "Nov 13" in the given locale and calendar time zone.
    static func day(_ date: Date, locale: Locale, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        style.locale = locale
        return date.formatted(style)
    }
    /// The weekday within the coming week ("Friday"), otherwise the day ("Nov 20").
    static func end(_ date: Date, now: Date, locale: Locale, calendar: Calendar) -> String {
        guard date > now, date.timeIntervalSince(now) < 6 * 86400 else { return day(date, locale: locale, calendar: calendar) }
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
        return date.formatted(style)
    }
    /// "You lead", "Yulia leads" or "Tied".
    static func standing(_ facts: CutBattleFacts) -> String {
        facts.ownScore == facts.otherScore ? "Tied" : facts.ownScore > facts.otherScore ? "You lead" : "\(facts.opponent) leads"
    }
}

enum CutBattleDetailLogic {
    static func model(_ facts: CutBattleFacts, unit: WeightUnit, locale: Locale = .current,
                      now: Date = Date(), calendar: Calendar = .current) -> CutBattleDetailModel {
        let state = presentationState(facts, now: now)
        let scoreUnit = CutCompeteFormat.unit(facts.type, weight: unit)
        let participant = facts.isChallenger || facts.isOpponent
        let exit = participant && [.pending, .active].contains(facts.status)
            ? (facts.status == .active ? "Leave battle" : facts.isOpponent ? "Decline battle" : "Cancel battle") : nil
        let confirmation = facts.status == .active
            ? "Leaving cancels this battle for both you and \(facts.opponent). Scores will stop updating."
            : facts.isOpponent ? "Decline this battle invitation from \(facts.opponent)?" : "Cancel this battle invitation to \(facts.opponent)?"
        let duration = calendar.dateComponents([.day], from: facts.start, to: facts.end).day ?? 0
        // Plate names read as plates in the "earns" rows, so the word "plate" is left out to keep each on one line.
        let started = [.active, .expired, .won, .lost, .tied].contains(state)
        let timing: String
        switch state {
        case .active: timing = "ends " + CutCompeteFormat.end(facts.end, now: now, locale: locale, calendar: calendar)
        case .expired, .won, .lost, .tied: timing = "ended " + CutCompeteFormat.day(facts.end, locale: locale, calendar: calendar)
        case .pending, .incoming, .declined, .cancelled: timing = duration == 1 ? "1 day" : "\(duration) days"
        }
        let rewards = rewards(type: facts.type, target: facts.targetMetric, unit: unit, locale: locale)
        var details = [CutBattleDetailModel.Row(label: "Runs", value: CutCompeteFormat.day(facts.start, locale: locale, calendar: calendar)
                                                + " to " + CutCompeteFormat.day(facts.end, locale: locale, calendar: calendar))]
        for reward in rewards.reversed() {
            details.append(.init(label: reward.title == "Win" ? "Winner earns" : "Finishing earns",
                                 value: "\(reward.name), \(reward.weightText), \(reward.xp.replacingOccurrences(of: "+", with: ""))"))
        }
        return .init(id: facts.id, state: state, title: "You vs \(facts.opponent)",
                     subtitle: CutCompeteFormat.battleTitle(facts.type) + ", " + timing, opponent: facts.opponent,
                     own: .init(name: facts.ownName, initials: CutCompeteFormat.initials(facts.ownName), avatarURL: facts.ownAvatarURL,
                                score: CutCompeteFormat.score(facts.ownScore, type: facts.type, unit: unit, locale: locale)),
                     other: .init(name: facts.opponent, initials: CutCompeteFormat.initials(facts.opponent), avatarURL: facts.opponentAvatarURL,
                                  score: CutCompeteFormat.score(facts.otherScore, type: facts.type, unit: unit, locale: locale)),
                     unit: scoreUnit, showsScores: started, split: split(facts),
                     headline: headline(facts, state: state, unit: unit, locale: locale, now: now, calendar: calendar),
                     headlineIsLime: state == .won || ((state == .active || state == .expired) && facts.ownScore > facts.otherScore),
                     accepts: facts.status == .pending && facts.isOpponent, exit: exit, confirmation: confirmation,
                     details: details, rewards: rewards)
    }
    static func headline(_ facts: CutBattleFacts, state: CutBattleDetailModel.State, unit: WeightUnit, locale: Locale,
                         now: Date, calendar: Calendar) -> String {
        let margin = CutCompeteFormat.score(abs(facts.ownScore - facts.otherScore), type: facts.type, unit: unit, locale: locale)
            + " " + CutCompeteFormat.unit(facts.type, weight: unit)
        switch state {
        case .active:
            let left = CutCompeteFormat.remaining(end: facts.end, now: now, calendar: calendar)
            let standing = CutCompeteFormat.standing(facts)
            return (standing == "Tied" ? "Tied" : standing + " by " + margin) + " with " + left
        case .expired:
            let standing = CutCompeteFormat.standing(facts)
            return standing == "Tied" ? "Ended tied. Final result soon" : "Ended. \(standing) by \(margin), final result soon"
        case .won: return "You won by " + margin
        case .lost: return "\(facts.opponent) won by " + margin
        case .tied: return "Tied at " + CutCompeteFormat.score(facts.ownScore, type: facts.type, unit: unit, locale: locale) + " " + CutCompeteFormat.unit(facts.type, weight: unit)
        case .incoming: return "\(facts.opponent) invited you"
        case .pending: return "Waiting for \(facts.opponent) to accept"
        case .declined: return "Invitation declined"
        case .cancelled: return "Battle cancelled"
        }
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
        case .incoming: status = "Invited you"
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
