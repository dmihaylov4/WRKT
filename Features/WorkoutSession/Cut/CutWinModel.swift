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

struct CutWinXPItem: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String?
    let xp: String
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
    /// The legacy XP breakdown, opened from a row.
    var xpItems: [CutWinXPItem]
    var showsShare: Bool
}

enum CutWinLogic {
    static func model(summary: RewardSummary, workout: CompletedWorkout?, unit: WeightUnit,
                      tierName: (Int) -> String? = { _ in nil }) -> CutWinModel {
        CutWinModel(
            hero: workout != nil ? "Done." : "New reward.",
            xp: summary.xp > 0 ? "+\(grouped(Double(summary.xp)))\u{00A0}XP" : nil,
            levelLine: levelLine(summary),
            recordLine: recordLine(prCount: summary.prCount),
            stats: workout.map { stats($0, unit: unit) } ?? [],
            rows: rows(summary, tierName: tierName),
            xpItems: summary.xpLineItems.map {
                CutWinXPItem(id: $0.id, title: humanize($0.source), detail: $0.detail.map(humanize), xp: "+\($0.xp)")
            },
            showsShare: workout != nil
        )
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
