//
//  WeeklyGoalSetupView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 18.10.25.
//


// Features/Goals/WeeklyGoalSetupView.swift
import SwiftUI
import SwiftData

struct WeeklyGoalSetupView: View {
    let goal: WeeklyGoal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var targetMinutes: Int = 150
    @State private var targetStrengthDays: Int = 2
    @State private var weekStartDay: Int = 2 // Monday

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Your Weekly Goal").font(.title2.weight(.bold))
                    Text("Track your fitness with custom weekly targets")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("Active Minutes (MVPA)") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(targetMinutes) minutes")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Color(hex: "#F4E409"))
                        Spacer()
                    }
                    Slider(value: Binding(
                        get: { Double(targetMinutes) },
                        set: { targetMinutes = Int($0) }
                    ), in: 30...600, step: 15)
                    .tint(Color(hex: "#F4E409"))

                    Text("WHO recommends 150 minutes per week")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Strength Training Days") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(targetStrengthDays) days")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Color(hex: "#F4E409"))
                        Spacer()
                    }
                    Stepper("", value: $targetStrengthDays, in: 0...7).labelsHidden()
                    Text("Aim for 2-3 strength sessions per week")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Week Start Day") {
                Picker("Week starts on", selection: $weekStartDay) {
                    ForEach(1...7, id: \.self) { day in
                        Text(weekdayName(for: day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Button {
                    saveGoal()
                } label: {
                    HStack { Spacer(); Text("Save Goal").font(.headline); Spacer() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#F4E409"))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Weekly Goal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let g = goal {
                targetMinutes = g.targetActiveMinutes
                targetStrengthDays = g.targetStrengthDays
                weekStartDay = g.anchorWeekday
            }
        }
    }

    private func saveGoal() {
        let g = goal ?? WeeklyGoal()
        g.isSet = true
        g.targetActiveMinutes = targetMinutes
        g.targetStrengthDays = targetStrengthDays
        g.anchorWeekday = weekStartDay
        g.updatedAt = .now

        if goal == nil { context.insert(g) }
        try? context.save()
        dismiss()
    }

    private func weekdayName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1) % 7]
    }
}

private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >> 8) & 0xFF) / 255.0,
                     blue: Double(v & 0xFF) / 255.0,
                     opacity: 1.0)
    }
}
