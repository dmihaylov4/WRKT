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
    @State private var openedRun: RunSummary?

    // Same flag as the legacy tab: one automatic prompt until Health is connected.
    @AppStorage("hasPromptedForHealthKitAuth") private var hasPromptedThisSession = false

    private var typedRuns: [RunSummary] { CutCardioLogic.runs(store.validRunSummaries, type: selectedType) }

    private var model: CutCardioTabModel {
        let loaded = store.isStorageLoaded || store.storageLoadError != nil || !store.runSummaries.isEmpty
        return CutCardioLogic.tab(
            allRuns: loaded ? store.validRunSummaries : nil,
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
                openedRun = store.validRunSummaries.first { $0.id == id }
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

/// CardioDetailView's data and flows behind the Cut detail. Reads its one workout through the
/// store's live detail handle, so fetched routes and splits appear in place, and builds the
/// model (heart-rate zones included) again only when that workout or the zone settings change.
struct CutCardioDetailHost: View {
    let run: RunSummary

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cutSheetDepth) private var sheetDepth
    @State private var inSheet = false

    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var mapSnapshotImage: UIImage?
    @State private var isGeneratingSnapshot = false
    @State private var localRouteWithHR: [RoutePoint]?
    @State private var localRoute: [Coordinate]?
    /// Bumped whenever the two local routes change, so the cached model is rebuilt.
    @State private var localRouteRevision = 0
    @State private var isRefreshing = false
    @State private var holder = RunDetailHolder()
    @State private var modelCache: CutCardioDetailModelCache

    /// `modelCache` is for tests that count model builds.
    init(run: RunSummary, modelCache: CutCardioDetailModelCache = CutCardioDetailModelCache()) {
        self.run = run
        _modelCache = State(initialValue: modelCache)
    }

    private var detail: RunDetail { holder.detail(for: run.id, in: store) }

    /// The workout's light fields: the store's summary, else the last run the screen held.
    private var currentSummary: RunSummary {
        store.runSummary(id: run.id) ?? detail.run?.summary ?? run
    }

    /// The workout's full record with any route fetched on this screen laid over it.
    private var displayRun: Run? {
        guard var current = detail.run else { return nil }
        if let localRouteWithHR { current.routeWithHR = localRouteWithHR }
        if let localRoute { current.route = localRoute }
        return current
    }

    private static func hrSamples(_ current: Run) -> [HeartRateSample]? {
        let routeSamples = current.routeWithHR?.compactMap { point -> HeartRateSample? in
            guard let hr = point.hr else { return nil }
            return HeartRateSample(timestamp: point.t, bpm: hr)
        }
        if let routeSamples, !routeSamples.isEmpty { return routeSamples }
        return current.hrSamples
    }

    private var model: CutCardioDetailModel {
        let detail = self.detail
        let now = Date.now
        let key = CutCardioDetailModelCache.Key(
            handle: ObjectIdentifier(detail), revision: detail.revision, localRouteRevision: localRouteRevision,
            year: Calendar.current.component(.year, from: now), zones: HRZoneCalculator.shared.config,
            summary: detail.run == nil ? currentSummary : nil)
        return modelCache.model(for: key) {
            if let current = displayRun {
                return CutCardioLogic.detail(current,
                                             zones: CardioDataExtractor.shared.calculateHRZones(from: current) ?? [],
                                             hrSamples: Self.hrSamples(current), now: now)
            }
            return CutCardioLogic.detail(summary: currentSummary, run: nil, isLoading: detail.isLoading,
                                         zones: [], hrSamples: nil, now: now)
        }
    }

    var body: some View {
        let model = model
        CutCardioDetailView(model: model, isRefreshing: isRefreshing, actions: CutCardioDetailActions(
            fetchRoute: { Task { await refresh() } },
            refreshDetails: { Task { await refresh() } }
        ), inSheet: inSheet, close: { dismiss() }, tools: AnyView(workoutMenu(model)
            .labelStyle(.iconOnly).menuStyle(.button)
            .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: DS.Cut.Metrics.minTouchTarget)))) {
            routeMap
        }
        .background(CutPresentationReader { inSheet = $0 })
        .workoutDetailScrollEdge()
        // The hero carries the name; the bar keeps only back and the menu.
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !inSheet {
                ToolbarItem(placement: .topBarTrailing) { workoutMenu(model) }
            }
        }
        .sheet(isPresented: $showingDeleteConfirmation) {
            CutSheetConfirm("Delete workout?", message: "\(model.deleteTitle)\n\nIt is removed from VOLIA and from Apple Health.",
                primaryTitle: "Delete workout", cancelTitle: "Keep workout", confirm: {
                    showingDeleteConfirmation = false
                    Task {
                        do {
                            try await HealthKitManager.shared.deleteCardioWorkout(run: currentSummary)
                            dismiss()
                        } catch {
                            deleteError = error.localizedDescription
                        }
                    }
            }, cancel: { showingDeleteConfirmation = false })
                .environment(\.cutSheetDepth, sheetDepth + (inSheet ? 1 : 0))
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
                .environment(\.cutSheetDepth, sheetDepth + (inSheet ? 1 : 0))
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
        if let points = current?.routeWithHR, points.count > 1 {
            InteractiveRouteMapHeat(points: points)
        } else if let route = current?.route, route.count > 1 {
            InteractiveRouteMapHeat(coords: route, hrPerPoint: nil)
        }
    }

    private func workoutMenu(_ model: CutCardioDetailModel) -> some View {
        Menu {
            Button("Share workout", systemImage: "square.and.arrow.up") {
                Haptics.light()
                Task { await generateMapSnapshotAndShare() }
            }
            if currentSummary.healthKitUUID != nil {
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

    /// The legacy Get Route, Load Splits and Load Details: one detailed refresh from Health.
    private func refresh() async {
        guard !isRefreshing, currentSummary.healthKitUUID != nil else { return }
        isRefreshing = true
        if let updated = await HealthKitManager.shared.refreshDetailedDataForRun(runId: run.id) {
            localRouteWithHR = updated.routeWithHR
            localRoute = updated.route
            localRouteRevision &+= 1
        }
        isRefreshing = false
    }

    // MARK: Share (CardioDetailView's flow)

    private func enrichedWorkout() -> CompletedWorkout {
        // The full record is here from the first frame; without it, the workout as listed.
        detail.run?.sharedWorkout() ?? currentSummary.completedWorkoutWithoutSamples()
    }

    private func generateMapSnapshotAndShare() async {
        mapSnapshotImage = nil
        var current = detail.run
        isGeneratingSnapshot = true

        let hasUsableRoute = (current?.routeWithHR?.count ?? 0) > 1 || (current?.route?.count ?? 0) > 1
        if !hasUsableRoute, currentSummary.healthKitUUID != nil,
           let refreshed = await HealthKitManager.shared.refreshDetailedDataForRun(runId: run.id) {
            current = refreshed
        }

        let coordinates: [CLLocationCoordinate2D]
        let hrValues: [Double]?
        if let routeWithHR = current?.routeWithHR, routeWithHR.count > 1 {
            coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = routeWithHR.map { $0.hr ?? .nan }
        } else if let route = current?.route, route.count > 1 {
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

/// The Cut detail model for the last inputs it was built from. A plain class kept in `@State`:
/// reading or filling it never triggers a render.
@MainActor
final class CutCardioDetailModelCache {
    struct Key: Equatable {
        /// The handle and its revision: the workout's full record as last set.
        var handle: ObjectIdentifier
        var revision: Int
        var localRouteRevision: Int
        /// The date line names the year only for other years.
        var year: Int
        var zones: HRZoneConfig?
        /// Only while the full record is not here: then the model is built from the summary.
        var summary: RunSummary?
    }

    private(set) var builds = 0
    private var key: Key?
    private var model: CutCardioDetailModel?

    nonisolated init() {}

    func model(for key: Key, build: () -> CutCardioDetailModel) -> CutCardioDetailModel {
        if let model, self.key == key { return model }
        let built = build()
        builds += 1
        self.key = key
        model = built
        return built
    }
}
