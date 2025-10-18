// CardioDetailView.swift
//
// Detailed view for a single cardio workout with map, stats, and heart rate overlay
//

import SwiftUI
import MapKit

private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}

struct CardioDetailView: View {
    let run: Run
    @State private var hasActiveWorkoutInset = false

    var body: some View {
        VStack(spacing: 12) {
            // MAP
            if let route = run.route, route.count > 1 {
                // If you later persist [RoutePoint], switch to the .points initializer (see below).
                InteractiveRouteMapHeat(coords: route, hrPerPoint: nil)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        HStack {
                            HeatLegend()
                            Spacer()
                        }
                        .padding(10),
                        alignment: .topLeading
                    )
            }

            // STATS GRID
            StatGrid(run: run)

            // NOTES
            if let notes = run.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.headline)
                    Text(notes)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .safeAreaInset(edge: .bottom) {
            if hasActiveWorkoutInset { Color.clear.frame(height: 65) }
        }
    }
}

// MARK: - Stat Grid

private struct StatGrid: View {
    let run: Run

    private var paceSecPerKm: Int? {
        guard run.distanceKm > 0 else { return nil }
        return Int(Double(run.durationSec) / run.distanceKm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {

                StatTile(title: "Distance", value: String(format: "%.2f km", run.distanceKm))
                StatTile(title: "Duration", value: format(sec: run.durationSec))

                if let pace = paceSecPerKm {
                    StatTile(title: "Pace", value: paceString(pace))
                } else {
                    StatTile(title: "Pace", value: "—")
                }

                if let hr = run.avgHeartRate, hr > 0 {
                    StatTile(title: "Avg HR", value: "\(Int(hr)) bpm")
                } else {
                    StatTile(title: "Avg HR", value: "—")
                }

                if let kcal = run.calories {
                    StatTile(title: "Calories", value: "\(Int(kcal)) kcal")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(sec: Int) -> String {
        String(format: "%02d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
    }

    private func paceString(_ spk: Int) -> String {
        let m = spk / 60
        let s = spk % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(Color.blue.opacity(0.9)).frame(width: 16, height: 6)
            Capsule().fill(Theme.accent).frame(width: 16, height: 6)
            Capsule().fill(Color.red).frame(width: 16, height: 6)
            Text("HR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}
