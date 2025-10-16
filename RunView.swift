//
//  RunsView.swift
//  WRKT
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
    static let accent    = Color(hex: "#F4E409")
}

struct RunsView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var importing = false

    // Derived
    private var runsSorted: [Run] {
        store.runs.sorted(by: { $0.date > $1.date })
    }
    private var recentRuns: [Run] {
        Array(runsSorted.prefix(8)) // ← keep list short
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                // MARK: Summary
                SummaryGrid(runs: store.runs)
                    .padding(.horizontal, 16)

                // MARK: Rewards (simple placeholders; hook up to real logic later)
                RewardsStrip(runs: store.runs)
                    .padding(.horizontal, 16)

                // MARK: Recent
                VStack(spacing: 10) {
                    HStack {
                        Text("Recent").font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        if runsSorted.count > recentRuns.count {
                            NavigationLink("See all", destination: AllRunsList(runs: runsSorted))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        ForEach(recentRuns) { r in
                            NavigationLink {
                                RunDetailView(run: r)
                            } label: {
                                RunRowCard(run: r)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Runs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        importing = true
                        await store.importRunsFromHealth()
                        importing = false
                    }
                } label: {
                    if importing {
                        ProgressView()
                    } else {
                        Label("Import", systemImage: "arrow.down.circle")
                    }
                }
                .tint(Theme.accent)
            }
        }
    }
}

// MARK: - Summary

private struct SummaryGrid: View {
    let runs: [Run]

    private var totalDistance: Double {
        runs.reduce(0) { $0 + $1.distanceKm }
    }
    private var totalTime: Int {
        runs.reduce(0) { $0 + $1.durationSec }
    }
    private var longest: Double {
        runs.map(\.distanceKm).max() ?? 0
    }
    private var bestPaceSecPerKm: Double? {
        let paces = runs
            .filter { $0.distanceKm > 0.2 }
            .map { Double($0.durationSec) / $0.distanceKm }
        return paces.min()
    }
    private var thisMonthKm: Double {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps) ?? now
        return runs.filter { $0.date >= start }.reduce(0) { $0 + $1.distanceKm }
    }
    private var runDaysStreak: Int {
        // simple streak of consecutive days with a run up to today
        let byDay = Set(runs.map { Calendar.current.startOfDay(for: $0.date) })
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())
        while byDay.contains(day) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    var body: some View {
        VStack(spacing: 12) {
            // Streak banner
            if runDaysStreak > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Theme.accent)
                        .padding(8)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(runDaysStreak)-day run streak")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("Keep it going!")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }

            // Stat grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                StatTile(title: "Total", value: String(format: "%.1f km", totalDistance))
                StatTile(title: "Time", value: format(sec: totalTime))
                StatTile(title: "This Month", value: String(format: "%.1f km", thisMonthKm))
                StatTile(title: "Longest", value: String(format: "%.1f km", longest))
                StatTile(title: "Best Pace", value: bestPaceSecPerKm.map { paceString($0) } ?? "—")
                StatTile(title: "Runs", value: "\(runs.count)")
            }
        }
    }

    private func format(sec: Int) -> String {
        String(format: "%02d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }
    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.headline).foregroundStyle(Theme.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Rewards

private struct RewardsStrip: View {
    let runs: [Run]

    private var totalKm: Double { runs.reduce(0) { $0 + $1.distanceKm } }

    private var badges: [Badge] {
        var b: [Badge] = []
        if totalKm >= 10 { b.append(.init("10K Club", "figure.run")) }
        if totalKm >= 42.195 { b.append(.init("Marathon Total", "medal.fill")) }
        if runs.contains(where: { $0.distanceKm >= 21.097 }) { b.append(.init("Half Marathon", "trophy.fill")) }
        if let longest = runs.map(\.distanceKm).max(), longest >= 10 { b.append(.init("Longest ≥ 10K", "star.fill")) }
        return b
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rewards").font(.headline).foregroundStyle(Theme.text)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if badges.isEmpty {
                        Text("Run more to unlock rewards")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    } else {
                        ForEach(badges) { badge in
                            HStack(spacing: 8) {
                                Image(systemName: badge.sf)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.black)
                                    .padding(6)
                                    .background(Theme.accent, in: Circle())
                                Text(badge.title).font(.footnote).foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private struct Badge: Identifiable {
        var id = UUID()
        let title: String
        let sf: String
        init(_ title: String, _ sf: String) { self.title = title; self.sf = sf }
    }
}

// MARK: - Recent Row

private struct RunRowCard: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(run.distanceKm, specifier: "%.2f") km • \(format(sec: run.durationSec))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            if let route = run.route, route.count > 1 {
                InteractiveRouteMapHeat(coords: route, hrPerPoint: nil)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let notes = run.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func format(sec: Int) -> String {
        String(format: "%d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }
}

// MARK: - See all

private struct AllRunsList: View {
    let runs: [Run]
    var body: some View {
        List {
            ForEach(runs) { r in
                NavigationLink {
                    RunDetailView(run: r)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            Text("\(r.distanceKm, specifier: "%.2f") km • \(format(sec: r.durationSec))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("All Runs")
    }

    private func format(sec: Int) -> String {
        String(format: "%d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }
}
