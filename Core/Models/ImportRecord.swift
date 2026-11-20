//
//  ImportRecord.swift
//  WRKT
//
//  Tracks a past import. Each record points to a snapshot file containing
//  the app state immediately before the import was applied -- used for restore.
//

import Foundation

struct ImportRecord: Codable, Identifiable {
    let id: UUID
    let importedAt: Date
    let sourceFileName: String      // original filename the user picked
    let strategy: String            // "merge" | "replace"
    let workoutsAdded: Int
    let platesAdded: Int
    let snapshotFileName: String    // filename inside Documents/volia-snapshots/
    /// Workouts from Apple Health added (version 2 backups); absent in older records.
    var runsAdded: Int? = nil
}
