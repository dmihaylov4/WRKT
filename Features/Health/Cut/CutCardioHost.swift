//
//  CutCardioHost.swift
//  WRKT
//
//  Feeds the Cut Cardio views from what the legacy screens already read: WorkoutStoreV2's runs
//  and HealthKitManager's connection and sync state. Same syncs, refresh, Health permission
//  sheet, auto prompt, delete, share and detail fetches as CardioView and CardioDetailView;
//  only the presentation differs. No new HealthKit queries.
//

import SwiftUI
import MapKit

// MARK: - Tab

struct CutCardioHost: View {
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var healthKit: HealthKitManager

    @State private var showingAuthSheet = false
    @State private var isResyncing = false
    @State private var selectedType: CardioType = .running
    @State private var weekOffset = 0
    @State private var openedRun: Run?

    // Same flag as the legacy tab: one automatic prompt until Health is connected.
    @AppStorage("hasPromptedForHealthKitAuth") private var hasPromptedThisSession = false

    private var typedRuns: [Run] { CutCardioLogic.runs(store.validRuns, type: selectedType) }

    private var model: CutCardioTabModel {
        let loaded = store.isStorageLoaded || store.storageLoadError != nil || !store.runs.isEmpty
        return CutCardioLogic.tab(
            allRuns: loaded ? store.validRuns : nil,
            type: selectedType,
            weekOffset: weekOffset,
            connection: healthKit.connectionState,
            isSyncing: healthKit.isSyncing || isResyncing,
            syncProcessed: healthKit.syncProcessedCount,
            syncTotal: healthKit.syncTotalCount,
            now: .now
        )
    }

    var body: some View {
        CutCardioView(model: model, actions: actions)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedRun) { run in
                CardioDetailView(run: run)
            }
            .sheet(isPresented: $showingAuthSheet, onDismiss: {
                if healthKit.connectionState == .connected {
                    Task {
                        await healthKit.syncWorkoutsIncremental()
                        store.matchAllWorkoutsWithHealthKit()
                    }
                }
            }) {
                HealthAuthSheet()
                    .environmentObject(healthKit)
            }
            .task {
                clampWeek()
                if healthKit.connectionState == .connected {
                    hasPromptedThisSession = false
                } else if healthKit.connectionState == .disconnected && !hasPromptedThisSession {
                    try? await Task.sleep(for: .milliseconds(500))
                    if healthKit.connectionState == .disconnected {
                        hasPromptedThisSession = true
                        showingAuthSheet = true
                    }
                }
                if healthKit.connectionState == .connected {
                    await healthKit.syncWorkoutsIncremental()
                    store.matchAllWorkoutsWithHealthKit()
                }
            }
            .onChange(of: selectedType) { _, _ in clampWeek() }
            .onChange(of: typedRuns.count) { _, _ in clampWeek() }
    }

    private var actions: CutCardioActions {
        CutCardioActions(
            selectType: { selectedType = $0 },
            olderWeek: { changeWeek(by: 1) },
            newerWeek: { changeWeek(by: -1) },
            syncNew: { Task { await healthKit.syncWorkoutsIncremental() } },
            fullResync: {
                isResyncing = true
                Task {
                    await healthKit.forceFullResync()
                    store.matchAllWorkoutsWithHealthKit()
                    isResyncing = false
                }
            },
            connectHealth: { showingAuthSheet = true },
            refresh: {
                await healthKit.syncRecentWorkouts()
                store.matchAllWorkoutsWithHealthKit()
            },
            openRun: { id in
                Haptics.light()
                openedRun = store.validRuns.first { $0.id == id }
            }
        )
    }

    private func clampWeek() {
        weekOffset = CutCardioLogic.clampedOffset(weekOffset, runs: typedRuns, now: .now, calendar: .current)
    }

    private func changeWeek(by delta: Int) {
        let next = CutCardioLogic.clampedOffset(weekOffset + delta, runs: typedRuns, now: .now, calendar: .current)
        guard next != weekOffset else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { weekOffset = next }
    }
}

// MARK: - Detail

/// CardioDetailView's data and flows behind the Cut detail. Reads the latest copy of the run
/// from the store, as the legacy view does, so fetched routes and splits appear in place.
struct CutCardioDetailHost: View {
    let run: Run

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss

    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var mapSnapshotImage: UIImage?
    @State private var isGeneratingSnapshot = false
    @State private var localRouteWithHR: [RoutePoint]?
    @State private var localRoute: [Coordinate]?
    @State private var isRefreshing = false

    private var latestRun: Run {
        store.runs.first { $0.id == run.id } ?? run
    }

    /// The latest run with any route fetched on this screen laid over it.
    private var displayRun: Run {
        var current = latestRun
        if let localRouteWithHR { current.routeWithHR = localRouteWithHR }
        if let localRoute { current.route = localRoute }
        return current
    }

