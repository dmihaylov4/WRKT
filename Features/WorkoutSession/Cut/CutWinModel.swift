//
//  CutWinModel.swift
//  WRKT
//
//  Cut workout complete screen: the plain values it shows, built from the RewardSummary and
//  the completed workout that WinScreenCoordinator already holds. Everything the legacy win
//  screen listed keeps a place: the hero, XP and record lines first, then hairline rows.
//

import Foundation

struct CutWinStat: Equatable, Identifiable {
    let value: String
    let label: String
    var id: String { label }
}

struct CutWinRow: Equatable, Identifiable {
    enum Kind: Equatable { case plate, skin, challenge, levelUp, streak, achievement, newExercises, lucky, coins }

    let id: String
    let kind: Kind
    let title: String
    let value: String
}

/// One XP line item as the count-up lands it.
struct CutWinXPItem: Equatable, Identifiable {
    let id: String
    /// The source in title case, as the legacy breakdown named it ("Workout Complete").
    let title: String
    /// The source in sentence case for the label next to the number ("Workout complete").
    let label: String
    let amount: Int
}

/// One beat of the XP count-up: at `time` seconds after the screen appears the total jumps to
/// `total`, and `label` ("+50 Workout complete") joins the line under the number.
struct CutWinXPStep: Equatable {
    let time: TimeInterval
    /// Nil for a step that only completes the total (no line items at all).
    let label: String?
    let total: Int
    /// False when the step lands on top of a reward haptic, so taps do not double up.
    let haptic: Bool
}

/// What the XP count-up shows at one moment.
struct CutWinXPFrame: Equatable {
    let total: Int
    /// How many steps have landed.
    let landed: Int
    /// The landed labels on one quiet line, nil before the first lands.
    let labelsLine: String?
}

struct CutWinModel: Equatable {
    /// "Done." after a workout, "New reward." for rewards that arrive on their own.
    var hero: String
    /// "+240 XP", or nil when no XP was earned.
    var xp: String?
    /// "Level 14, 420 to go".
    var levelLine: String?
    /// "New record" or "3 new records".
    var recordLine: String?
    /// Duration, volume and sets, when a workout was completed.
    var stats: [CutWinStat]
    var rows: [CutWinRow]
    /// The XP line items, in the order the count-up lands them.
    var xpItems: [CutWinXPItem]
    /// The count-up: items one at a time, then a closing step for any difference (a multiplier
    /// or bonus) so the last total always equals the summary's XP. Empty when no XP was earned.
    var xpSteps: [CutWinXPStep]
    var showsShare: Bool
}

enum CutWinLogic {
    static func model(summary: RewardSummary, workout: CompletedWorkout?, unit: WeightUnit,
                      tierName: (Int) -> String? = { _ in nil }) -> CutWinModel {
        let items = xpItems(summary.xpLineItems)
        let haptics = rewardHaptics(gotLuckyBonus: summary.gotLuckyBonus, plateCount: summary.earnedPlates.count)
        return CutWinModel(
            hero: workout != nil ? "Done." : "New reward.",
            xp: summary.xp > 0 ? xpText(summary.xp) : nil,
            levelLine: levelLine(summary),
            recordLine: recordLine(prCount: summary.prCount),
            stats: workout.map { stats($0, unit: unit) } ?? [],
            rows: rows(summary, tierName: tierName),
            xpItems: items,
            xpSteps: xpSteps(items: items, totalXP: summary.xp,
                             closingLabel: summary.gotLuckyBonus ? "Lucky bonus" : "Bonus",
                             quietTimes: haptics.all),
            showsShare: workout != nil
        )
    }

    /// "+240 XP"; "0 XP" before the count-up has landed anything.
    static func xpText(_ xp: Int) -> String {
        xp > 0 ? "+\(grouped(Double(xp)))\u{00A0}XP" : "0\u{00A0}XP"
    }

    // MARK: XP count-up

