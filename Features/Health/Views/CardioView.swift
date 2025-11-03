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
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
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
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showingAuthSheet = false
    @State private var isResyncing = false
    @State private var selectedType: CardioType = .running

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

    // This week's runs
    private var thisWeekRuns: [Run] {
        let cal = Calendar.current
        let now = Date()
        // Get start of current week (Monday)
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 2 // Monday
        guard let weekStart = cal.date(from: components) else { return [] }
        return cardioRuns.filter { $0.date >= weekStart }
    }

    // Last week's runs for comparison
    private var lastWeekRuns: [Run] {
        let cal = Calendar.current
        let now = Date()
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 2 // Monday
        guard let weekStart = cal.date(from: components),
              let lastWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart) else { return [] }
        return cardioRuns.filter { $0.date >= lastWeekStart && $0.date < weekStart }
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

                // MARK: - Weekly Summary
                WeeklySummaryCard(
                    thisWeek: thisWeekRuns,
                    lastWeek: lastWeekRuns,
                    activityType: selectedType
                )
                .padding(.horizontal, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)

                // MARK: - Pace Insights
                PaceInsightsCard(runs: last30DaysRuns, activityType: selectedType)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)

                // MARK: - Training Consistency
                ConsistencyCard(allRuns: cardioRuns, activityType: selectedType)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)

                // MARK: - Sync Progress
                if healthKit.isSyncing {
                    HealthKitSyncProgressView(healthKit: healthKit)
                        .padding(.horizontal, 16)
                }

                // MARK: - Recent Activities
                VStack(spacing: 10) {
                    HStack {
                        Text("Recent \(selectedType.activityName)")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if runsSorted.count > 10 {
                            NavigationLink("See all", destination: AllRunsList(runs: runsSorted, activityType: selectedType))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedType)

                    VStack(spacing: 10) {
                        ForEach(Array(runsSorted.prefix(10))) { r in
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
                }
            }
            .padding(.top, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Cardio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                healthConnectionButton
            }
        }
        .sheet(isPresented: $showingAuthSheet) {
            HealthAuthSheet()
                .environmentObject(healthKit)
        }
        .task {
            let didSync = await healthKit.autoSyncIfNeeded()
            if didSync {
                store.matchAllWorkoutsWithHealthKit()
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
                    .padding(.vertical, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.surface)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                    .tag(type)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 140)
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
                Text("This Week")
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

                StatTile(
                    icon: "map",
                    title: "Distance",
                    value: String(format: "%.1f km", thisWeekDistance),
                    iconColor: .blue
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
        guard runs.count >= 6 else { return nil }
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
            return "Getting faster 📈"
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

                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 12) {
                // Average pace/speed
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(.blue)
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
                            .foregroundStyle(.green)
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
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

// MARK: - Consistency Card

private struct ConsistencyCard: View {
    let allRuns: [Run]
    let activityType: CardioType

    private var runsPerWeek: Double {
        guard let oldestRun = allRuns.min(by: { $0.date < $1.date }) else { return 0 }
        let weeksSinceFirst = max(1, Calendar.current.dateComponents([.weekOfYear], from: oldestRun.date, to: Date()).weekOfYear ?? 1)
        return Double(allRuns.count) / Double(weeksSinceFirst)
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
                        Text("\(Int(run.avgHeartRate ?? 0)) bpm")
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
