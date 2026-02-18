//
//  CardioView.swift
//  WRKT
//
//  Runner-focused cardio view with actionable metrics and insights
//

import SwiftUI
import Foundation

private enum Theme {
    static let bg        = Color.black
    static let surface   = Color.black
    static let surface2  = Color.black
    static let border    = Color.white.opacity(0.08)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = DS.Theme.accent
}

// MARK: - Cardio Type Enum

enum CardioType: String, CaseIterable, Identifiable {
    case running = "Running"
    case walking = "Walking"
    case cycling = "Cycling"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        }
    }

    var displayName: String { rawValue }

    var activityName: String {
        switch self {
        case .running: return "Runs"
        case .walking: return "Walks"
        case .cycling: return "Rides"
        }
    }

    var metricLabel: String {
        switch self {
        case .running, .walking: return "Pace"
        case .cycling: return "Speed"
        }
    }

    var metricUnit: String {
        switch self {
        case .running, .walking: return "min/km"
        case .cycling: return "km/h"
        }
    }
}

struct CardioView: View {
    @Environment(\.dependencies) private var deps
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showingAuthSheet = false
    @State private var showingVirtualRunInvite = false
    @State private var isResyncing = false
    @State private var selectedType: CardioType = .running
    @State private var selectedWeekOffset: Int = 0  // 0 = current week, 1 = last week, 2 = 2 weeks ago, etc.
    @State private var selectedWeekTag: Int = 0  // Tag for TabView (same as offset: swipe left = increase = past)

    // Track if we've prompted in this app session (persists across view appearances)
    @AppStorage("hasPromptedForHealthKitAuth") private var hasPromptedThisSession = false

    // Filter to cardio workouts by selected type
    private var cardioRuns: [Run] {
        store.runs.filter { run in
            guard let type = run.workoutType else {
                // Default unknown workouts with distance to running
                return selectedType == .running && run.distanceKm > 0.1
            }
            return type == selectedType.rawValue
        }
    }

    private var runsSorted: [Run] {
        cardioRuns.sorted(by: { $0.date > $1.date })
    }