    /// When the first item lands: after the hero and the XP line have risen into place.
    static let xpCountStart: TimeInterval = 0.6
    /// Time between items.
    static let xpCountInterval: TimeInterval = 0.55
    /// A step this close to a reward haptic stays silent.
    static let hapticGap: TimeInterval = 0.18

    /// Line items that earned XP, in their order.
    static func xpItems(_ lineItems: [XPLineItem]) -> [CutWinXPItem] {
        lineItems.filter { $0.xp > 0 }.map {
            CutWinXPItem(id: $0.id, title: humanize($0.source), label: sentenceCase($0.source), amount: $0.xp)
        }
    }

    /// Items in, timed steps out. Each item adds its amount; if the items fall short of
    /// `totalXP` a closing step adds the difference, and if they overshoot the running total is
    /// held at `totalXP`, so the last step's total is always `totalXP`. With no items the whole
    /// amount lands in one unlabelled step.
    static func xpSteps(items: [CutWinXPItem], totalXP: Int, closingLabel: String,
                        quietTimes: [TimeInterval] = []) -> [CutWinXPStep] {
        guard totalXP > 0 else { return [] }
        var beats: [(label: String?, total: Int)] = []
        var sum = 0
        for item in items {
            sum += item.amount
            beats.append(("+\(grouped(Double(item.amount))) \(item.label)", min(sum, totalXP)))
        }
        if sum < totalXP {
            let difference = totalXP - sum
            beats.append((items.isEmpty ? nil : "+\(grouped(Double(difference))) \(closingLabel)", totalXP))
        }
        return beats.enumerated().map { index, beat in
            let time = xpCountStart + Double(index) * xpCountInterval
            return CutWinXPStep(time: time, label: beat.label, total: beat.total,
                                haptic: !quietTimes.contains { abs($0 - time) < hapticGap })
        }
    }

    /// The count-up at `elapsed` seconds after the screen appeared. Reduce Motion (or a capture)
    /// shows the final total and every label at once.
    static func xpFrame(steps: [CutWinXPStep], elapsed: TimeInterval, reduceMotion: Bool) -> CutWinXPFrame {
        // A small tolerance so a timeline entry that fires a hair early still lands its step.
        let landed = reduceMotion ? steps.count : steps.prefix { $0.time <= elapsed + 0.01 }.count
        let labels = steps.prefix(landed).compactMap(\.label)
        return CutWinXPFrame(total: landed > 0 ? steps[landed - 1].total : 0, landed: landed,
                             labelsLine: labels.isEmpty ? nil : labels.joined(separator: ", "))
    }

    /// The reward feedback CutWinScreen plays, in seconds after it appears: the barbell reward
    /// and the lucky bonus at once, the lucky bonus's second tap, then a tap per plate.
    struct RewardHaptics: Equatable {
        let luckyFollowUp: TimeInterval?
        let plates: [TimeInterval]

        var all: [TimeInterval] { [0] + [luckyFollowUp].compactMap { $0 } + plates }
    }

    static func rewardHaptics(gotLuckyBonus: Bool, plateCount: Int) -> RewardHaptics {
        let baseDelay = gotLuckyBonus ? 0.3 : 0.0
        let plateStart = baseDelay + 1.1
        return RewardHaptics(luckyFollowUp: gotLuckyBonus ? baseDelay + 0.4 : nil,
                             plates: (0..<max(0, plateCount)).map { plateStart + Double($0) * 0.25 })
    }

    /// "Workout Complete" to "Workout complete"; the bare "PR" source reads as "Personal record".
    static func sentenceCase(_ raw: String) -> String {
        let words = humanize(raw)
        if words.lowercased() == "pr" { return "Personal record" }
        guard let first = words.first else { return words }
        return first.uppercased() + words.dropFirst().lowercased()
    }

    static func levelLine(_ summary: RewardSummary) -> String? {
        if let snapshot = summary.xpSnapshot {
            let toGo = max(0, snapshot.afterCeiling - snapshot.afterXP)
            return "Level \(snapshot.afterLevel), \(grouped(Double(toGo))) to go"
        }
        return summary.levelUpTo.map { "Level \($0)" }
    }

