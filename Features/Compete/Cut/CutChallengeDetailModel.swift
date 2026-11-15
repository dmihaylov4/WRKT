import Foundation

struct CutChallengeFacts: Equatable {
    struct Participant: Equatable, Identifiable {
        var id: UUID
        var name: String
        var progress: Double
        var isViewer: Bool
    }
    var id: UUID
    var title: String
    var description: String?
    var type: ChallengeType
    var metric: String
    var goal: Double
    var start: Date
    var end: Date
    var evergreen: Bool
    var difficulty: String?
    var participantCount: Int
    var current: Double?
    var percentage: Int
    var completed: Bool
    var participants: [Participant]
    var reward: CutChallengeDetailModel.Reward? = nil
}
struct CutChallengeDetailModel: Equatable {
    enum State: Equatable { case notJoined, joined, completed, ended }
    struct Leader: Equatable, Identifiable {
        var id: UUID
        var rank: String
        var name: String
        var progress: String
        var percentage: String
        var isViewer: Bool
    }
    enum Reward: Equatable {
        case skin(id: Int, name: String)
        case plate(id: Int, name: String)
    }
    var id: UUID
    var title: String
    var state: State
    /// One line under the title: type and time ("Workouts, 14 days left").
    var subtitle: String
    var time: String
    var goal: String
    var progress: String?
    /// The progress numeral, its dimmed goal and the unit ("6", "/ 10", "workouts").
    var amount: String?
    var amountRest: String
    var unit: String
    var fraction: Double
    var percentage: String
    /// The one bold line under the progress.
    var headline: String
    var headlineIsLime: Bool
    var action: String
    var leaves: Bool
    var about: [CutBattleDetailModel.Row]
    var description: String?
    var leaders: [Leader]
    var reward: Reward?
}
enum CutChallengeDetailLogic {
    static func amount(_ value: Double, facts: CutChallengeFacts, unit: WeightUnit, locale: Locale) -> String {
        if facts.type == .totalVolume { return CutCompeteFormat.score(value, type: .volume, unit: unit, locale: locale) }
        return CutCompeteFormat.number(value.rounded(.towardZero), locale: locale)
    }
    static func suffix(_ facts: CutChallengeFacts, unit: WeightUnit) -> String {
        switch facts.type {
        case .totalVolume: return unit.label
        case .workoutCount: return "workouts"
        case .streak: return "days"
        case .specificExercise: return "reps"
        case .custom: return facts.metric == "conditioning_minutes" ? "min" : facts.metric
        }
    }
    /// Short type name for the one line under a challenge.
    static func typeName(_ facts: CutChallengeFacts) -> String {
        switch facts.type {
        case .totalVolume: return "Volume"
        case .workoutCount: return "Workouts"
        case .streak: return "Streak"
        case .specificExercise: return "Exercise"
        case .custom: return facts.metric == "conditioning_minutes" ? "Conditioning" : "Custom"
        }
    }
    static func time(_ facts: CutChallengeFacts, now: Date, calendar: Calendar) -> String {
        facts.completed ? "Completed" : facts.evergreen ? "Ongoing" : CutCompeteFormat.remaining(end: facts.end, now: now, calendar: calendar)
    }
    static func model(_ facts: CutChallengeFacts, unit: WeightUnit, locale: Locale = .current, now: Date = Date(), calendar: Calendar = .current) -> CutChallengeDetailModel {
        let joined = facts.current != nil
        let state: CutChallengeDetailModel.State = facts.completed ? .completed : !facts.evergreen && now > facts.end ? .ended : joined ? .joined : .notJoined
        let goal = amount(facts.goal, facts: facts, unit: unit, locale: locale)
        let suffix = suffix(facts, unit: unit)
        let time = time(facts, now: now, calendar: calendar)
        let duration = calendar.dateComponents([.day], from: facts.start, to: facts.end).day ?? 0
        var about = [CutBattleDetailModel.Row(label: "Participants", value: CutCompeteFormat.number(Double(facts.participantCount), locale: locale)),
                     .init(label: "Duration", value: facts.evergreen ? "Ongoing" : "\(duration) days")]
        if !facts.evergreen {
            about.append(.init(label: "Runs", value: CutCompeteFormat.day(facts.start, locale: locale, calendar: calendar) + " to " + CutCompeteFormat.day(facts.end, locale: locale, calendar: calendar)))
        }
        if let difficulty = facts.difficulty { about.append(.init(label: "Difficulty", value: difficulty)) }
        switch facts.reward {
        case .skin(_, let name): about.append(.init(label: "Reward", value: "\(name) bar skin, 200 XP"))
        case .plate(_, let name): about.append(.init(label: "Reward", value: "\(name) plate, 20 kg, 200 XP"))
        case nil: break
        }
        let current = facts.current.map { amount($0, facts: facts, unit: unit, locale: locale) }
        let headline: String
        switch state {
        case .completed: headline = "Challenge complete"
        case .ended: headline = joined ? "Ended at \(facts.percentage)%" : "This challenge has ended"
        case .joined: headline = "\(facts.percentage)% complete"
        case .notJoined: headline = "Goal: \(goal) \(suffix)"
        }
        return .init(id: facts.id, title: facts.title, state: state, subtitle: typeName(facts) + ", " + time.lowercased(), time: time, goal: goal + " " + suffix,
            progress: current.map { $0 + " / " + goal + " " + suffix }, amount: current, amountRest: "/ " + goal, unit: suffix,
            fraction: max(0, min(1, Double(facts.percentage) / 100)), percentage: "\(facts.percentage)%",
            headline: headline, headlineIsLime: state == .completed,
            action: joined ? "Leave challenge" : "Join challenge", leaves: joined, about: about, description: facts.description,
            leaders: facts.participants.enumerated().map { index, participant in
                .init(id: participant.id, rank: "\(index + 1)", name: participant.name,
                      progress: amount(participant.progress, facts: facts, unit: unit, locale: locale) + " / " + goal + " " + suffix,
                      percentage: "\(min(Int(participant.progress / max(facts.goal, 1) * 100), 100))%", isViewer: participant.isViewer)
            }, reward: facts.reward)
    }
}
