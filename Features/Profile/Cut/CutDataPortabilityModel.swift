//
//  CutDataPortabilityModel.swift
//  WRKT
//
//  What the Cut Data portability and Import history pages show, as plain values: the export and
//  import rows while idle or busy, the strategy choice, the last import's counts, the import
//  confirmation's wording, and each past import with the restore confirmation's title. The
//  rules and copy are DataPortabilityView's and ImportHistoryView's.
//

import Foundation

struct CutDataPortabilityModel: Equatable {
    struct Count: Identifiable, Equatable {
        var title: String
        var value: String
        var id: String { title }
    }

    var title = "Data portability"
    /// "Preparing export" while the backup is written; nil when the Export row shows.
    var exportBusyLine: String?
    var exportFooter = CutDataPortabilityLogic.exportFooter
    var strategyOptions = CutDataPortabilityLogic.strategyOptions
    /// "Importing" while a backup is applied; nil when the Import row shows.
    var importBusyLine: String?
    var importFooter = CutDataPortabilityLogic.importFooter
    /// The last import's counts this session; empty before one.
    var lastImport: [Count]
}

struct CutImportHistoryModel: Equatable {
    struct Row: Identifiable, Equatable {
        var id: UUID
        var fileName: String
        /// "Merge, 3 Oct 2026 at 10:12"
        var detail: String
        /// "+12 workouts, +2 plates" for a merge; "34 workouts, 3 plates" for a replace.
        var counts: String
    }

    var title = "Import history"
    var isLoading: Bool
    var rows: [Row]
    var emptyTitle = "No import history"
    var emptyLine = "Imports you apply will appear here."

    var showsEmpty: Bool { !isLoading && rows.isEmpty }
}

struct CutRestoreConfirmation: Equatable {
    var title: String
    var message: String
}

enum CutDataPortabilityLogic {
    static let exportFooter = "Saves strength workouts and earned plates to a JSON file. Cardio runs are excluded: re-sync them from Apple Health."
    static let importFooter = "Merge adds only items not already present. Replace overwrites all existing data: a snapshot is saved automatically so you can undo."

    static let strategyOptions = [
        CutSettingsOption(value: "merge", label: "Merge (keep newer)"),
        CutSettingsOption(value: "replace", label: "Replace all data")
    ]

    static func strategy(_ raw: String) -> ImportStrategy {
        ImportStrategy(rawValue: raw) ?? .merge
    }

    static func model(isExporting: Bool, isImporting: Bool, last: ImportSummary?) -> CutDataPortabilityModel {
        CutDataPortabilityModel(
            exportBusyLine: isExporting ? "Preparing export" : nil,
            importBusyLine: isImporting ? "Importing" : nil,
            lastImport: last.map { lastImport(strategy: $0.record.strategy, workouts: $0.workoutsAdded, plates: $0.platesAdded) } ?? []
        )
    }

    static func lastImport(strategy: String, workouts: Int, plates: Int) -> [CutDataPortabilityModel.Count] {
        let replaced = strategy == "replace"
        return [
            .init(title: replaced ? "Workouts imported" : "Workouts added", value: "\(workouts)"),
            .init(title: replaced ? "Plates imported" : "Plates added", value: "\(plates)")
        ]
    }

    // MARK: Import confirmation

    static func confirmTitle(_ strategy: ImportStrategy) -> String {
        strategy == .replace ? "Replace all existing data with this backup?" : "Add new items from this backup?"
    }

    static func confirmButton(_ strategy: ImportStrategy) -> String {
        strategy == .replace ? "Replace" : "Merge"
    }

    static func confirmIsDestructive(_ strategy: ImportStrategy) -> Bool {
        strategy == .replace
    }

    // MARK: Import history

    static func history(_ records: [ImportRecord], isLoading: Bool,
                        locale: Locale = .current, timeZone: TimeZone = .current) -> CutImportHistoryModel {
        CutImportHistoryModel(isLoading: isLoading, rows: records.reversed().map { row($0, locale: locale, timeZone: timeZone) })
    }

    static func row(_ record: ImportRecord, locale: Locale = .current, timeZone: TimeZone = .current) -> CutImportHistoryModel.Row {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        style.timeZone = timeZone
        let replaced = record.strategy == "replace"
        let sign = replaced ? "" : "+"
        return CutImportHistoryModel.Row(
            id: record.id,
            fileName: record.sourceFileName,
            detail: "\(replaced ? "Replace" : "Merge"), \(record.importedAt.formatted(style))",
            counts: "\(sign)\(record.workoutsAdded) workouts, \(sign)\(record.platesAdded) plates"
        )
    }

    /// Keep the original question and warning, but let the warning wrap as body text.
    static func restoreConfirmation(records: [ImportRecord], restoring id: UUID?) -> CutRestoreConfirmation {
        let text = restoreTitle(records: records, restoring: id)
        guard let end = text.firstIndex(of: "?") else { return .init(title: text, message: "") }
        return .init(title: String(text[...end]), message: String(text[text.index(after: end)...]).trimmingCharacters(in: .whitespaces))
    }

    /// The legacy restore question: it names how many later imports go with it.
    static func restoreTitle(records: [ImportRecord], restoring id: UUID?) -> String {
        guard let id, let index = records.firstIndex(where: { $0.id == id }) else {
            return "Restore to this point?"
        }
        let later = records.count - 1 - index
        if later > 0 {
            return "Restore to this point? \(later) later import(s) will also be removed."
        }
        return "Restore state to before this import?"
    }
}
