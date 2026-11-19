//
//  RunDetail.swift
//  WRKT
//
//  One workout's full record (route, heart-rate samples, splits) as a detail screen sees it.
//  The store hands out one shared, observable handle per workout and updates it whenever that
//  workout changes, so a screen re-renders for its own workout only. Today the handle is
//  filled from memory at once; written so that it may later load from disk.
//

import Foundation
import Observation

/// What one workout's full record resolves to.
enum RunLoadResult {
    case loaded(Run)
    /// No workout with this id: deleted, or never existed.
    case removed
    /// The workout is listed but its data could not be read.
    case unreadable
}

/// One workout's full record, observed by a detail screen. Shared: every caller asking the
/// store for the same id while one is alive gets the same instance.
@MainActor
@Observable
final class RunDetail: Identifiable {
    enum Phase: Equatable {
        case loading
        case loaded(Run)
        case unavailable(Unavailable)
    }

    enum Unavailable: Equatable {
        case removed
        case unreadable
    }

    nonisolated let id: UUID
    private(set) var phase: Phase
    /// The last full run this handle held. Kept after the workout is removed, so a screen that
    /// is still open keeps showing what it showed.
    private(set) var lastLoaded: Run?
    /// Bumped every time the phase is set: lets a screen cache work done on one version.
    private(set) var revision = 0

    init(id: UUID, phase: Phase) {
        self.id = id
        self.phase = phase
        if case .loaded(let run) = phase { lastLoaded = run }
    }

    /// The run to show: the loaded one, or the last one after a removal. nil while loading,
    /// when unreadable, or when the workout was gone before this handle ever held it.
    var run: Run? {
        switch phase {
        case .loaded(let run): return run
        case .unavailable(.removed): return lastLoaded
        case .loading, .unavailable(.unreadable): return nil
        }
    }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    // Set by the store only.

    func setLoaded(_ run: Run) {
        phase = .loaded(run)
        lastLoaded = run
        revision &+= 1
    }

    func setUnavailable(_ reason: Unavailable) {
        phase = .unavailable(reason)
        revision &+= 1
    }
}

/// Keeps one handle for the lifetime of the view that holds it in `@State`. A plain class, so
/// taking the handle while the body runs does not itself trigger a render.
@MainActor
final class RunDetailHolder {
    private var held: RunDetail?

    func detail(for id: UUID, in store: WorkoutStoreV2) -> RunDetail {
        if let held, held.id == id { return held }
        let detail = store.runDetail(id: id)
        held = detail
        return detail
    }
}

/// A weak reference, so the store does not keep handles alive after their screens close.
@MainActor
struct WeakRunDetail {
    weak var detail: RunDetail?
}
