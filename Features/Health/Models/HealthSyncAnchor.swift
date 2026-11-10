//
//  HealthSyncAnchor.swift
//  WRKT
//
//  SwiftData-persisted anchors for HKAnchoredObjectQuery
//  Enables efficient delta syncing with HealthKit
//

import Foundation
import SwiftData
import HealthKit

@Model
final class HealthSyncAnchor {
    @Attribute(.unique) var dataType: String  // e.g., "running_workouts", "exercise_time", "all_workouts"
    var anchorData: Data?                      // Encoded HKQueryAnchor
    var lastSyncDate: Date
    var syncCount: Int                         // Total number of syncs performed

    init(dataType: String, anchorData: Data? = nil, lastSyncDate: Date = .now, syncCount: Int = 0) {
        self.dataType = dataType
        self.anchorData = anchorData
        self.lastSyncDate = lastSyncDate
        self.syncCount = syncCount
    }

    // Decode the stored anchor
    var anchor: HKQueryAnchor? {
        guard let data = anchorData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    /// Advance only after the imported data is durable. Keep the old in-memory
    /// anchor too if SwiftData rejects the commit, so the next attempt replays safely.
    func commit(_ newAnchor: HKQueryAnchor?, in context: ModelContext,
                after persistData: () async throws -> Void) async throws {
        try await persistData()
        try Task.checkCancellation()
        let encoded = try newAnchor.map {
            try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        let previous = (anchorData, lastSyncDate, syncCount)
        if let encoded { anchorData = encoded }
        lastSyncDate = .now
        syncCount += 1
        do {
            try context.save()
        } catch {
            (anchorData, lastSyncDate, syncCount) = previous
            throw error
        }
    }
}

// MARK: - Route Fetch Queue

@Model
final class RouteFetchTask {
    @Attribute(.unique) var workoutUUID: String
    var workoutDate: Date
    var priority: Int                          // 0 = high (recent/visible), 1 = normal, 2 = low (old)
    var allowAutoPost: Bool?
    var attemptCount: Int
    var lastAttemptDate: Date?
    var status: String                         // "pending", "fetching", "completed", "failed"
    var createdAt: Date

    init(workoutUUID: String, workoutDate: Date, priority: Int = 1, allowAutoPost: Bool = true, attemptCount: Int = 0, status: String = "pending") {
        self.workoutUUID = workoutUUID
        self.workoutDate = workoutDate
        self.priority = priority
        self.allowAutoPost = allowAutoPost
        self.attemptCount = attemptCount
        self.status = status
        self.createdAt = .now
    }
}

// MARK: - Map Snapshot Cache

@Model
final class MapSnapshotCache {
    @Attribute(.unique) var workoutUUID: String
    var snapshotData: Data?                    // PNG image data
    var generatedAt: Date
    var routeHash: String?                     // Hash of route coordinates for invalidation

    init(workoutUUID: String, snapshotData: Data? = nil, routeHash: String? = nil) {
        self.workoutUUID = workoutUUID
        self.snapshotData = snapshotData
        self.generatedAt = .now
        self.routeHash = routeHash
    }
}
