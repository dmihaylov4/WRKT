//
//  CutLiveOverviewModel.swift
//  WRKT
//
//  Cut live workout overview: the plain values it shows and the logic that picks them.
//  The exercise states, the current exercise and the superset grouping follow
//  LiveWorkoutOverlayCard's rules exactly; only the layout differs.
//

import Foundation

/// Where a slanted segment stands.
enum CutSegmentState: Equatable, Sendable {
    case done, current, toDo
}

/// One exercise row in the overview.
struct CutLiveRow: Equatable, Identifiable {
    enum State: Equatable { case finished, inProgress, upNext }

    let id: UUID
    let name: String
    let line: String
    let state: State
    let isInSuperset: Bool
}

struct CutLiveSection: Equatable, Identifiable {
    let title: String
    let rows: [CutLiveRow]
    var id: String { title }
}

/// Everything the Cut overview shows.
struct CutLiveOverviewModel: Equatable {
    var title: String
    var startDate: Date
    /// "7 sets, 4,260 kg so far".
    var summaryLine: String
    var segments: [CutSegmentState]
    /// The current exercise, the big row.
    var now: CutLiveRow?
    /// The rest of the current exercise's superset, shown under it.
    var nowPartners: [CutLiveRow]
    var allDone: Bool
    var sections: [CutLiveSection]
    /// The legacy rule: every exercise finished (or removed) before the workout can finish.
    var canFinish: Bool
}

enum CutLiveOverviewLogic {
    static func state(_ entry: WorkoutEntry) -> CutLiveRow.State {
        guard !entry.sets.isEmpty else { return .upNext }
        let done = entry.sets.filter(\.isCompleted).count
        if done == 0 { return .upNext }
        return done == entry.sets.count ? .finished : .inProgress
    }

    /// LiveWorkoutOverlayCard.heroEntry.
    static func heroEntry(entries: [WorkoutEntry], activeEntryID: UUID?) -> WorkoutEntry? {
        if let activeEntryID, let entry = entries.first(where: { $0.id == activeEntryID }), state(entry) != .finished {
            return entry
        }
        if let entry = entries.first(where: { state($0) == .inProgress }) { return entry }
        return entries.first(where: { state($0) == .upNext })
    }

    /// LiveWorkoutOverlayCard.groupedEntries: supersets together in their order, others alone.
    static func groups(_ entries: [WorkoutEntry]) -> [[WorkoutEntry]] {
        var groups: [[WorkoutEntry]] = []
        var seen: Set<UUID> = []
        for entry in entries where !seen.contains(entry.id) {
            if let group = entry.supersetGroupID {
                let members = entries.filter { $0.supersetGroupID == group }
                    .sorted { ($0.orderInSuperset ?? 0) < ($1.orderInSuperset ?? 0) }
                members.forEach { seen.insert($0.id) }
                groups.append(members)
            } else {
                seen.insert(entry.id)
                groups.append([entry])
            }
        }
        return groups
    }

    /// LiveWorkoutOverlayCard.groupState: finished when all are, in progress when any started.
    static func groupState(_ group: [WorkoutEntry]) -> CutLiveRow.State {
        let states = group.map(state)
        if states.allSatisfy({ $0 == .finished }) { return .finished }
        if states.contains(where: { $0 != .upNext }) { return .inProgress }
        return .upNext
    }