    // Get runs for a specific week offset (0 = current week, 1 = last week, etc.)
    private func runsForWeek(offset: Int) -> [Run] {
        let cal = Calendar.current
        let now = Date()
        // Get start of current week (Monday)
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 2 // Monday
        guard let currentWeekStart = cal.date(from: components),
              let weekStart = cal.date(byAdding: .day, value: -offset * 7, to: currentWeekStart),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return [] }
        return cardioRuns.filter { $0.date >= weekStart && $0.date < weekEnd }
    }

    // This week's runs (using selected offset)
    private var thisWeekRuns: [Run] {
        runsForWeek(offset: selectedWeekOffset)
    }

    // Previous week's runs for comparison (relative to selected week)
    private var lastWeekRuns: [Run] {
        runsForWeek(offset: selectedWeekOffset + 1)
    }

    // Runs for the selected week only (for Pace Insights)
    private var selectedWeekRuns: [Run] {
        runsForWeek(offset: selectedWeekOffset)
    }

    // Get week label for display
    private func weekLabel(offset: Int) -> String {
        if offset == 0 {
            return "This Week"
        } else if offset == 1 {
            return "Last Week"
        } else {
            let cal = Calendar.current
            var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            components.weekday = 2 // Monday
            guard let currentWeekStart = cal.date(from: components),
                  let weekStart = cal.date(byAdding: .day, value: -offset * 7, to: currentWeekStart) else {
                return "\(offset) weeks ago"
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: weekStart)
        }
    }

    // Maximum number of weeks to show in history (limit to 6 weeks)
    private let maxWeeksHistory = 5  // 0-5 = 6 weeks total

    // Available week offsets (0 to maxWeeksHistory)
    private var availableWeekOffsets: [Int] {
        Array(0...maxWeeksHistory)
    }

    // Last 30 days for pace trend
    private var last30DaysRuns: [Run] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return [] }
        return cardioRuns.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // MARK: - Activity Type Carousel
                CardioTypeCarousel(selectedType: $selectedType)
                    .padding(.horizontal, 16)

                // MARK: - Training Consistency (Global Stats)
                ConsistencyCard(allRuns: cardioRuns, activityType: selectedType)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)

                // MARK: - Weekly Summary (Swipeable)
                VStack(spacing: 12) {
                    // Week navigation header with arrows
                    HStack {
                        // Left arrow: go to future (decrease offset toward 0 = current week)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedWeekOffset > 0 {
                                    selectedWeekOffset -= 1
                                    selectedWeekTag = selectedWeekOffset
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selectedWeekOffset > 0 ? Theme.accent : Theme.secondary.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(selectedWeekOffset == 0)

                        Spacer()

                        // Week label
                        Text(weekLabel(offset: selectedWeekOffset))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .frame(minWidth: 120)

                        Spacer()

                        // Right arrow: go to past (increase offset away from 0)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedWeekOffset < maxWeeksHistory {
                                    selectedWeekOffset += 1
                                    selectedWeekTag = selectedWeekOffset
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selectedWeekOffset < maxWeeksHistory ? Theme.accent : Theme.secondary.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(selectedWeekOffset >= maxWeeksHistory)
                    }
                    .padding(.horizontal, 16)

                    TabView(selection: $selectedWeekTag) {
                        ForEach(availableWeekOffsets, id: \.self) { offset in
                            WeeklySummaryCard(
                                thisWeek: runsForWeek(offset: offset),
                                lastWeek: runsForWeek(offset: offset + 1),
                                activityType: selectedType,
                                weekLabel: weekLabel(offset: offset)
                            )
                            .padding(.horizontal, 16)  // Match padding of other sections
                            .padding(.vertical, 4)      // Add vertical padding to prevent border cutoff
                            .tag(offset)  // Positive tag: swipe LEFT increases tag = goes to past
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 200)  // Increased height to accommodate padding
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectedWeekOffset)
                    .onChange(of: selectedWeekTag) { _, newTag in
                        selectedWeekOffset = newTag  // Tag equals offset
                    }

                    // Page dots (show all 6 weeks)
                    HStack(spacing: 6) {
                        ForEach(availableWeekOffsets, id: \.self) { offset in
                            Circle()
                                .fill(offset == selectedWeekOffset ? Theme.accent : Theme.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedWeekOffset = offset
                                        selectedWeekTag = offset
                                    }
                                }
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)

                // MARK: - Pace Insights (for selected week)
                PaceInsightsCard(
                    runs: selectedWeekRuns,
                    activityType: selectedType,
                    weekLabel: weekLabel(offset: selectedWeekOffset)
                )
                .padding(.horizontal, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedWeekOffset)

                // MARK: - Sync Progress
                if healthKit.isSyncing {
                    HealthKitSyncProgressView(healthKit: healthKit)
                        .padding(.horizontal, 16)
                }

                // MARK: - Recent Activities (filtered by selected week)
                VStack(spacing: 10) {
                    HStack {
                        Text("\(selectedType.activityName) - \(weekLabel(offset: selectedWeekOffset))")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if selectedWeekRuns.count > 10 {
                            NavigationLink("See all", destination: AllRunsList(runs: selectedWeekRuns.sorted(by: { $0.date > $1.date }), activityType: selectedType))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedWeekOffset)

                    if selectedWeekRuns.isEmpty {
                        // Show empty state
                        VStack(spacing: 8) {
                            Image(systemName: selectedType.icon)
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.secondary.opacity(0.5))
                            Text("No \(selectedType.activityName.lowercased()) this week")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(selectedWeekRuns.sorted(by: { $0.date > $1.date }).prefix(10))) { r in
                                NavigationLink {
                                    CardioDetailView(run: r)
                                } label: {
                                    RunRowCard(run: r, activityType: selectedType)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedWeekOffset)
                    }
                }
            }
            .padding(.top, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingVirtualRunInvite = true
                } label: {
                    Label("Run Together", systemImage: "figure.run.square.stack")
                }
                .tint(Theme.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                healthConnectionButton
            }
        }
        .sheet(isPresented: $showingVirtualRunInvite) {
            VirtualRunInviteView()
                .environment(\.dependencies, deps)
        }
        .sheet(isPresented: $showingAuthSheet, onDismiss: {
            // Don't call verifyAuthorizationStatus here - requestAuthorization already did proper check
            // If now connected, trigger immediate sync
            if healthKit.connectionState == .connected {
                Task {
                    do {
                        try await healthKit.syncWorkoutsIncremental()
                        await MainActor.run {
                            store.matchAllWorkoutsWithHealthKit()
                        }
                    } catch {
                        print("Failed to sync after authorization: \(error)")
                    }
                }
            }
        }) {
            HealthAuthSheet()
                .environmentObject(healthKit)
        }
        .refreshable {
            // Pull-to-refresh: Sync recent workouts (resets anchor for reliability)
            print("📊 [CardioView] Pull to refresh - syncing recent workouts")

            await healthKit.syncRecentWorkouts()
            await MainActor.run {
                store.matchAllWorkoutsWithHealthKit()
            }
            print("✅ [CardioView] Recent workout sync completed")
        }
        .task {
            // Clear prompt flag if now connected (user authorized successfully)
            if healthKit.connectionState == .connected {
                hasPromptedThisSession = false
            }
            // Only auto-prompt if disconnected AND haven't prompted this session
            else if healthKit.connectionState == .disconnected && !hasPromptedThisSession {
                // Small delay to avoid jarring immediate popup
                try? await Task.sleep(for: .milliseconds(500))

                // Double-check still disconnected after delay
                if healthKit.connectionState == .disconnected {
                    await MainActor.run {
                        hasPromptedThisSession = true
                        showingAuthSheet = true
                    }
                }
                
            }  

            // Always sync when view appears if connected - anchored queries make this efficient
            if healthKit.connectionState == .connected {
                await healthKit.syncWorkoutsIncremental()
                await MainActor.run {
                    store.matchAllWorkoutsWithHealthKit()
                }
            }
        }
    }

    @ViewBuilder
    private var healthConnectionButton: some View {
        switch healthKit.connectionState {
        case .connected:
            Menu {
                Button {
                    Task {
                        await healthKit.syncWorkoutsIncremental()
                    }
                } label: {
                    Label("Sync New Workouts", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    isResyncing = true
                    Task {
                        await healthKit.forceFullResync()
                        await MainActor.run {
                            store.matchAllWorkoutsWithHealthKit()
                        }
                        isResyncing = false
                    }
                } label: {
                    if isResyncing {
                        Label("Re-syncing...", systemImage: "arrow.clockwise.circle.fill")
                    } else {
                        Label("Force Full Re-sync", systemImage: "arrow.clockwise.circle.fill")
                    }
                }
                .disabled(healthKit.isSyncing || isResyncing)

            } label: {
                if healthKit.isSyncing {
                    HealthKitSyncProgressCompact(healthKit: healthKit)
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .tint(Theme.accent)
            .disabled(healthKit.isSyncing)

        case .limited, .disconnected:
            Button {
                showingAuthSheet = true
            } label: {
                Label("Connect Health", systemImage: "heart.circle")
            }
            .tint(.orange)
        }
    }
}

// MARK: - Cardio Type Carousel

private struct CardioTypeCarousel: View {
    @Binding var selectedType: CardioType
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 16) {
            // Tab content with smooth swipe
            TabView(selection: $selectedType) {
                ForEach(CardioType.allCases) { type in
                    VStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.accent.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)

                        Text(type.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        ChamferedRectangle(.xl)
                            .fill(Theme.surface)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
                    .overlay(
                        ChamferedRectangle(.xl)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.border, Theme.border.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .tag(type)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 150)
            .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0), value: selectedType)

            // Custom page indicators
            CustomPageIndicator(
                numberOfPages: CardioType.allCases.count,
                currentPage: CardioType.allCases.firstIndex(of: selectedType) ?? 0
            )
        }
    }
}

