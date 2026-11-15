import Foundation
import Testing
@testable import WRKT

enum CutDataPortabilityFixtures {
    static let base = Date(timeIntervalSince1970: 1_794_571_200)

    static func record(_ name: String, strategy: String, workouts: Int, plates: Int, daysAgo: Int) -> ImportRecord {
        ImportRecord(id: UUID(), importedAt: base.addingTimeInterval(Double(-daysAgo) * 86_400), sourceFileName: name,
                     strategy: strategy, workoutsAdded: workouts, platesAdded: plates, snapshotFileName: "snapshot.json")
    }

    /// Oldest first, as the service stores them.
    static let records = [
        record("volia-backup-2026-08-02.json", strategy: "merge", workouts: 3, plates: 0, daysAgo: 103),
        record("volia-backup-2026-09-21.json", strategy: "replace", workouts: 34, plates: 3, daysAgo: 53),
        record("volia-backup-2026-11-03.json", strategy: "merge", workouts: 12, plates: 2, daysAgo: 10)
    ]
}

@Suite("Cut Data portability logic")
struct CutDataPortabilityLogicTests {
    private typealias F = CutDataPortabilityFixtures
    private let utc = TimeZone(identifier: "UTC")!
    private let locale = Locale(identifier: "en_GB")

    @Test func idleShowsBothActionsAndNoLastImport() {
        let model = CutDataPortabilityLogic.model(isExporting: false, isImporting: false, last: nil)
        #expect(model.exportBusyLine == nil)
        #expect(model.importBusyLine == nil)
        #expect(model.lastImport.isEmpty)
        #expect(model.title == "Data portability")
    }

    @Test func busyStatesReplaceTheirRows() {
        let exporting = CutDataPortabilityLogic.model(isExporting: true, isImporting: false, last: nil)
        #expect(exporting.exportBusyLine == "Preparing export")
        #expect(exporting.importBusyLine == nil)
        let importing = CutDataPortabilityLogic.model(isExporting: false, isImporting: true, last: nil)
        #expect(importing.importBusyLine == "Importing")
    }

    @Test func lastImportWordingFollowsTheStrategy() {
        let merged = CutDataPortabilityLogic.model(isExporting: false, isImporting: false,
                                                   last: ImportSummary(record: F.records[2], workoutsAdded: 12, platesAdded: 2))
        #expect(merged.lastImport.map(\.title) == ["Workouts added", "Plates added"])
        #expect(merged.lastImport.map(\.value) == ["12", "2"])
        let replaced = CutDataPortabilityLogic.lastImport(strategy: "replace", workouts: 34, plates: 3)
        #expect(replaced.map(\.title) == ["Workouts imported", "Plates imported"])
    }

    @Test func strategyOptionsAndConfirmation() {
        #expect(CutDataPortabilityLogic.strategyOptions.map(\.value) == ["merge", "replace"])
        #expect(CutDataPortabilityLogic.strategyOptions.map(\.label) == ["Merge (keep newer)", "Replace all data"])
        #expect(CutDataPortabilityLogic.strategy("replace") == .replace)
        #expect(CutDataPortabilityLogic.strategy("anything") == .merge)
        #expect(CutDataPortabilityLogic.confirmTitle(.merge) == "Add new items from this backup?")
        #expect(CutDataPortabilityLogic.confirmTitle(.replace) == "Replace all existing data with this backup?")
        #expect(CutDataPortabilityLogic.confirmButton(.merge) == "Merge")
        #expect(CutDataPortabilityLogic.confirmButton(.replace) == "Replace")
        #expect(CutDataPortabilityLogic.confirmIsDestructive(.replace))
        #expect(!CutDataPortabilityLogic.confirmIsDestructive(.merge))
    }

    @Test func historyIsNewestFirstWithSignedCountsForMerges() {
        let model = CutDataPortabilityLogic.history(F.records, isLoading: false, locale: locale, timeZone: utc)
        #expect(model.rows.map(\.fileName) == F.records.reversed().map(\.sourceFileName))
        #expect(model.rows[0].counts == "+12 workouts, +2 plates")
        #expect(model.rows[1].counts == "34 workouts, 3 plates")
        #expect(model.rows[0].detail.hasPrefix("Merge, "))
        #expect(model.rows[1].detail.hasPrefix("Replace, "))
        #expect(model.rows[0].detail.contains("3 Nov 2026"))
        #expect(!model.showsEmpty)
    }

    @Test func emptyHistoryShowsTheEmptyLineOnlyWhenNotLoading() {
        #expect(CutDataPortabilityLogic.history([], isLoading: false).showsEmpty)
        #expect(!CutDataPortabilityLogic.history([], isLoading: true).showsEmpty)
    }

    @Test func restoreTitleCountsLaterImports() {
        let records = F.records
        #expect(CutDataPortabilityLogic.restoreTitle(records: records, restoring: records[0].id)
                == "Restore to this point? 2 later import(s) will also be removed.")
        #expect(CutDataPortabilityLogic.restoreTitle(records: records, restoring: records[2].id)
                == "Restore state to before this import?")
        #expect(CutDataPortabilityLogic.restoreTitle(records: records, restoring: nil) == "Restore to this point?")
        #expect(CutDataPortabilityLogic.restoreTitle(records: records, restoring: UUID()) == "Restore to this point?")
    }
}
