// CardioDetailView.swift
//
// Detailed view for a single cardio workout with map, stats, and heart rate overlay
//

import SwiftUI
import MapKit
import Charts

private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = DS.Theme.accent
}

struct CardioDetailView: View {
    let run: Run
    @EnvironmentObject private var store: WorkoutStoreV2
    @State private var hasActiveWorkoutInset = false
    @State private var selectedTab: DetailTab = .overview
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var mapSnapshotImage: UIImage?
    @State private var isGeneratingSnapshot = false
    @State private var localRouteWithHR: [RoutePoint]?
    @State private var localRoute: [Coordinate]?
    @State private var isFetchingRoute = false
    @Environment(\.dismiss) private var dismiss

    private enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case splits = "Splits"
        case heartRate = "Heart Rate"
    }

    var body: some View {
        let currentRun = latestRun

        ScrollView {
            VStack(spacing: 16) {
                // HERO CARD - Workout summary
                HeroCard(run: currentRun)

                // MAP
                mapSection

                // TABS
                Picker("View", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)

                // TAB CONTENT
                Group {
                    switch selectedTab {
                    case .overview:
                        OverviewTab(run: currentRun)
                    case .splits:
                        SplitsTab(run: currentRun)
                    case .heartRate:
                        HeartRateTab(run: currentRun)
                    }
                }

                // NOTES
                if let notes = currentRun.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .dsFont(.headline)
                        Text(notes)
                            .foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        print("🗺️ [CardioDetail] Share button tapped!")
                        Task {
                            await generateMapSnapshotAndShare()
                        }
                        Haptics.light()
                    } label: {
                        Label("Share Workout", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                        Haptics.light()
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .confirmationDialog("Delete Workout", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                Task {
                    do {
                        try await HealthKitManager.shared.deleteCardioWorkout(run: latestRun)
                        await MainActor.run {
                            dismiss()
                        }
                    } catch {
                        print("Failed to delete workout: \(error)")
                        await MainActor.run {
                            deleteError = error.localizedDescription
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this workout? This will remove it from both the app and Apple Health.")
        }
        .alert("Delete Failed", isPresented: Binding(
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
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Preparing map...")
                            .dsFont(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if hasActiveWorkoutInset { Color.clear.frame(height: 65) }
        }
        // Listen for tab changes
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { _ in
            dismiss()
        }
        // Listen for cardio tab reselection
        .onReceive(NotificationCenter.default.publisher(for: .cardioTabReselected)) { _ in
            dismiss()
        }
    }

    // MARK: - Map Section

    @ViewBuilder
    private var mapSection: some View {
        // Prefer locally-fetched route so the map updates immediately
        // without waiting for the parent to re-render from the store.
        let currentRun = latestRun
        let displayRouteWithHR = localRouteWithHR ?? currentRun.routeWithHR
        let displayRoute = localRoute ?? currentRun.route

        if let routeWithHR = displayRouteWithHR, routeWithHR.count > 1 {
            InteractiveRouteMapHeat(points: routeWithHR)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    HStack { HeatLegend(); Spacer() }.padding(10),
                    alignment: .topLeading
                )
        } else if let route = displayRoute, route.count > 1 {
            InteractiveRouteMapHeat(coords: route, hrPerPoint: nil)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    HStack { HeatLegend(); Spacer() }.padding(10),
                    alignment: .topLeading
                )
        } else if currentRun.healthKitUUID != nil {
            Button {
                Task { await fetchRouteOnly() }
            } label: {
                HStack(spacing: 8) {
                    if isFetchingRoute {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "map.fill")
                    }
                    Text(isFetchingRoute ? "Fetching route..." : "Get Route")
                        .fontWeight(.semibold)
                        
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent.opacity(isFetchingRoute ? 0.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isFetchingRoute)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Enriched Workout for Sharing

    private func enrichedWorkout() -> CompletedWorkout {
        let currentRun = latestRun
        var workout = currentRun.toCompletedWorkout()
        CardioDataExtractor.shared.enrichWorkout(&workout, from: currentRun)

        // Convert route HR data to samples for the post
        if let routeWithHR = currentRun.routeWithHR, !routeWithHR.isEmpty {
            workout.matchedHealthKitHeartRateSamples = routeWithHR.compactMap { point in
                guard let hr = point.hr else { return nil }
                return HeartRateSample(timestamp: point.t, bpm: hr)
            }
        }
        return workout
    }

    /// Get the latest version of this run from the store (may have route data fetched after view was created)
    private var latestRun: Run {
        store.runs.first(where: { $0.id == run.id }) ?? run
    }

    // MARK: - Map Snapshot Generation

    private func generateMapSnapshotAndShare() async {
        mapSnapshotImage = nil
        var currentRun = latestRun
        isGeneratingSnapshot = true

        // Always attempt on-demand HealthKit fetch if there is no usable route.
        // Use count > 1 (not == nil) because the background queue may have stored an
        // empty routeWithHR = [] when HK hadn't synced the route yet — a non-nil empty
        // array would bypass a nil-only check and silently skip the fetch.
        let hasUsableRoute = (currentRun.routeWithHR?.count ?? 0) > 1 || (currentRun.route?.count ?? 0) > 1

        if !hasUsableRoute, currentRun.healthKitUUID != nil,
           let refreshed = await HealthKitManager.shared.refreshDetailedDataForRun(runId: currentRun.id) {
            currentRun = refreshed
        }

        // Build coordinates from whichever source has data
        let coordinates: [CLLocationCoordinate2D]
        let hrValues: [Double]?

        if let routeWithHR = currentRun.routeWithHR, routeWithHR.count > 1 {
            coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = routeWithHR.map { $0.hr ?? .nan }
        } else if let route = currentRun.route, route.count > 1 {
            coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            hrValues = nil
        } else {
            isGeneratingSnapshot = false
            showingShareSheet = true
            return
        }

        do {
            let snapshot = try await MapSnapshotService.shared.generateRouteSnapshot(
                coordinates: coordinates,
                hrValues: hrValues,
                size: CGSize(width: 600, height: 400)
            )
            mapSnapshotImage = snapshot
        } catch {
            mapSnapshotImage = nil
        }

        isGeneratingSnapshot = false
        showingShareSheet = true
    }

    // MARK: - Route-Only Fetch

    /// Fetches the GPS route from HealthKit and stores it locally so the map
    /// updates immediately without waiting for the background queue.
    private func fetchRouteOnly() async {
        guard !isFetchingRoute, latestRun.healthKitUUID != nil else { return }
        isFetchingRoute = true

        if let updated = await HealthKitManager.shared.refreshDetailedDataForRun(runId: latestRun.id) {
            localRouteWithHR = updated.routeWithHR
            localRoute = updated.route
        }

        isFetchingRoute = false
    }
}

// MARK: - Hero Card

private struct HeroCard: View {
    let run: Run

    private var isStrengthWorkout: Bool {
        run.countsAsStrengthDay
    }

    var body: some View {
        VStack(spacing: 16) {
            // Workout Name & Type
            VStack(spacing: 4) {
                if let workoutName = run.workoutName, !workoutName.isEmpty {
                    Text(workoutName)
                        .dsFont(.title2, weight: .bold)
                        .foregroundStyle(Theme.text)
                }
                HStack(spacing: 6) {
                    if let workoutType = run.workoutType {
                        Text(workoutType)
                            .dsFont(.subheadline, weight: .semibold)
                            .foregroundStyle(Theme.accent)
                    }
                    Text("•").dsFont(.subheadline).foregroundStyle(Theme.secondary)
                    Text(run.date.formatted(date: .abbreviated, time: .shortened))
                        .dsFont(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }

            // Main Stats - Hero Display
            if !isStrengthWorkout {
                HStack(spacing: 20) {
                    // Distance
                    VStack(spacing: 4) {
                        Text(String(format: "%.2f", run.distanceKm))
                            .font(DS.Typography.custom(size: 42, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text("KILOMETERS")
                            .dsFont(.caption2, weight: .semibold)
                            .foregroundStyle(Theme.secondary)
                            .tracking(1)
                    }

                    Divider()
                        .frame(height: 60)
                        .background(Theme.border)

                    // Duration
                    VStack(spacing: 4) {
                        Text(formatTime(run.durationSec))
                            .font(DS.Typography.custom(size: 42, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("TIME")
                            .dsFont(.caption2, weight: .semibold)
                            .foregroundStyle(Theme.secondary)
                            .tracking(1)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                // For strength workouts, show duration prominently
                VStack(spacing: 4) {
                    Text(formatTime(run.durationSec))
                        .font(DS.Typography.custom(size: 42, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("DURATION")
                        .dsFont(.caption2, weight: .semibold)
                        .foregroundStyle(Theme.secondary)
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.surface, Theme.surface2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func formatTime(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Overview Tab

private struct OverviewTab: View {
    let run: Run

    var body: some View {
        VStack(spacing: 12) {
            // Stats Grid
            StatGrid(run: run)

            // Performance Summary
            PerformanceSummary(run: run)

            // Running Dynamics
            RunningDynamicsGrid(
                avgPower: run.avgRunningPower,
                avgCadence: run.avgCadence,
                avgStrideLength: run.avgStrideLength,
                avgGroundContactTime: run.avgGroundContactTime,
                avgVerticalOscillation: run.avgVerticalOscillation
            )
        }
    }
}

// MARK: - Splits Tab

private struct SplitsTab: View {
    let run: Run
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 12) {
            // Refresh button for HealthKit workouts
            if run.healthKitUUID != nil {
                HStack {
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task {
                                isRefreshing = true
                                await HealthKitManager.shared.refreshDetailedDataForRun(runId: run.id)
                                isRefreshing = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(run.splits == nil ? "Load Splits" : "Refresh")
                            }
                            .dsFont(.caption)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            SplitsChart(splits: run.splits ?? [])
        }
    }
}

// MARK: - Heart Rate Tab

private struct HeartRateTab: View {
    let run: Run
    @State private var isRefreshing = false

    private let cardioDataExtractor = CardioDataExtractor.shared

    private var hrZoneSummaries: [HRZoneSummary] {
        cardioDataExtractor.calculateHRZones(from: run) ?? []
    }

    private var hrSamples: [HeartRateSample]? {
        let routeSamples: [HeartRateSample]? = run.routeWithHR?.compactMap { point -> HeartRateSample? in
            guard let hr = point.hr else { return nil }
            return HeartRateSample(timestamp: point.t, bpm: hr)
        }
        if let routeSamples, !routeSamples.isEmpty {
            return routeSamples
        }
        return run.hrSamples
    }

    var body: some View {
        VStack(spacing: 12) {
            // Average HR Card
            if let avgHR = run.avgHeartRate, avgHR > 0 {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average Heart Rate")
                            .dsFont(.subheadline)
                            .foregroundStyle(Theme.secondary)
                        Text("\(Int(avgHR)) bpm")
                            .font(DS.Typography.custom(size: 36, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent.opacity(0.3))
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }

            if run.maxHeartRate != nil || run.minHeartRate != nil {
                HStack(spacing: 10) {
                    if let maxHR = run.maxHeartRate, maxHR > 0 {
                        MetricCard(
                            title: "Max Heart Rate",
                            value: "\(Int(maxHR)) bpm",
                            icon: "arrow.up.heart.fill"
                        )
                    }

                    if let minHR = run.minHeartRate, minHR > 0 {
                        MetricCard(
                            title: "Min Heart Rate",
                            value: "\(Int(minHR)) bpm",
                            icon: "arrow.down.heart.fill"
                        )
                    }
                }
            }

            // Refresh button — show when route is missing OR empty (background queue
            // may have stored [] when Watch hadn't synced the route yet)
            if (run.routeWithHR?.count ?? 0) < 2 && run.healthKitUUID != nil {
                HStack {
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task {
                                isRefreshing = true
                                await HealthKitManager.shared.refreshDetailedDataForRun(runId: run.id)
                                isRefreshing = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Load Details")
                            }
                            .dsFont(.caption)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            HRZoneChart(zones: hrZoneSummaries, samples: hrSamples)
        }
    }
}

// MARK: - Performance Summary

private struct PerformanceSummary: View {
    let run: Run

    private var avgPaceSecPerKm: Int? {
        guard run.distanceKm > 0 else { return nil }
        return (Double(run.durationSec) / run.distanceKm).safeInt
    }

    private var avgSpeedKmh: Double? {
        guard run.durationSec > 0 else { return nil }
        return (run.distanceKm / Double(run.durationSec)) * 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance")
                .dsFont(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let pace = avgPaceSecPerKm {
                    MetricCard(
                        title: "Avg Pace",
                        value: paceString(pace),
                        icon: "speedometer"
                    )
                }

                if let speed = avgSpeedKmh {
                    MetricCard(
                        title: "Avg Speed",
                        value: String(format: "%.1f km/h", speed),
                        icon: "gauge.with.dots.needle.67percent"
                    )
                }

                if let kcal = run.calories, kcal > 0 {
                    MetricCard(
                        title: "Energy",
                        value: "\(Int(kcal)) kcal",
                        icon: "flame.fill"
                    )
                }

                if run.distanceKm > 0 {
                    let calPerKm = (run.calories ?? 0) / run.distanceKm
                    MetricCard(
                        title: "Efficiency",
                        value: String(format: "%.0f kcal/km", calPerKm),
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }
            }
        }
    }

    private func paceString(_ spk: Int) -> String {
        let m = spk / 60
        let s = spk % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .dsFont(.caption)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .dsFont(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Text(value)
                .dsFont(.headline)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Stat Grid

private struct StatGrid: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Stats")
                .dsFont(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                QuickStatTile(
                    icon: "figure.run",
                    label: "Distance",
                    value: String(format: "%.2f km", run.distanceKm)
                )

                QuickStatTile(
                    icon: "clock.fill",
                    label: "Duration",
                    value: formatDuration(run.durationSec)
                )
            }
        }
    }

    private func formatDuration(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m) min"
        }
    }
}

private struct QuickStatTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .dsFont(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .dsFont(.caption)
                    .foregroundStyle(Theme.secondary)
                Text(value)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(Theme.text)
            }

            Spacer()
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}


private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(Color.blue.opacity(0.9)).frame(width: 16, height: 6)
            Capsule().fill(Theme.accent).frame(width: 16, height: 6)
            Capsule().fill(Color.red).frame(width: 16, height: 6)
            Text("HR")
                .dsFont(.caption2, weight: .semibold)
                .foregroundStyle(Theme.text)
                .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}