// MARK: - Custom Page Indicator

private struct CustomPageIndicator: View {
    let numberOfPages: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<numberOfPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Theme.accent : Theme.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

// MARK: - Weekly Summary Card

private struct WeeklySummaryCard: View {
    let thisWeek: [Run]
    let lastWeek: [Run]
    let activityType: CardioType
    let weekLabel: String

    private var thisWeekDistance: Double {
        thisWeek.reduce(0) { $0 + $1.distanceKm }
    }

    private var lastWeekDistance: Double {
        lastWeek.reduce(0) { $0 + $1.distanceKm }
    }

    private var thisWeekTime: Int {
        thisWeek.reduce(0) { $0 + $1.durationSec }
    }

    private var thisWeekAvgPace: Double? {
        let paces = thisWeek
            .filter { $0.distanceKm > 0.2 }
            .map { Double($0.durationSec) / $0.distanceKm }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    private var distanceChange: Double? {
        guard lastWeekDistance > 0 else { return nil }
        return ((thisWeekDistance - lastWeekDistance) / lastWeekDistance) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekLabel)
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Spacer()

                if let change = distanceChange {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(String(format: "%.0f%%", abs(change)))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(change >= 0 ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((change >= 0 ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                StatTile(
                    icon: activityType.icon,
                    title: activityType.activityName,
                    value: "\(thisWeek.count)",
                    iconColor: Theme.accent
                )

                // Odometer-style distance display
                OdometerTile(
                    distance: thisWeekDistance,
                    title: "Distance"
                )

                StatTile(
                    icon: "timer",
                    title: "Time",
                    value: formatDuration(thisWeekTime),
                    iconColor: .orange
                )

                if let avgPace = thisWeekAvgPace {
                    StatTile(
                        icon: "speedometer",
                        title: "Avg \(activityType.metricLabel)",
                        value: activityType == .cycling ? speedString(avgPace) : paceString(avgPace),
                        iconColor: .green
                    )
                } else {
                    StatTile(
                        icon: "speedometer",
                        title: "Avg \(activityType.metricLabel)",
                        value: "—",
                        iconColor: .green
                    )
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(Theme.border, lineWidth: 1))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(format: "%dh %dm", h, m)
        } else {
            return String(format: "%dm", m)
        }
    }

    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func speedString(_ secPerKm: Double) -> String {
        // Convert sec/km to km/h
        let kmh = 3600.0 / secPerKm
        return String(format: "%.1f km/h", kmh)
    }
}

// MARK: - Pace Insights Card

private struct PaceInsightsCard: View {
    let runs: [Run]
    let activityType: CardioType
    let weekLabel: String

    private var avgPace: Double? {
        let paces = runs
            .filter { $0.distanceKm > 0.2 }
            .map { Double($0.durationSec) / $0.distanceKm }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    private var bestPace: Double? {
        runs
            .filter { $0.distanceKm > 0.2 }
            .map { Double($0.durationSec) / $0.distanceKm }
            .min()
    }

    // Pace trend: comparing first half vs second half of period
    private var paceTrend: String? {
        guard runs.count >= 3 else { return nil }
        let half = runs.count / 2
        let recentHalf = Array(runs.prefix(half))
        let olderHalf = Array(runs.suffix(half))

        let recentPaces = recentHalf.filter { $0.distanceKm > 0.2 }.map { Double($0.durationSec) / $0.distanceKm }
        let olderPaces = olderHalf.filter { $0.distanceKm > 0.2 }.map { Double($0.durationSec) / $0.distanceKm }

        guard !recentPaces.isEmpty && !olderPaces.isEmpty else { return nil }

        let recentAvg = recentPaces.reduce(0, +) / Double(recentPaces.count)
        let olderAvg = olderPaces.reduce(0, +) / Double(olderPaces.count)

        let diff = recentAvg - olderAvg
        let percentChange = (diff / olderAvg) * 100

        if abs(percentChange) < 2 {
            return "Steady pace"
        } else if diff < 0 {
            return "Getting faster"
        } else {
            return "Slowing down"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(activityType.metricLabel) Insights")
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Spacer()

                Text(weekLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 12) {
                // Average pace/speed
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                        Text("Average")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }

                    if let pace = avgPace {
                        Text(activityType == .cycling ? speedString(pace) : paceString(pace))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.text)
                        Text(activityType.metricUnit)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text("—")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Best pace/speed
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                        Text("Best")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }

                    if let pace = bestPace {
                        Text(activityType == .cycling ? speedString(pace) : paceString(pace))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.text)
                        Text(activityType.metricUnit)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text("—")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Pace trend indicator
            if let trend = paceTrend {
                HStack(spacing: 8) {
                    Image(systemName: trend.contains("faster") ? "arrow.up.right.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(trend.contains("faster") ? .green : .orange)
                    Text(trend)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(Theme.surface, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(Theme.border, lineWidth: 1))
    }

    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func speedString(_ secPerKm: Double) -> String {
        let kmh = 3600.0 / secPerKm
        return String(format: "%.1f km/h", kmh)
    }
}

// MARK: - Consistency Card

private struct ConsistencyCard: View {
    let allRuns: [Run]
    let activityType: CardioType

    // Calculate runs per week based on last 4 weeks for a meaningful recent average
    private var runsPerWeek: Double {
        let cal = Calendar.current
        guard let fourWeeksAgo = cal.date(byAdding: .weekOfYear, value: -4, to: Date()) else { return 0 }
        let recentRuns = allRuns.filter { $0.date >= fourWeeksAgo }
        return Double(recentRuns.count) / 4.0
    }

    private var currentStreak: Int {
        let byDay = Set(allRuns.map { Calendar.current.startOfDay(for: $0.date) })
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())
        while byDay.contains(day) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    private var longestRun: Double {
        allRuns.map(\.distanceKm).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Consistency")
                .font(.headline)
                .foregroundStyle(Theme.text)

            HStack(spacing: 12) {
                // Runs per week
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text("Per Week")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Text(String(format: "%.1f", runsPerWeek))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text(activityType.activityName.lowercased())
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Current streak
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Streak")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Text("\(currentStreak)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text("days")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Longest run
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        Text("Longest")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Text(String(format: "%.1f", longestRun))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text("km")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(Theme.surface, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Odometer Tile

private struct OdometerTile: View {
    let distance: Double
    let title: String

    // Break distance into individual digits for odometer display
    private var digits: [Int] {
        // Format: XXX.X (e.g., 045.7 for 45.7 km)
        let distanceInTenths = (distance * 10).safeInt
        let hundreds = (distanceInTenths / 1000) % 10
        let tens = (distanceInTenths / 100) % 10
        let ones = (distanceInTenths / 10) % 10
        let tenths = distanceInTenths % 10
        return [hundreds, tens, ones, tenths]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            // Odometer display
            HStack(spacing: 2) {
                // First three digits
                ForEach(0..<3) { index in
                    OdometerDigit(digit: digits[index], isDecimal: false)
                }

                // Decimal point
                Text(".")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .offset(y: 2)

                // Tenth digit
                OdometerDigit(digit: digits[3], isDecimal: true)

                // Unit label
                Text("km")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct OdometerDigit: View {
    let digit: Int
    let isDecimal: Bool

    var body: some View {
        Text("\(digit)")
            .font(.system(size: isDecimal ? 16 : 18, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: isDecimal ? 14 : 16, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Stat Tile

private struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var iconColor: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Recent Run Row

private struct RunRowCard: View {
    let run: Run
    let activityType: CardioType

    private var pace: String {
        guard run.distanceKm > 0.2 else { return "—" }
        let secPerKm = Double(run.durationSec) / run.distanceKm
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var speed: String {
        guard run.distanceKm > 0.2 else { return "—" }
        let secPerKm = Double(run.durationSec) / run.distanceKm
        let kmh = 3600.0 / secPerKm
        return String(format: "%.1f", kmh)
    }

    private var hasHeartRate: Bool {
        if let hr = run.avgHeartRate, hr > 0 {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    // Workout type and date
                    HStack(spacing: 4) {
                        if let workoutType = run.workoutType {
                            Text(workoutType)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                        } else {
                            Text("Run")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                        }

                        if let name = run.workoutName, !name.isEmpty {
                            Text("•").font(.caption).foregroundStyle(Theme.secondary)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    Text(run.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }

                Spacer()

                // Pace/Speed - PROMINENT
                VStack(alignment: .trailing, spacing: 2) {
                    if activityType == .cycling {
                        Text(speed)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("km/h")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text(pace)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("min/km")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }

            // Stats row
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(String(format: "%.2f km", run.distanceKm))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.text)
                }

                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(formatDuration(run.durationSec))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.text)
                }

                if hasHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                        Text("\((run.avgHeartRate ?? 0).safeInt) bpm")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.text)
                    }
                }

                Spacer()
            }

            // Route map preview
            if let route = run.route, route.count > 1 {
                InteractiveRouteMapHeat(coords: route, hrPerPoint: nil)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .background(Theme.surface, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(Theme.border, lineWidth: 1))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - All Runs List

private struct AllRunsList: View {
    let runs: [Run]
    let activityType: CardioType

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(runs) { r in
                    NavigationLink {
                        CardioDetailView(run: r)
                    } label: {
                        RunRowCard(run: r, activityType: activityType)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("All \(activityType.activityName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Color Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 244, 228, 9)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
