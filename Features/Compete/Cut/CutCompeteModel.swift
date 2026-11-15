import Foundation

/// One row in a Compete panel: a battle (with avatar and score) or a challenge (with progress).
struct CutCompeteItem: Equatable, Identifiable {
    enum Target: Hashable { case battle(UUID), challenge(UUID) }
    enum Kind: Equatable {
        /// A started or finished battle: avatar, name, status line, score.
        case battle
        /// An invitation to the viewer: Accept and Decline beneath.
        case invitation
        /// An invitation the viewer sent, waiting on the opponent.
        case sent
        /// A joined challenge: progress and a thin bar.
        case challenge
        /// A challenge the viewer can join: a Join pill.
        case available
        /// A completed challenge.
        case completedChallenge
    }
    var id: Target
    var kind: Kind
    var title: String
    /// The one secondary line.
    var line: String
    /// The line is lime: the viewer leads or won.
    var lineIsLime = false
    var initials: String? = nil
    var avatarURL: String? = nil
    /// The leading numeral: the viewer's score or the challenge progress ("12.4k", "6").
    var score: String? = nil
    /// The dimmed rest after it: the opponent's score or the goal (": 9.8k", "/ 20").
    var scoreRest: String? = nil
    var fraction: Double? = nil
    /// What VoiceOver reads for the score or progress ("You 12.4k, Yulia 9.8k kg").
    var spokenValue: String = ""
    var incoming: Bool { kind == .invitation }
}

/// What a panel shows when it has no rows.
enum CutCompetePanelState: Equatable {
    case rows
    case loading
    case empty(title: String, line: String)
    /// Hidden while an error is shown, so an empty panel does not claim there is nothing.
    case hidden
}

struct CutCompeteModel: Equatable {
    var loading = false
    var error: String?
    /// Up to three invitations to the viewer, then "All invitations" when there are more.
    var invitations: [CutCompeteItem] = []
    var invitationCount = 0
    /// Up to five active battles.
    var battles: [CutCompeteItem] = []
    /// Up to five joined challenges.
    var challenges: [CutCompeteItem] = []
    /// Up to three challenges to join.
    var recommended: [CutCompeteItem] = []
    /// Up to two finished challenges and two finished battles.
    var completed: [CutCompeteItem] = []
    var summary: [CutBattleDetailModel.Row] = []
    var battlesPanel: CutCompetePanelState = .rows
    var challengesPanel: CutCompetePanelState = .rows
    var showsAllInvitations: Bool { invitationCount > invitations.count }
}

