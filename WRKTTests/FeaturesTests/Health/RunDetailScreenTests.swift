import Foundation
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// The detail screens show the workout's route from their first frame, keep showing a workout
/// removed while they are open, update when their workout is enriched, and the Cut screen
/// rebuilds its model (heart-rate zones included) only when its own workout changes.
@MainActor
@Suite(.serialized)
struct RunDetailScreenTests {
    private typealias F = RunDetailScreenCaptureTests

    @MainActor
    private final class Fixture {
        let directory: URL
        let defaults: UserDefaults
        let suite: String
        let store: WorkoutStoreV2
        let repository = ExerciseRepository()

        init(runs: [Run]) async throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            suite = "RunDetailScreenTests." + UUID().uuidString
            defaults = UserDefaults(suiteName: suite)!
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent(".migrated"))
            let storage = WorkoutStorage(directory: directory)
            try await storage.saveWorkouts([], prIndex: [:])
            try await storage.saveRuns(runs)
            defaults.set(true, forKey: "runs.deduplication.v1")
            store = WorkoutStoreV2(repo: repository, storage: WorkoutStorage(directory: directory), defaults: defaults)
            try await store.waitForStorage()
        }

        func remove() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Hosts `view` in a window and lays it out once, without letting the run loop turn.
    private func host<V: View>(_ view: V, _ fixture: Fixture) throws -> (UIWindow, UIHostingController<AnyView>) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(rootView: AnyView(NavigationStack { view }
            .environmentObject(fixture.store).environmentObject(fixture.repository)))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return (window, host)
    }

    private func close(_ window: UIWindow, _ fixture: Fixture) {
        window.isHidden = true
        window.rootViewController = nil
        fixture.remove()
    }

    private func mapViews(in view: UIView) -> [MKMapView] {
        (view as? MKMapView).map { [$0] } ?? view.subviews.flatMap { mapViews(in: $0) }
    }

    @Test func legacyDetailShowsTheRouteInItsFirstFrame() async throws {
        let fixture = try await Fixture(runs: [F.routeAndHeartRate, F.nothing])
        let (window, host) = try host(LegacyCardioDetailView(run: F.routeAndHeartRate.summary), fixture)
        defer { close(window, fixture) }
        #expect(mapViews(in: host.view).count == 1)
    }

    @Test func cutDetailShowsTheRouteInItsFirstFrame() async throws {
        let fixture = try await Fixture(runs: [F.routeAndHeartRate])
        let (window, host) = try host(CutCardioDetailHost(run: F.routeAndHeartRate.summary), fixture)
        defer { close(window, fixture) }
        #expect(mapViews(in: host.view).count == 1)
    }

    @Test func noRouteMeansNoMap() async throws {
        let fixture = try await Fixture(runs: [F.nothing])
        let (window, host) = try host(LegacyCardioDetailView(run: F.nothing.summary), fixture)
        defer { close(window, fixture) }
        #expect(mapViews(in: host.view).isEmpty)
    }

    /// Fetching a route while the screen is open (Get Route, Load splits, the route queue) shows
    /// it in place: the store updates the screen's handle.
    @Test func legacyDetailShowsARouteFetchedWhileOpen() async throws {
        let fixture = try await Fixture(runs: [F.nothing])
        let (window, host) = try host(LegacyCardioDetailView(run: F.nothing.summary), fixture)
        defer { close(window, fixture) }
        #expect(mapViews(in: host.view).isEmpty)

        var enriched = F.nothing
        enriched.routeWithHR = F.routeAndHeartRate.routeWithHR
        enriched.route = F.routeAndHeartRate.route
        fixture.store.editRun(.replacing(with: enriched))
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutIfNeeded()
        #expect(mapViews(in: host.view).count == 1)
    }

    @Test func aWorkoutRemovedWhileOpenStaysOnScreen() async throws {
        let fixture = try await Fixture(runs: [F.routeAndHeartRate])
        let (window, host) = try host(LegacyCardioDetailView(run: F.routeAndHeartRate.summary), fixture)
        defer { close(window, fixture) }
        fixture.store.removeRun(withId: F.routeAndHeartRate.id)
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutIfNeeded()
        #expect(mapViews(in: host.view).count == 1)
    }

    /// The Cut model, with its heart-rate zones, is built once per version of its workout: not
    /// again when the store publishes for another workout, again when its own workout changes.
    @Test func cutDetailRebuildsItsModelOnlyForItsOwnWorkout() async throws {
        let fixture = try await Fixture(runs: [F.routeAndHeartRate, F.nothing])
        let cache = CutCardioDetailModelCache()
        let (window, host) = try host(CutCardioDetailHost(run: F.routeAndHeartRate.summary, modelCache: cache), fixture)
        defer { close(window, fixture) }
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutIfNeeded()
        let initial = cache.builds
        #expect(initial >= 1)

        var other = F.nothing
        other.notes = "another workout changed"
        fixture.store.editRun(.replacing(with: other))
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutIfNeeded()
        #expect(cache.builds == initial)

        var own = F.routeAndHeartRate
        own.notes = "this workout changed"
        fixture.store.editRun(.replacing(with: own))
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutIfNeeded()
        #expect(cache.builds == initial + 1)
    }

    @Test func modelCacheBuildsOncePerKey() {
        let cache = CutCardioDetailModelCache()
        let model = CutCardioLogic.detail(F.splitsOnly, zones: [], hrSamples: nil, now: .now)
        let key = CutCardioDetailModelCache.Key(handle: ObjectIdentifier(cache), revision: 1, localRouteRevision: 0,
                                                year: 2026, zones: nil, summary: nil)
        _ = cache.model(for: key) { model }
        _ = cache.model(for: key) { model }
        #expect(cache.builds == 1)
        var next = key
        next.localRouteRevision = 1
        _ = cache.model(for: next) { model }
        #expect(cache.builds == 2)
    }

    // MARK: Detail model without the full record

    /// With the full record, the summary-based detail equals today's run-based one.
    @Test func detailFromSummaryAndRunEqualsTheRunDetail() {
        for run in [F.routeAndHeartRate, F.splitsOnly, F.nothing, F.strength] {
            let zones = CardioDataExtractor.shared.calculateHRZones(from: run) ?? []
            let viaRun = CutCardioLogic.detail(run, zones: zones, hrSamples: run.hrSamples, now: F.date)
            let viaSummary = CutCardioLogic.detail(summary: run.summary, run: run, zones: zones,
                                                   hrSamples: run.hrSamples, now: F.date)
            #expect(viaRun == viaSummary)
            #expect(viaRun.availability == .ready)
        }
    }

    @Test func loadingKeepsTheRouteAndSplitPlaces() {
        let run = F.routeAndHeartRate
        let model = CutCardioLogic.detail(summary: run.summary, run: nil, isLoading: true, zones: [], hrSamples: nil, now: F.date)
        let full = CutCardioLogic.detail(run, zones: [], hrSamples: nil, now: F.date)
        #expect(model.availability == .loading)
        #expect(model.route == .map)
        #expect(model.splits.isEmpty)
        #expect(model.splitPlaceholderCount == 6)
        #expect(!model.canLoadSplits && !model.canLoadDetails)
        #expect(model.hero == full.hero && model.stats == full.stats && model.title == full.title)
        #expect(model.heartRate?.stats == full.heartRate?.stats)
        #expect(model.heartRate?.bars.isEmpty == true)
    }

    @Test func unavailableSaysSoAndLeavesOutDetail() {
        let run = F.routeAndHeartRate
        let model = CutCardioLogic.detail(summary: run.summary, run: nil, zones: [], hrSamples: nil, now: F.date)
        #expect(model.availability == .unavailable)
        #expect(model.route == .map)
        #expect(model.splitPlaceholderCount == 0)
        #expect(!model.canLoadSplits && !model.canLoadDetails)
    }
}
