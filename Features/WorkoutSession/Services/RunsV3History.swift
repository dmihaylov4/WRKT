//
//  RunsV3History.swift
//  WRKT
//
//  The per-workout run history (runs_v3) as WorkoutStoreV2 holds it: summaries in the store,
//  a few full runs in memory, and changes queued per workout until a drain makes them durable.
//  Used only when the storage found an active runs_v3 directory (WorkoutStorage.openRunHistory);
//  otherwise the store keeps today's whole history in memory and one file.
//  Specification: docs/run-storage-v3-format-spec.md, sections 3.4, 3.5, 3.7, 4 and 5.1.
//

import Foundation

/// The store-side state of the per-workout history. Main actor; every file operation goes to
/// the storage actor. Not thread safe beyond that.
@MainActor
final class RunsV3History {
    /// One queued change to one workout, in the order the store made it.
    enum Change {
        case add(Run, seq: Int64)
        /// The whole run of a workout that exists (a change carried over by the migration).
        case replace(Run)
        case edit(RunEdit)
        case delete
    }

    let mode: RunsV3Mode
    private let storage: WorkoutStorage
    private(set) var nextSeq: Int64

    /// Full runs held in memory, each equal to its file with the pending changes applied. Kept:
    /// every run a live detail handle shows, plus the most recently loaded few.
    private var cache: [UUID: Run] = [:]
    private var recent: [UUID] = []
    static let recentLimit = 3
    /// Whether a live handle shows this id (its run stays cached).
    var isObserved: (UUID) -> Bool = { _ in false }

    /// Changes not yet durable, per workout, with a serial each.
    private var pending: [UUID: [(serial: Int, change: Change)]] = [:]
    private var serial = 0
    /// Written by a drain whose barrier failed: durable only after a later barrier.
    private var owedBarrier: Set<UUID> = []
    private var indexWrite: Task<Void, Never>?
    /// How long a burst of drains may leave the index stale before it is written once.
    var indexDelay: Duration = .seconds(2)

    init(storage: WorkoutStorage, opened: WorkoutStorage.RunsV3Opened) {
        self.storage = storage
        self.mode = opened.mode
        self.nextSeq = opened.nextSeq
    }

    var isWritable: Bool { mode == .writable }
    var hasPendingChanges: Bool { !pending.isEmpty || !owedBarrier.isEmpty }

    // MARK: - Memory

    func cachedRun(_ id: UUID) -> Run? { cache[id] }

    /// Holds `run` as the current full record of its workout.
    func remember(_ run: Run) {
        cache[run.id] = run
        recent.removeAll { $0 == run.id }
        recent.append(run.id)
        trim()
    }

    func forget(_ id: UUID) {
        cache[id] = nil
        recent.removeAll { $0 == id }
    }

    /// Drops what no handle shows beyond the most recent few; on a memory warning, all of it.
    func trim(keepRecent: Int = 3) {
        let keep = Set(recent.suffix(keepRecent))
        for id in Array(cache.keys) where !keep.contains(id) && !isObserved(id) { cache[id] = nil }
        recent = recent.filter { cache[$0] != nil }
    }

    var cachedCount: Int { cache.count }

    // MARK: - Changes

    /// Bumped by every change queued for this id, never reset: tells whether the workout
    /// changed between two moments.
    func serial(of id: UUID) -> Int { lastSerial[id] ?? 0 }
    private var lastSerial: [UUID: Int] = [:]

    /// Queues a change; the cached run, if any, follows it at once.
    func enqueue(_ change: Change, for id: UUID) {
        serial += 1
        lastSerial[id] = serial
        pending[id, default: []].append((serial, change))
        switch change {
        case .add(let run, let seq):
            nextSeq = max(nextSeq, seq + 1)
            remember(run)
        case .replace(let run):
            remember(run)
        case .edit(let edit):
            if let run = cache[id] { cache[id] = edit.applied(to: run) }
        case .delete:
            forget(id)
        }
    }

    func takeSeq() -> Int64 {
        defer { nextSeq += 1 }
        return nextSeq
    }

    private static func apply(_ changes: [Change], to base: Run?) -> Run? {
        var state = base
        for change in changes {
            switch change {
            case .add(let run, _), .replace(let run): state = run
            case .edit(let edit): state = state.map(edit.applied(to:))
            case .delete: state = nil
            }
        }
        return state
    }

    // MARK: - Reads

    /// One workout's full record, as the store shows it: the file with the pending changes
    /// applied. Must run inside the store's save queue, so no drain runs meanwhile.
    func read(_ id: UUID) async -> RunsV3ReadResult {
        if let cached = cache[id] { return .loaded(cached) }
        let disk = await storage.runsV3Read(id: id)
        // Changes made while the file was read are pending too: none was drained meanwhile.
        let changes = (pending[id] ?? []).map(\.change)
        switch disk {
        case .loaded(let run):
            guard let current = Self.apply(changes, to: run) else { return .removed }
            remember(current)
            return .loaded(current)
        case .removed:
            if let current = Self.apply(changes, to: nil) {
                remember(current)
                return .loaded(current)
            }
            return .removed
        case .unreadable, .temporarilyUnavailable:
            // Added since, or deleted since, decides without the file.
            if changes.contains(where: { if case .edit = $0 { return false }; return true }),
               let current = Self.apply(changes, to: nil) {
                remember(current)
                return .loaded(current)
            }
            return disk
        }
    }

