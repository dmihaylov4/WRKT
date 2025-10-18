//
//  PreferencesView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


import SwiftUI
import SwiftData

struct PreferencesView: View {
    // Stored app settings (use your existing keys where possible)
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    @AppStorage("streak_reminder_enabled") private var streakReminderEnabled: Bool = false
    @AppStorage("streak_reminder_hour") private var streakReminderHour: Int = 20

    @State private var showResetAlert = false
    @State private var exportSheet = false

    @Query private var goals: [WeeklyGoal]
    @Environment(\.modelContext) private var context

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section("Units") {
                Picker("Weight units", selection: $weightUnitRaw) {
                    Text("Kilograms (kg)").tag(WeightUnit.kg.rawValue)
                    Text("Pounds (lb)").tag(WeightUnit.lb.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Weight units")
            }

            Section("Feedback") {
                Toggle("Haptics", isOn: $hapticsEnabled)
            }

            Section("Streak reminders") {
                Toggle("Daily reminder", isOn: $streakReminderEnabled)
                if streakReminderEnabled {
                    Stepper("Remind at \(streakReminderHour):00",
                            value: $streakReminderHour, in: 6...23)
                        .accessibilityLabel("Reminder time")
                    Text("We’ll ping you once a day to keep your streak alive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Button {
                    // Hook up your real exporter here.
                    exportSheet = true
                } label: {
                    Label("Export activity", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset progress", systemImage: "trash")
                }
            }

            // Debug Section
            #if DEBUG
            Section("Debug") {
                if let goal = goals.first, goal.isSet {
                    Button {
                        goal.isSet = false
                        try? context.save()
                    } label: {
                        Label("Reset Weekly Goal", systemImage: "arrow.counterclockwise.circle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Weekly goal not set")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            #endif

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://example.com/privacy")!) {
                    Label("Privacy policy", systemImage: "lock.shield")
                }
            }
        }
        .navigationTitle("Preferences")
        .alert("Reset all progress?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                // TODO: inject a service to reset SwiftData rows safely.
                print("Perform reset…")
            }
        } message: {
            Text("This removes XP, streaks, ledger entries, and achievements. This cannot be undone.")
        }
        .sheet(isPresented: $exportSheet) {
            // Placeholder export UI
            VStack(spacing: 16) {
                Image(systemName: "doc.richtext").font(.largeTitle)
                Text("Export coming soon").font(.headline)
                Text("We’ll generate a CSV of workouts, runs, and rewards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close") { exportSheet = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