enum CutCompeteLogic {
    static func model(pending: [CutCompeteItem], battles: [CutCompeteItem], challenges: [CutCompeteItem],
                      available: [CutCompeteItem], completedBattles: [CutCompeteItem], completedChallenges: [CutCompeteItem],
                      loading: Bool, error: String?) -> CutCompeteModel {
        let incoming = pending.filter(\.incoming)
        let counts = [("Active challenges", challenges.count), ("Active battles", battles.count),
                      ("Challenges completed", completedChallenges.count), ("Battles completed", completedBattles.count)]
            .filter { $0.1 > 0 }.map { CutBattleDetailModel.Row(label: $0.0, value: "\($0.1)") }
        let invitations = Array(incoming.prefix(3)), active = Array(battles.prefix(5))
        let joined = Array(challenges.prefix(5)), recommended = Array(available.prefix(3))
        return .init(loading: loading, error: error, invitations: invitations, invitationCount: incoming.count,
                     battles: active, challenges: joined, recommended: recommended,
                     completed: Array(completedChallenges.prefix(2)) + Array(completedBattles.prefix(2)), summary: counts.count >= 2 ? counts : [],
                     battlesPanel: panel(empty: invitations.isEmpty && active.isEmpty, loading: loading, error: error,
                                         title: "No active battles", line: "Challenge a friend to start one."),
                     challengesPanel: panel(empty: joined.isEmpty && recommended.isEmpty, loading: loading, error: error,
                                            title: "No active challenges", line: "Browse all to find one to join."))
    }
    static func panel(empty: Bool, loading: Bool, error: String?, title: String, line: String) -> CutCompetePanelState {
        if !empty { return .rows }
        if loading { return .loading }
        if error != nil { return .hidden }
        return .empty(title: title, line: line)
    }
    static func battle(_ facts: CutBattleFacts, unit: WeightUnit, locale: Locale = .current, now: Date = Date(), calendar: Calendar = .current) -> CutCompeteItem {
        let state = CutBattleDetailLogic.presentationState(facts, now: now)
        let duration = calendar.dateComponents([.day], from: facts.start, to: facts.end).day ?? 0
        let days = duration == 1 ? "1 day" : "\(duration) days"
        let own = CutCompeteFormat.score(facts.ownScore, type: facts.type, unit: unit, locale: locale)
        let other = CutCompeteFormat.score(facts.otherScore, type: facts.type, unit: unit, locale: locale)
        let scoreUnit = CutCompeteFormat.unit(facts.type, weight: unit)
        let kind: CutCompeteItem.Kind
        let line: String
        switch state {
        case .incoming: kind = .invitation; line = "Invited you, \(days) of \(CutCompeteFormat.battleNoun(facts.type))"
        case .pending: kind = .sent; line = "Invite sent, \(days) of \(CutCompeteFormat.battleNoun(facts.type))"
        case .active: kind = .battle; line = CutCompeteFormat.standing(facts) + ", " + CutCompeteFormat.remaining(end: facts.end, now: now, calendar: calendar).lowercased()
        case .expired: kind = .battle; line = "Ended, " + standingInSentence(facts)
        case .won, .lost, .tied, .declined, .cancelled: kind = .battle; line = CutBattleDetailLogic.status(state)
        }
        let scored = [.active, .expired, .won, .lost, .tied].contains(state)
        return .init(id: .battle(facts.id), kind: kind, title: facts.opponent, line: line,
                     lineIsLime: state == .won || ((state == .active || state == .expired) && facts.ownScore > facts.otherScore),
                     initials: CutCompeteFormat.initials(facts.opponent), avatarURL: facts.opponentAvatarURL,
                     score: scored ? own : nil, scoreRest: scored ? ": " + other : nil,
                     spokenValue: scored ? "You \(own), \(facts.opponent) \(other) \(scoreUnit)" : "")
    }
    private static func standingInSentence(_ facts: CutBattleFacts) -> String {
        let standing = CutCompeteFormat.standing(facts)
        return standing == "You lead" ? "you lead" : standing == "Tied" ? "tied" : standing
    }

    static func challenge(_ facts: CutChallengeFacts, unit: WeightUnit, locale: Locale = .current, now: Date = Date(), calendar: Calendar = .current) -> CutCompeteItem {
        let suffix = CutChallengeDetailLogic.suffix(facts, unit: unit)
        let goal = CutChallengeDetailLogic.amount(facts.goal, facts: facts, unit: unit, locale: locale)
        let typeName = CutChallengeDetailLogic.typeName(facts)
        let kind: CutCompeteItem.Kind = facts.completed ? .completedChallenge : facts.current == nil ? .available : .challenge
        let line: String
        switch kind {
        case .completedChallenge: line = typeName + ", completed"
        case .available: line = "\(goal) \(suffix), " + (facts.difficulty?.lowercased() ?? CutChallengeDetailLogic.time(facts, now: now, calendar: calendar).lowercased())
        default: line = typeName + ", " + CutChallengeDetailLogic.time(facts, now: now, calendar: calendar).lowercased()
        }
        let amount = facts.current.map { CutChallengeDetailLogic.amount($0, facts: facts, unit: unit, locale: locale) }
        return .init(id: .challenge(facts.id), kind: kind, title: facts.title, line: line,
                     score: amount, scoreRest: amount == nil ? nil : "/ " + goal,
                     fraction: kind == .challenge ? max(0, min(1, Double(facts.percentage) / 100)) : nil,
                     spokenValue: amount.map { "\($0) of \(goal) \(suffix), \(facts.percentage) percent" } ?? "")
    }
    /// A failed or cancelled refresh must retain the last loaded snapshot, including an empty success.
    static func refreshed<Value>(_ previous: Value, candidate: Value, failed: Bool) -> Value { failed ? previous : candidate }
}