    static func model(
        title: String,
        startDate: Date,
        entries: [WorkoutEntry],
        activeEntryID: UUID?,
        unit: WeightUnit
    ) -> CutLiveOverviewModel {
        let hero = heroEntry(entries: entries, activeEntryID: activeEntryID)
        let allGroups = groups(entries)
        let heroGroup = hero.flatMap { hero in allGroups.first(where: { $0.contains(where: { $0.id == hero.id }) }) }
        let others = allGroups.filter { group in !group.contains(where: { $0.id == hero?.id }) }

        func rows(_ state: CutLiveRow.State) -> [CutLiveRow] {
            others.filter { groupState($0) == state }.flatMap { $0 }.map { row($0, unit: unit) }
        }
        var sections: [CutLiveSection] = []
        for (title, state) in [("In progress", CutLiveRow.State.inProgress), ("Up next", .upNext), ("Completed", .finished)] {
            let list = rows(state)
            if !list.isEmpty { sections.append(CutLiveSection(title: title, rows: list)) }
        }

        let allDone = !entries.isEmpty && entries.allSatisfy { state($0) == .finished }
        return CutLiveOverviewModel(
            title: title,
            startDate: startDate,
            summaryLine: summaryLine(entries: entries, unit: unit),
            segments: entries.map { entry in
                if state(entry) == .finished { return .done }
                return entry.id == hero?.id ? .current : .toDo
            },
            now: hero.map { heroRow($0) },
            nowPartners: (heroGroup ?? []).filter { $0.id != hero?.id }.map { row($0, unit: unit) },
            allDone: allDone,
            sections: sections,
            canFinish: !entries.contains { state($0) != .finished }
        )
    }

    /// "Set 3 of 4", with the superset noted.
    static func heroRow(_ entry: WorkoutEntry) -> CutLiveRow {
        let line: String
        if entry.sets.isEmpty {
            line = "Tap to add sets"
        } else {
            let next = (entry.sets.firstIndex(where: { !$0.isCompleted }) ?? entry.sets.count - 1) + 1
            line = "Set \(next) of \(entry.sets.count)"
        }
        return CutLiveRow(id: entry.id, name: entry.exerciseName,
                          line: entry.isInSuperset ? "\(line), superset" : line,
                          state: state(entry), isInSuperset: entry.isInSuperset)
    }

    static func row(_ entry: WorkoutEntry, unit: WeightUnit) -> CutLiveRow {
        let state = state(entry)
        var line: String
        switch state {
        case _ where entry.sets.isEmpty:
            line = "No sets yet"
        case .upNext:
            let count = entry.sets.count
            line = "\(count) \(count == 1 ? "set" : "sets")"
            if let first = entry.sets.first, let value = setValue(first, unit: unit) { line += ", \(value)" }
        case .inProgress:
            line = "\(entry.sets.filter(\.isCompleted).count) of \(entry.sets.count) sets done"
        case .finished:
            line = "\(entry.sets.count) \(entry.sets.count == 1 ? "set" : "sets") done"
        }
        if entry.isInSuperset { line = "Superset, " + line.prefix(1).lowercased() + line.dropFirst() }
        return CutLiveRow(id: entry.id, name: entry.exerciseName, line: line, state: state, isInSuperset: entry.isInSuperset)
    }

    /// "32 kg x 10", "12 reps", "0:45", or nil when the set has nothing to show.
    static func setValue(_ set: SetInput, unit: WeightUnit) -> String? {
        switch set.trackingMode {
        case .timed:
            return set.durationSeconds > 0 ? CutSetLoggingLogic.clock(set.durationSeconds) : nil
        case .bodyweight:
            return set.reps > 0 ? "\(set.reps) reps" : nil
        case .weighted, .distance:
            if set.weight > 0, set.reps > 0 { return CutSetLoggingLogic.rowValue(set, mode: .weighted, unit: unit) }
            return set.reps > 0 ? "\(set.reps) reps" : nil
        }
    }

    /// "7 sets, 4,260 kg so far", or "No sets logged yet".
    static func summaryLine(entries: [WorkoutEntry], unit: WeightUnit) -> String {
        let done = entries.flatMap(\.sets).filter(\.isCompleted)
        guard !done.isEmpty else { return "No sets logged yet" }
        let sets = done.count == 1 ? "1 set" : "\(done.count) sets"
        let volumeKg = done.reduce(0.0) { $0 + max(0, $1.weight) * Double(max(0, $1.reps)) }
        guard volumeKg > 0 else { return "\(sets) so far" }
        return "\(sets), \(grouped(unit.displayValue(volumeKg)))\u{00A0}\(unit.rawValue) so far"
    }

    static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? String(format: "%.0f", value)
    }

    /// One sentence for VoiceOver on the exercise segments.
    static func segmentsAccessibilityValue(_ segments: [CutSegmentState]) -> String {
        let done = segments.filter { $0 == .done }.count
        return "\(done) of \(segments.count) exercises done"
    }
}
