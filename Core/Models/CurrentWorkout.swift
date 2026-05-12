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
    var plannedWorkoutID: UUID? = nil
    var activeEntryID: UUID? = nil
    /// Planned exercise IDs intentionally removed during this session.
    /// Used by the planner to treat them as completed when marking the workout done.
    var excusedPlannedExerciseIDs: Set<UUID> = []

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        entries: [WorkoutEntry] = [],
        plannedWorkoutID: UUID? = nil,
        activeEntryID: UUID? = nil,
        excusedPlannedExerciseIDs: Set<UUID> = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.entries = entries
        self.plannedWorkoutID = plannedWorkoutID
        self.activeEntryID = activeEntryID
        self.excusedPlannedExerciseIDs = excusedPlannedExerciseIDs
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, startedAt, entries, plannedWorkoutID, activeEntryID, excusedPlannedExerciseIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        startedAt = (try? c.decode(Date.self, forKey: .startedAt)) ?? .now
        entries = (try? c.decode([WorkoutEntry].self, forKey: .entries)) ?? []
        plannedWorkoutID = try? c.decode(UUID.self, forKey: .plannedWorkoutID)
        activeEntryID = try? c.decode(UUID.self, forKey: .activeEntryID)
        excusedPlannedExerciseIDs = (try? c.decode(Set<UUID>.self, forKey: .excusedPlannedExerciseIDs)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(entries, forKey: .entries)
        try c.encodeIfPresent(plannedWorkoutID, forKey: .plannedWorkoutID)
        try c.encodeIfPresent(activeEntryID, forKey: .activeEntryID)
        try c.encode(excusedPlannedExerciseIDs, forKey: .excusedPlannedExerciseIDs)
    }
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
