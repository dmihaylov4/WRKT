//
//  CutAchievementsDexModel.swift
//  WRKT
//
//  What the Cut PR Dex (AchievementsDexView) and its detail (DexDetailView) show, as plain
//  values. The dex: the unlocked count, the tiles in AchievementsDexVM's filtered order (unlocked
//  first), the scope, the searching state and the two records rows. The detail: the unlock
//  line, best estimated 1RM and last working set, the rep ladder for 1 to 12 reps, and the Try
//  a PR set when the store suggests one.
//

import Foundation

// MARK: - Dex

struct CutAchievementsDexModel: Equatable {
    struct Tile: Identifiable, Equatable {
        var id: String
        /// The short name (DexText.shortName), as the legacy tile.
        var title: String
        /// "Nov 14, 2026" when unlocked, "Locked" otherwise.
        var status: String
        var isUnlocked: Bool
        var accessibilityLabel: String
    }

    var title = "PR Dex"
    /// "12 of 340 unlocked"
    var countLine: String
    var scopeOptions: [CutSettingsOption<AchievementsDexVM.Scope>]
    var tiles: [Tile]
    var isSearching: Bool
    var records: [CutSettingsRowValue]
}

enum CutAchievementsDexLogic {
    static func model(items: [DexItem], unlocked: Int, total: Int, isSearching: Bool) -> CutAchievementsDexModel {
        CutAchievementsDexModel(
            countLine: "\(unlocked) of \(total) unlocked",
            scopeOptions: AchievementsDexVM.Scope.allCases.map { CutSettingsOption(value: $0, label: $0.rawValue) },
            tiles: items.map(tile),
            isSearching: isSearching,
            // The legacy placeholders: nothing feeds these two rows yet.
            records: [.init(title: "Longest run", value: "Not yet"), .init(title: "Longest streak", value: "Not yet")]
        )
    }

    static func tile(_ item: DexItem) -> CutAchievementsDexModel.Tile {
        let date = item.unlockedAt.map(dateLine)
        return CutAchievementsDexModel.Tile(
            id: item.id,
            title: item.short,
            status: date ?? "Locked",
            isUnlocked: item.isUnlocked,
            accessibilityLabel: date.map { "\(item.name), unlocked on \($0)" } ?? "\(item.name), locked"
        )
    }

    /// The legacy tile's date: "Nov 14, 2026", always in US English as before.
    static func dateLine(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
    }

    /// Tiles in rows of `columns` for the hairline table; the last row may be short.
    static func rows<T>(_ items: [T], columns: Int) -> [[T]] {
        let size = max(columns, 1)
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

// MARK: - Detail

struct CutDexDetailFacts {
    var name: String
    var unlockedAt: Date?
    var bestE1RMKg: Double?
    var lastWorking: (reps: Int, weightKg: Double)?
    /// Best weight for exactly 1 to 12 reps, in kilograms.
    var ladder: [(reps: Int, weightKg: Double?)]
    var attempt: (reps: Int, weightKg: Double)?
    var hasExercise: Bool
    var unit: WeightUnit
}

struct CutDexDetailModel: Equatable {
    struct Cell: Identifiable, Equatable {
        var id: Int { reps }
        var reps: Int
        var label: String
        var value: String
    }

    var title: String
    var unlockLine: String
    var isUnlocked: Bool
    var records: [CutSettingsRowValue]
    var ladder: [Cell]
    /// "5 × 102.5 kg" when the store suggests a PR attempt.
    var attempt: String?
    var showsExerciseActions: Bool
}

enum CutDexDetailLogic {
    static func model(_ facts: CutDexDetailFacts, locale: Locale = .current) -> CutDexDetailModel {
        var records: [CutSettingsRowValue] = []
        if let best = facts.bestE1RMKg {
            records.append(.init(title: "Best est. 1RM", value: facts.unit.format(best)))
            if let last = facts.lastWorking {
                records.append(.init(title: "Last working", value: facts.unit.formatSet(reps: last.reps, weightKg: last.weightKg)))
            }
        }
        return CutDexDetailModel(
            title: facts.name,
            unlockLine: facts.unlockedAt.map {
                "Unlocked \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))"
            } ?? "Log a working set to unlock",
            isUnlocked: facts.unlockedAt != nil,
            records: records,
            ladder: facts.ladder.map {
                .init(reps: $0.reps, label: "\($0.reps) reps", value: $0.weightKg.map { facts.unit.format($0) } ?? "-")
            },
            attempt: facts.hasExercise ? facts.attempt.map { facts.unit.formatSet(reps: $0.reps, weightKg: $0.weightKg) } : nil,
            showsExerciseActions: facts.hasExercise
        )
    }
}