    // MARK: - Drain

    struct DrainReport {
        var durable: Set<UUID> = []
        var failed: [UUID: Error] = [:]
        var dropped: [UUID: String] = [:]
        var awaitingBarrier: Set<UUID> = []
        var barrierError: Error?
        /// Stored summaries of ids with nothing pending any more, to check against memory.
        var settled: [UUID: RunSummary] = [:]
        var removedFromDisk: Set<UUID> = []
        var isFullyDurable: Bool { failed.isEmpty && awaitingBarrier.isEmpty && barrierError == nil }
    }

    /// Sends every pending change to the storage actor as one batch and records the outcome.
    /// Must run inside the store's save queue.
    func drain() async -> DrainReport {
        var report = DrainReport()
        guard isWritable else {
            for id in pending.keys { report.failed[id] = StorageError.runHistoryReadOnly }
            return report
        }
        // Taken in one main-actor turn, with the cache that reflects exactly these changes.
        let snapshot = pending.mapValues { $0 }
        let cachedTargets = snapshot.keys.reduce(into: [UUID: Run]()) { $0[$1] = cache[$1] }
        let needBase = snapshot.compactMap { id, items -> UUID? in
            guard cachedTargets[id] == nil else { return nil }
            // A base is needed only when an edit comes before any add.
            for item in items {
                switch item.change {
                case .add, .replace: return nil
                case .edit: return id
                case .delete: continue
                }
            }
            return nil
        }
        let bases = needBase.isEmpty ? [:] : await storage.runsV3Read(ids: needBase)

        var batch: [(id: UUID, operations: [RunsV3Operation])] = []
        var batchSerial: [UUID: Int] = [:]
        for (id, items) in snapshot {
            batchSerial[id] = items.last?.serial ?? 0
            let changes = items.map(\.change)
            let addSeq = changes.reduce(nil as Int64?) { last, change in
                if case .add(_, let seq) = change { return seq }
                if case .delete = change { return nil }
                return last
            }
            let hasDelete = changes.contains { if case .delete = $0 { return true }; return false }
            let target: Run?
            if let cached = cachedTargets[id] {
                target = cached
            } else if needBase.contains(id) {
                switch bases[id] {
                case .loaded(let run)?:
                    target = Self.apply(changes, to: run)
                case .temporarilyUnavailable?:
                    report.failed[id] = StorageError.runHistoryDeferred
                    continue
                default:
                    // The stored workout cannot be read: its edits cannot be applied (permanent).
                    if hasDelete {
                        batch.append((id, [.delete]))
                    } else if let addIndex = changes.lastIndex(where: { if case .add = $0 { return true }; return false }) {
                        if let added = Self.apply(Array(changes[addIndex...]), to: nil), let addSeq {
                            batch.append((id, [.delete, .add(added, seq: addSeq)]))
                        }
                    } else {
                        report.dropped[id] = "stored workout cannot be read"
                    }
                    continue
                }
            } else {
                target = Self.apply(changes, to: nil)
            }
            if let target {
                if let addSeq {
                    batch.append((id, [.delete, .add(target, seq: addSeq)]))
                } else {
                    batch.append((id, [.replace(target)]))
                }
            } else {
                batch.append((id, [.delete]))
            }
        }
        // Dropped edits are settled now: nothing will ever apply them.
        for id in report.dropped.keys { settle(id, upTo: batchSerial[id] ?? 0) }

        let outcome = await storage.runsV3Drain(batch)
        let result = outcome.result
        report.barrierError = result.barrierError
        report.failed.merge(result.failed) { first, _ in first }
        for (id, reason) in result.dropped { report.dropped[id] = reason; settle(id, upTo: batchSerial[id] ?? 0) }
        for id in result.awaitingBarrier {
            owedBarrier.insert(id)
            settle(id, upTo: batchSerial[id] ?? 0)
        }
        for id in result.durable {
            owedBarrier.remove(id)
            if let upTo = batchSerial[id] { settle(id, upTo: upTo) }
            if pending[id] == nil {
                if let summary = outcome.summaries[id] { report.settled[id] = summary } else { report.removedFromDisk.insert(id) }
            }
        }
        report.durable = result.durable
        report.awaitingBarrier = owedBarrier
        scheduleIndexWrite()
        return report
    }

    private func settle(_ id: UUID, upTo serial: Int) {
        guard var items = pending[id] else { return }
        items.removeAll { $0.serial <= serial }
        pending[id] = items.isEmpty ? nil : items
    }

    /// Writes the index once after a burst of drains (spec: coalesced; it is only a cache).
    private func scheduleIndexWrite() {
        indexWrite?.cancel()
        let delay = indexDelay
        indexWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.writeIndexNow()
        }
    }

    /// Hook for the store: runs `writeIndex` inside its save queue.
    var enqueueIndexWrite: (@escaping @MainActor (WorkoutStorage) async throws -> Void) -> Void = { _ in }

    func writeIndexNow() async {
        enqueueIndexWrite { storage in
            do {
                try await storage.runsV3WriteIndexIfStale()
            } catch {
                AppLogger.warning("runs_v3 index write failed; it is rebuilt from the files: \(error)", category: AppLogger.storage)
            }
        }
    }
}