    static func recordLine(prCount: Int) -> String? {
        switch prCount {
        case ..<1: return nil
        case 1: return "New record"
        default: return "\(prCount) new records"
        }
    }

    static func stats(_ workout: CompletedWorkout, unit: WeightUnit) -> [CutWinStat] {
        let done = workout.entries.flatMap(\.sets).filter(\.isCompleted)
        let volumeKg = done.reduce(0.0) { $0 + max(0, $1.weight) * Double(max(0, $1.reps)) }
        let seconds = workout.startedAt.map { workout.date.timeIntervalSince($0) } ?? 0
        return [
            CutWinStat(value: duration(seconds), label: "Duration"),
            CutWinStat(value: grouped(unit.displayValue(volumeKg)), label: "\(unit.rawValue) volume"),
            CutWinStat(value: "\(done.count)", label: done.count == 1 ? "Set" : "Sets")
        ]
    }

    /// m:ss under an hour, h:mm from an hour (compact hero numerals drop seconds).
    static func duration(_ seconds: TimeInterval) -> String {
        CutTrainLogic.elapsed(seconds)
    }

    static func rows(_ summary: RewardSummary, tierName: (Int) -> String?) -> [CutWinRow] {
        var rows: [CutWinRow] = []
        for (index, plate) in summary.earnedPlates.enumerated() {
            let weight = CutSetLoggingLogic.number(plate.weightKg) + "\u{00A0}kg"
            let value = tierName(plate.tierID).map { "\(weight), \($0)" } ?? weight
            rows.append(CutWinRow(id: "plate-\(index)", kind: .plate, title: "New plate unlocked", value: value))
        }
        let skins = ([summary.rewardQueue.primary].compactMap { $0 } + summary.rewardQueue.compactEvents)
            .filter { $0.kind == .cosmeticUnlock }
        for event in skins {
            rows.append(CutWinRow(id: "skin-\(event.id)", kind: .skin, title: "New bar skin", value: event.title))
        }
        for challenge in summary.challengeCompletions {
            rows.append(CutWinRow(id: "challenge-\(challenge.id)", kind: .challenge, title: "Challenge done", value: challenge.title))
        }
        if summary.gotLuckyBonus {
            rows.append(CutWinRow(id: "lucky", kind: .lucky, title: "Lucky bonus",
                                  value: "\(multiplier(summary.bonusMultiplier)) XP"))
        }
        if let level = summary.levelUpTo {
            rows.append(CutWinRow(id: "level-\(level)", kind: .levelUp, title: "Level up", value: "Level \(level)"))
        }
        if summary.streakNew > summary.streakOld {
            rows.append(CutWinRow(id: "streak", kind: .streak, title: "Streak",
                                  value: summary.hitStreakMilestone ? "\(summary.streakNew), a milestone" : "\(summary.streakNew)"))
        }
        if summary.newExerciseCount > 0 {
            rows.append(CutWinRow(id: "new-exercises", kind: .newExercises,
                                  title: summary.newExerciseCount == 1 ? "New exercise" : "New exercises",
                                  value: "\(summary.newExerciseCount)"))
        }
        for name in summary.unlockedAchievements.sorted() {
            rows.append(CutWinRow(id: "achievement-\(name)", kind: .achievement, title: "Achievement", value: humanize(name)))
        }
        if summary.coins > 0 {
            rows.append(CutWinRow(id: "coins", kind: .coins, title: "Coins", value: "+\(summary.coins)"))
        }
        return rows
    }

    /// "1.5x", "2x", "3x" as the legacy banner.
    static func multiplier(_ value: Double) -> String {
        if value == 1.5 { return "1.5x" }
        return "\(Int(value))x"
    }

    /// WinScreenView.humanize: snake and kebab case to title case words.
    static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { String($0).capitalized }
            .joined(separator: " ")
    }

    static func grouped(_ value: Double) -> String {
        CutLiveOverviewLogic.grouped(value)
    }
}
