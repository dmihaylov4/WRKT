//
//  RunsV3Merge.swift
//  WRKT
//
//  Folds an older app version's writes to the frozen runs_v2.json into runs_v3 (spec section 8):
//  a three-way merge against baseline.json, by the normal form (StoredRun.normalHash), so a
//  rewrite that dropped the routeFromRouteWithHR marker compares equal. Pure: it plans; the
//  store applies the plan through its own per-workout path, and the baseline is rewritten only
//  after that drain is durable. Planning again after a partial application gives no further
//  change (INV-11).
//

import Foundation

nonisolated enum RunsV3Merge {
    /// What the v3 history holds for one workout.
    struct Live {
        let seq: Int64
        let unavailable: Bool
        let healthKitUUID: UUID?
    }

    struct Counts: Codable, Equatable {
        var added = 0
        var replaced = 0
        var trashed = 0
        var deduplicated = 0
        /// Deletions not applied because they exceeded the valve.
        var skippedByValve = 0
        /// Changed by the older build and in v3: v3 kept.
        var conflicts = 0
        /// Deleted in v3 (or re-added by the older build after a v3 delete): stays deleted.
        var keptDeleted = 0
        /// An unreadable v3 workout restored from the older build's copy.
        var repaired = 0

        var changesHistory: Bool { added + replaced + trashed + repaired > 0 }
    }

    struct Plan {
        /// New workouts, in runs_v2.json order (front-most first).
        var adds: [Run] = []
        /// Whole runs replacing v3's, keeping each workout's id and position.
        var replaces: [Run] = []
        var deletes: [UUID] = []
        var counts = Counts()
        var valveTripped: Bool { counts.skippedByValve > 0 }
    }

    /// The most deletions an older build may make before none are applied: max(5, 20 percent of
    /// the history at the last reconciliation) (owner's decision).
    static func valveLimit(baselineCount: Int) -> Int { max(5, baselineCount / 5) }

    /// Plans the merge (spec 8.3, with the outcomes added in batch 3b).
    /// - `baseline`: baseline.json's entries. Empty when runs_v2.json appeared without one.
    /// - `v2`: runs_v2.json now, decoded, in its order.
    /// - `live`: the v3 history by id.
    /// - `trashed`: ids with a recorded deletion in v3's trash.
    /// - `current`: a v3 workout's full record: nil when it cannot be read.
    static func plan(baseline: [RunsV3BaselineV1.Entry], v2: [Run], live: [UUID: Live], trashed: Set<UUID>,
                     current: (UUID) -> Run?) -> Plan {
        var plan = Plan()
        let base = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var liveByHealthID: [UUID: UUID] = [:]
        for (id, entry) in live { if let hk = entry.healthKitUUID, liveByHealthID[hk] == nil { liveByHealthID[hk] = id } }
        var addedHealthIDs: Set<UUID> = []
        var replaced: Set<UUID> = []
        let inV2 = Set(v2.map(\.id))

        func replace(_ run: Run, as id: UUID, repaired: Bool) {
            guard !replaced.contains(id) else { return }
            replaced.insert(id)
            var copy = run
            copy.id = id
            plan.replaces.append(copy)
            if repaired { plan.counts.repaired += 1 } else { plan.counts.replaced += 1 }
        }

        for v in v2 {
            let liveEntry = live[v.id]
            if let entry = base[v.id] {
                let changed = StoredRun.normalHash(v) != entry.hash
                guard let liveEntry else {
                    // Deleted in v3: stays deleted, whether or not the older build changed it.
                    if changed { plan.counts.keptDeleted += 1 }
                    continue
                }
                if liveEntry.unavailable {
                    // v3 cannot read it; the older build's copy restores it.
                    replace(v, as: v.id, repaired: true)
                    continue
                }
                guard changed else { continue }
                guard let stored = current(v.id) else {
                    replace(v, as: v.id, repaired: true)
                    continue
                }
                if StoredRun.normalHash(stored) == entry.hash {
                    // Only the older build changed it: take its version, keeping v3's rebuilt
                    // route when the older build only dropped it with the marker.
                    var taken = v
                    if taken.route == nil, let route = stored.route, let points = v.routeWithHR,
                       route.count == points.count,
                       zip(route, points).allSatisfy({ $0.lat.bitPattern == $1.lat.bitPattern && $0.lon.bitPattern == $1.lon.bitPattern }) {
                        taken.route = route
                    }
                    replace(taken, as: v.id, repaired: false)
                } else {
                    plan.counts.conflicts += 1
                }
                continue
            }
            // Not in the baseline: added by the older build (or by a v3 build after the baseline).
            if let liveEntry {
                if liveEntry.unavailable { replace(v, as: v.id, repaired: true) }
                continue
            }
            if let hk = v.healthKitUUID, let other = liveByHealthID[hk] {
                if live[other]?.unavailable == true {
                    // The same Health workout, unreadable in v3: restore it under v3's id.
                    replace(v, as: other, repaired: true)
                } else {
                    plan.counts.deduplicated += 1
                }
                continue
            }
            if let hk = v.healthKitUUID, addedHealthIDs.contains(hk) {
                plan.counts.deduplicated += 1
                continue
            }
            if trashed.contains(v.id) {
                // The older build re-added, under the same id, a workout v3 deleted.
                plan.counts.keptDeleted += 1
                continue
            }
            if let hk = v.healthKitUUID { addedHealthIDs.insert(hk) }
            plan.adds.append(v)
            plan.counts.added += 1
        }

        var deletions: [UUID] = []
        for entry in baseline where !inV2.contains(entry.id) {
            guard let liveEntry = live[entry.id], !liveEntry.unavailable,
                  let stored = current(entry.id), StoredRun.normalHash(stored) == entry.hash else { continue }
            deletions.append(entry.id)
        }
        if deletions.count > valveLimit(baselineCount: baseline.count) {
            plan.counts.skippedByValve = deletions.count
        } else {
            plan.deletes = deletions
            plan.counts.trashed = deletions.count
        }
        return plan
    }

    /// The baseline after a merge: runs_v2.json as it is now, each entry with its normal-form
    /// hash and the position the workout has (or had) in v3.
    static func baseline(after v2: [Run], state: RunsV3BaselineV1.V2State, previous: [RunsV3BaselineV1.Entry],
                         seqs: [UUID: Int64], now: Date) -> RunsV3BaselineV1 {
        let old = Dictionary(previous.map { ($0.id, $0.seq) }, uniquingKeysWith: { first, _ in first })
        return RunsV3BaselineV1(formatVersion: 1, reconciledAt: now, v2: state,
                                entries: v2.map { .init(id: $0.id, hash: StoredRun.normalHash($0), seq: seqs[$0.id] ?? old[$0.id] ?? 0) })
    }

    /// Whether runs_v2.json's stamp is the one the baseline recorded, at the files' precision
    /// (whole seconds). A different stamp is only a hint: the content decides.
    static func stampMatches(_ state: RunsV3BaselineV1.V2State, size: Int, fileNumber: Int, modified: Date) -> Bool {
        guard state.present, let recordedSize = state.size, let number = state.fileNumber, let recorded = state.modified else { return false }
        return recordedSize == size && number == fileNumber
            && recorded.timeIntervalSince1970.rounded(.down) == modified.timeIntervalSince1970.rounded(.down)
    }
}