    private var hrSamples: [HeartRateSample]? {
        let current = displayRun
        let routeSamples = current.routeWithHR?.compactMap { point -> HeartRateSample? in
            guard let hr = point.hr else { return nil }
            return HeartRateSample(timestamp: point.t, bpm: hr)
        }
        if let routeSamples, !routeSamples.isEmpty { return routeSamples }
        return current.hrSamples
    }

    private var model: CutCardioDetailModel {
        let current = displayRun
        return CutCardioLogic.detail(current,
                                     zones: CardioDataExtractor.shared.calculateHRZones(from: current) ?? [],
                                     hrSamples: hrSamples, now: .now)
    }

    var body: some View {
        let model = model
        CutCardioDetailView(model: model, isRefreshing: isRefreshing, actions: CutCardioDetailActions(
            fetchRoute: { Task { await refresh() } },
            refreshDetails: { Task { await refresh() } }
        )) {
            routeMap
        }
        .workoutDetailScrollEdge()
        // The hero carries the name; the bar keeps only back and the menu.
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share workout", systemImage: "square.and.arrow.up") {
                        Haptics.light()
                        Task { await generateMapSnapshotAndShare() }
                    }
                    if latestRun.healthKitUUID != nil {
                        Button(model.route == .map ? "Refresh route and details" : "Get route and details",
                               systemImage: "arrow.clockwise") {
                            Task { await refresh() }
                        }
                        .disabled(isRefreshing)
                    }
                    Button("Delete workout", systemImage: "trash", role: .destructive) {
                        Haptics.light()
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmationDialog(model.deleteTitle, isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                Task {
                    do {
                        try await HealthKitManager.shared.deleteCardioWorkout(run: latestRun)
                        dismiss()
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed from VOLIA and from Apple Health.")
        }
        .alert("Delete failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(isPresented: $showingShareSheet) {
            PostCreationView(workout: enrichedWorkout(), mapImage: mapSnapshotImage)
        }
        .overlay {
            if isGeneratingSnapshot {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    HStack(spacing: 12) {
                        ProgressView().tint(DS.Cut.Colors.textPrimary)
                        Text("Preparing map")
                            .cutFont(.title)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { _ in dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: .cardioTabReselected)) { _ in dismiss() }
    }

    @ViewBuilder
    private var routeMap: some View {
        let current = displayRun
        if let points = current.routeWithHR, points.count > 1 {
            InteractiveRouteMapHeat(points: points)
        } else if let route = current.route, route.count > 1 {
            InteractiveRouteMapHeat(coords: route, hrPerPoint: nil)
        }
    }

    /// The legacy Get Route, Load Splits and Load Details: one detailed refresh from Health.
    private func refresh() async {
        guard !isRefreshing, latestRun.healthKitUUID != nil else { return }
        isRefreshing = true
        if let updated = await HealthKitManager.shared.refreshDetailedDataForRun(runId: latestRun.id) {
            localRouteWithHR = updated.routeWithHR
            localRoute = updated.route
        }
        isRefreshing = false
    }

    // MARK: Share (CardioDetailView's flow)

    private func enrichedWorkout() -> CompletedWorkout {
        let current = latestRun
        var workout = current.toCompletedWorkout()
        CardioDataExtractor.shared.enrichWorkout(&workout, from: current)
        if let routeWithHR = current.routeWithHR, !routeWithHR.isEmpty {
            workout.matchedHealthKitHeartRateSamples = routeWithHR.compactMap { point in
                guard let hr = point.hr else { return nil }
                return HeartRateSample(timestamp: point.t, bpm: hr)
            }
        }
        return workout
    }

    private func generateMapSnapshotAndShare() async {
        mapSnapshotImage = nil
        var current = latestRun
        isGeneratingSnapshot = true

        let hasUsableRoute = (current.routeWithHR?.count ?? 0) > 1 || (current.route?.count ?? 0) > 1
        if !hasUsableRoute, current.healthKitUUID != nil,
           let refreshed = await HealthKitManager.shared.refreshDetailedDataForRun(runId: current.id) {
            current = refreshed
        }

        let coordinates: [CLLocationCoordinate2D]
        let hrValues: [Double]?
        if let routeWithHR = current.routeWithHR, routeWithHR.count > 1 {
            coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = routeWithHR.map { $0.hr ?? .nan }
        } else if let route = current.route, route.count > 1 {
            coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = nil
        } else {
            isGeneratingSnapshot = false
            showingShareSheet = true
            return
        }

        mapSnapshotImage = try? await MapSnapshotService.shared.generateRouteSnapshot(
            coordinates: coordinates,
            hrValues: hrValues,
            size: CGSize(width: 600, height: 400)
        )
        isGeneratingSnapshot = false
        showingShareSheet = true
    }
}
