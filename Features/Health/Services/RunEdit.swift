//
//  RunEdit.swift
//  WRKT
//
//  A change to one stored workout, by id: an edit of its light fields plus optional
//  replacements of its detail arrays. Writers describe what they learned instead of handing
//  back a whole run they read earlier, so a change that landed in between is kept, and a later
//  store can apply the same edit to a workout it reads from disk.
//

import Foundation

struct RunEdit {
    let id: UUID
    /// Applied to the workout's summary; its light fields are copied back to the run. Must be
    /// pure: it reads and writes only the fields it is given and gives the same result each time.
    var light: (inout RunSummary) -> Void
    /// nil keeps the stored array; a value, empty included, replaces it.
    var route: [Coordinate]??
    var routeWithHR: [RoutePoint]??
    var splits: [KilometerSplit]??
    var hrSamples: [HeartRateSample]??

    init(id: UUID,
         light: @escaping (inout RunSummary) -> Void = { _ in },
         route: [Coordinate]?? = nil,
         routeWithHR: [RoutePoint]?? = nil,
         splits: [KilometerSplit]?? = nil,
         hrSamples: [HeartRateSample]?? = nil) {
        self.id = id
        self.light = light
        self.route = route
        self.routeWithHR = routeWithHR
        self.splits = splits
        self.hrSamples = hrSamples
    }

    /// `run` with this edit applied.
    func applied(to run: Run) -> Run {
        var summary = RunSummary(run)
        light(&summary)
        var updated = run
        updated.applyLightFields(of: summary)
        if let route { updated.route = route }
        if let routeWithHR { updated.routeWithHR = routeWithHR }
        if let splits { updated.splits = splits }
        if let hrSamples { updated.hrSamples = hrSamples }
        return updated
    }
}

extension Run {
    /// Copies every light field of `summary` onto this run; the arrays are left as they are.
    mutating func applyLightFields(of summary: RunSummary) {
        date = summary.date
        distanceKm = summary.distanceKm
        durationSec = summary.durationSec
        notes = summary.notes
        healthKitUUID = summary.healthKitUUID
        avgHeartRate = summary.avgHeartRate
        calories = summary.calories
        workoutType = summary.workoutType
        workoutName = summary.workoutName
        maxHeartRate = summary.maxHeartRate
        minHeartRate = summary.minHeartRate
        avgRunningPower = summary.avgRunningPower
        avgCadence = summary.avgCadence
        avgStrideLength = summary.avgStrideLength
        avgGroundContactTime = summary.avgGroundContactTime
        avgVerticalOscillation = summary.avgVerticalOscillation
    }
}

extension RunEdit {
    /// What a detailed HealthKit read teaches about one workout. The totals, type and name are
    /// taken as read; heart rate and running dynamics only when read; splits whenever read;
    /// samples and routes only when not empty, with the plain route rebuilt from the route with
    /// heart rate when that is present.
    static func enrichment(_ enrichment: HealthKitManager.DetailedRunEnrichment, id: UUID) -> RunEdit {
        let e = enrichment
        let route: [Coordinate]??
        if let routeWithHR = e.routeWithHR, !routeWithHR.isEmpty {
            route = .some(routeWithHR.map { Coordinate(lat: $0.lat, lon: $0.lon) })
        } else if let plain = e.route, !plain.isEmpty {
            route = .some(plain)
        } else {
            route = nil
        }
        return RunEdit(
            id: id,
            light: { run in
                run.distanceKm = e.distanceKm
                run.durationSec = e.durationSec
                run.calories = e.calories
                run.workoutType = e.workoutType
                run.workoutName = e.workoutName
                if let value = e.avgHeartRate { run.avgHeartRate = value }
                if let value = e.maxHeartRate { run.maxHeartRate = value }
                if let value = e.minHeartRate { run.minHeartRate = value }
                if let value = e.avgRunningPower { run.avgRunningPower = value }
                if let value = e.avgCadence { run.avgCadence = value }
                if let value = e.avgStrideLength { run.avgStrideLength = value }
                if let value = e.avgGroundContactTime { run.avgGroundContactTime = value }
                if let value = e.avgVerticalOscillation { run.avgVerticalOscillation = value }
            },
            route: route,
            routeWithHR: e.routeWithHR.flatMap { $0.isEmpty ? nil : .some($0) },
            splits: e.splits.map { .some($0) },
            hrSamples: e.hrSamples.flatMap { $0.isEmpty ? nil : .some($0) }
        )
    }
}
