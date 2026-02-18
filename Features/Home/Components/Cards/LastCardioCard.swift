//
//  LastCardioCard.swift
//  WRKT
//
//  Shows summary of most recent cardio activity (run/walk/cycle)
//

import SwiftUI

struct LastCardioCard: View {
    let run: Run

    private var relativeDateString: String {
        let calendar = Calendar.current

        // Get start of day for both dates to compare calendar days
        let runDay = calendar.startOfDay(for: run.date)
        let today = calendar.startOfDay(for: .now)

        let daysSince = calendar.dateComponents([.day], from: runDay, to: today).day ?? 0

        if daysSince == 0 {
            return "Today"
        } else if daysSince == 1 {
            return "Yesterday"
        } else {
            return "\(daysSince) days ago"
        }
    }

    private var activityType: String {
        if let workoutType = run.workoutType {
            return workoutType
        }
        return "Cardio"
    }

    private var activityIcon: String {
        let type = run.workoutType?.lowercased() ?? ""
        if type.contains("run") {
            return "figure.run"
        } else if type.contains("walk") {
            return "figure.walk"
        } else if type.contains("cycl") || type.contains("bike") {
            return "figure.outdoor.cycle"
        } else if type.contains("hik") {
            return "figure.hiking"
        } else if type.contains("swim") {
            return "figure.pool.swim"
        } else {
            return "heart.fill"
        }
    }

    private var durationFormatted: String {
        let minutes = run.durationSec / 60
        let seconds = run.durationSec % 60

        if minutes < 60 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    private var paceFormatted: String? {
        guard run.distanceKm > 0 else { return nil }
        let paceSecondsPerKm = Double(run.durationSec) / run.distanceKm
        let paceMinutes = (paceSecondsPerKm / 60).safeInt
        let paceSeconds = (paceSecondsPerKm.truncatingRemainder(dividingBy: 60)).safeInt
        return "\(paceMinutes):\(String(format: "%02d", paceSeconds))/km"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with date and type icon - reserve space for arrow on left
            HStack {
                Text(relativeDateString)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24) // Space for arrow

                Spacer()

                Image(systemName: activityIcon)
                    .font(.caption)
                    .foregroundStyle(DS.tint)
            }

            // Activity name
            Text(activityType)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.top, 4) // Extra spacing from top row

            // Stats row
            HStack(spacing: 12) {
                // Distance
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.2f", run.distanceKm))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Duration
                VStack(alignment: .leading, spacing: 2) {
                    Text(durationFormatted)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Pace (if available)
                if let pace = paceFormatted {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pace)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("pace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Heart rate (if available)
                if let hr = run.avgHeartRate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(hr))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                            Text("bpm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Preview

#Preview("Running") {
    VStack {
        LastCardioCard(
            run: Run(
                date: Date().addingTimeInterval(-86400), // Yesterday
                distanceKm: 5.2,
                durationSec: 1620, // 27 minutes
                avgHeartRate: 145,
                calories: 320,
                workoutType: "Running"
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Cycling") {
    VStack {
        LastCardioCard(
            run: Run(
                date: Date().addingTimeInterval(-172800), // 2 days ago
                distanceKm: 15.5,
                durationSec: 2400, // 40 minutes
                avgHeartRate: 128,
                workoutType: "Cycling"
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Walking") {
    VStack {
        LastCardioCard(
            run: Run(
                date: Date(),
                distanceKm: 3.0,
                durationSec: 1800, // 30 minutes
                workoutType: "Walking"
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
