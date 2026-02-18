//
//  CurrentWorkout.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 26.10.25.
//

import Foundation

struct CurrentWorkout: Identifiable, Codable, Hashable {
    var id = UUID()
    var startedAt: Date = .now
    var entries: [WorkoutEntry] = []
    var plannedWorkoutID: UUID? = nil  // Link to PlannedWorkout if started from one
    var activeEntryID: UUID? = nil  // Track which exercise user is currently focused on
}

// MARK: - CurrentWorkout Superset Helpers
extension CurrentWorkout {
    /// Get all entries in a superset group, sorted by order
    func entriesInSuperset(_ groupID: UUID) -> [WorkoutEntry] {
        entries
            .filter { $0.supersetGroupID == groupID }
            .sorted { ($0.orderInSuperset ?? 0) < ($1.orderInSuperset ?? 0) }
    }

    /// Get the next entry in a superset after the given entry
    func nextSupersetEntry(after entryID: UUID) -> WorkoutEntry? {
        guard let entry = entries.first(where: { $0.id == entryID }),
              let groupID = entry.supersetGroupID else { return nil }
        let grouped = entriesInSuperset(groupID)
        guard let idx = grouped.firstIndex(where: { $0.id == entryID }) else { return nil }
        let nextIdx = (idx + 1) % grouped.count
        return grouped[nextIdx]
    }

    /// Check if completing this set finishes a superset round
    /// A round is complete when all exercises in the superset have the same number of completed sets
    func isLastInSupersetRound(entryID: UUID, completedSetCount: Int) -> Bool {
        guard let entry = entries.first(where: { $0.id == entryID }),
              let groupID = entry.supersetGroupID else { return true }
        let grouped = entriesInSuperset(groupID)
        return grouped.allSatisfy { e in
            e.sets.filter { $0.isCompleted }.count >= completedSetCount
        }
    }

    /// Get the superset partner entries for a given entry (excluding itself)
    func supersetPartners(for entryID: UUID) -> [WorkoutEntry] {
        guard let entry = entries.first(where: { $0.id == entryID }),
              let groupID = entry.supersetGroupID else { return [] }
        return entries.filter { $0.supersetGroupID == groupID && $0.id != entryID }
    }
}
