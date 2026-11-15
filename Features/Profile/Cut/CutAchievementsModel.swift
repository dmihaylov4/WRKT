//
//  CutAchievementsModel.swift
//  WRKT
//
//  What the Cut milestones page (AchievementsView) shows, as plain values: the search and filter
//  over title and description, then In progress rows with their a/b count and Unlocked rows with
//  their date, or the empty state.
//

import Foundation

struct CutAchievementFacts: Equatable {
    var id: String
    var title: String
    var desc: String
    var progress: Int
    var target: Int
    var unlockedAt: Date?
}

enum CutAchievementsFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case inProgress = "In progress"
    case unlocked = "Unlocked"
    var id: String { rawValue }
}

struct CutAchievementsModel: Equatable {
    struct Row: Identifiable, Equatable {
        var id: String
        var title: String
        var detail: String
        /// "3/10" in progress, the date when unlocked.
        var value: String
        /// 0...1 for the slanted bar; nil when unlocked.
        var fraction: Double?
        var isUnlocked: Bool
    }

    var title = "Milestones"
    /// "4 of 12 unlocked"
    var countLine: String
    var filterOptions: [CutSettingsOption<CutAchievementsFilter>]
    var inProgress: [Row]
    var unlocked: [Row]
    var emptyTitle = "No achievements"
    var emptyMessage = "Log more workouts or adjust your filters."
    var isEmpty: Bool { inProgress.isEmpty && unlocked.isEmpty }
}

enum CutAchievementsLogic {
    static func model(_ achievements: [CutAchievementFacts], search: String, filter: CutAchievementsFilter,
                      locale: Locale = .current) -> CutAchievementsModel {
        let shown = filtered(achievements, search: search, filter: filter)
        return CutAchievementsModel(
            countLine: "\(achievements.filter { $0.unlockedAt != nil }.count) of \(achievements.count) unlocked",
            filterOptions: CutAchievementsFilter.allCases.map { CutSettingsOption(value: $0, label: $0.rawValue) },
            inProgress: shown.filter { $0.unlockedAt == nil }.map { row($0, locale: locale) },
            unlocked: shown.filter { $0.unlockedAt != nil }.map { row($0, locale: locale) }
        )
    }

    /// The legacy filters: text in the title or description, then the state.
    static func filtered(_ achievements: [CutAchievementFacts], search: String,
                         filter: CutAchievementsFilter) -> [CutAchievementFacts] {
        achievements.filter { a in
            (search.isEmpty || a.title.localizedCaseInsensitiveContains(search) || a.desc.localizedCaseInsensitiveContains(search))
                && (filter == .all || (filter == .inProgress) == (a.unlockedAt == nil))
        }
    }

    static func row(_ a: CutAchievementFacts, locale: Locale) -> CutAchievementsModel.Row {
        CutAchievementsModel.Row(
            id: a.id,
            title: a.title,
            detail: a.desc,
            value: a.unlockedAt.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale)) }
                ?? "\(a.progress)/\(a.target)",
            fraction: a.unlockedAt == nil ? fraction(a.progress, of: a.target) : nil,
            isUnlocked: a.unlockedAt != nil
        )
    }

    static func fraction(_ progress: Int, of target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(max(Double(progress) / Double(target), 0), 1)
    }
}
