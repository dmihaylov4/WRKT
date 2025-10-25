//
//  PreferencesView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct PreferencesView: View {
    // Stored app settings (use your existing keys where possible)
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("user_bodyweight_kg") private var userBodyweightKg: Double = 70.0
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    @AppStorage("streak_reminder_enabled") private var streakReminderEnabled: Bool = false
    @AppStorage("streak_reminder_hour") private var streakReminderHour: Int = 20

    @State private var showResetAlert = false
    @State private var showClearWorkoutsAlert = false
    @State private var showExportSheet = false
    @State private var showResetTimersAlert = false
    @State private var csvFileURL: URL?
    @State private var showShareSheet = false

    @Query private var goals: [WeeklyGoal]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: WorkoutStoreV2

    // Rest timer preferences
    @ObservedObject private var timerPrefs = RestTimerPreferences.shared

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your bodyweight")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f kg", userBodyweightKg))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Stepper("", value: $userBodyweightKg, in: 30...200, step: 0.5)
                        .labelsHidden()
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Used to calculate volume for bodyweight exercises like push-ups and pull-ups.")
                    .font(.caption)
            }


            Section {
                Toggle("Enable rest timer", isOn: $timerPrefs.isEnabled)

                if timerPrefs.isEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Compound exercises", systemImage: "dumbbell.fill")
                                .font(.subheadline)
                            Spacer()
                            Text(formatTime(timerPrefs.defaultCompoundSeconds))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Stepper("", value: $timerPrefs.defaultCompoundSeconds, in: 30...600, step: 30)
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Isolation exercises", systemImage: "figure.strengthtraining.traditional")
                                .font(.subheadline)
                            Spacer()
                            Text(formatTime(timerPrefs.defaultIsolationSeconds))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Stepper("", value: $timerPrefs.defaultIsolationSeconds, in: 30...600, step: 30)
                            .labelsHidden()
                    }

                    Button(role: .destructive) {
                        showResetTimersAlert = true
                    } label: {
                        Label("Reset all custom timers", systemImage: "arrow.counterclockwise")
                    }
                }
            } header: {
                Text("Rest Timer")
            } footer: {
                if timerPrefs.isEnabled {
                    Text("Automatically starts a rest timer after saving sets. Custom timers override these defaults.")
                        .font(.caption)
                }
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

            Section {
                Button {
                    exportWorkoutsToCSV()
                } label: {
                    Label("Export workouts as CSV", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showClearWorkoutsAlert = true
                } label: {
                    Label("Clear all workout data", systemImage: "trash")
                }
                .disabled(store.completedWorkouts.isEmpty)

                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset all data (workouts, stats, XP, dex)", systemImage: "exclamationmark.triangle.fill")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Reset all data will clear everything: workouts, stats, XP, level, PR dex, favorites, and custom timers. Runs/cardio from HealthKit will be preserved.")
                    .font(.caption)
            }

            // Planner
            Section("Workout Planner") {
                NavigationLink {
                    PlannerDebugView()
                } label: {
                    Label("Debug & Testing", systemImage: "wrench.and.screwdriver")
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
        .alert("Clear all workout data?", isPresented: $showClearWorkoutsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear \(store.completedWorkouts.count) workouts", role: .destructive) {
                store.clearAllWorkouts()
            }
        } message: {
            Text("This will permanently delete all \(store.completedWorkouts.count) completed workouts. Your runs and cardio data will be preserved. This cannot be undone.")
        }
        .alert("Reset ALL data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will permanently delete: all workouts, stats, XP, level, PR dex, favorites, and custom timers. Only runs/cardio from HealthKit will be preserved. This cannot be undone.")
        }
        .alert("Reset custom timers?", isPresented: $showResetTimersAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                timerPrefs.resetAllOverrides()
            }
        } message: {
            Text("All custom rest timers for individual exercises will be reset to defaults.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = csvFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if secs == 0 {
            return "\(minutes):00"
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func exportWorkoutsToCSV() {
        let csv = generateCSV()

        // Save to temporary file
        let fileName = "WRKT_Workouts_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            csvFileURL = tempURL
            showShareSheet = true
        } catch {
            print("❌ Failed to export CSV: \(error)")
        }
    }

    private func generateCSV() -> String {
        var csv = "Date,Exercise,Set Number,Tag,Reps,Weight (kg),Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for workout in store.completedWorkouts.sorted(by: { $0.date < $1.date }) {
            let dateStr = dateFormatter.string(from: workout.date)

            for entry in workout.entries {
                for (index, set) in entry.sets.enumerated() {
                    let tag = set.tag.label
                    let completed = set.isCompleted ? "✓" : ""
                    csv += "\"\(dateStr)\",\"\(entry.exerciseName)\",\(index + 1),\"\(tag)\",\(set.reps),\(set.weight),\"\(completed)\"\n"
                }
            }
        }

        return csv
    }

    private func resetAllData() {
        Task {
            // Clear workouts and PRs from store
            store.clearAllWorkouts()

            // Reset rewards (XP, level, dex, PRs in SwiftData)
            RewardsEngine.shared.resetAll()

            // Clear favorites
            FavoritesStore.shared.clearAll()

            // Reset custom timers
            timerPrefs.resetAllOverrides()

            // Clear stats (async) - WAIT for this to complete
            if let stats = store.stats {
                await stats.resetAll()
            }

            // Delete persisted JSON files (old storage) to prevent reload on next launch
            await Persistence.shared.wipeAllDevOnly()
            print("✅ Legacy persisted JSON files deleted")

            // Wipe all data from new unified storage (including PR index)
            try? await WorkoutStorage.shared.wipeAllData()
            print("✅ New storage wiped (workouts, PRs, runs)")

            // Clear all notifications
            await clearAllNotifications()

            // Reset HealthKit state
            await resetHealthKitState()

            // Reset onboarding flags
            UserDefaults.standard.set(false, forKey: "has_completed_onboarding")
            OnboardingManager.shared.resetAllTutorials()
            print("✅ Onboarding flags reset")

            // Force save the view's context as well
            do {
                try context.save()
                print("✅ All data reset complete - changes saved to disk")
            } catch {
                print("❌ Failed to save reset changes: \(error)")
            }
        }
    }

    private func clearAllNotifications() async {
        let center = UNUserNotificationCenter.current()

        // Remove all pending notification requests
        center.removeAllPendingNotificationRequests()

        // Remove all delivered notifications
        center.removeAllDeliveredNotifications()

        print("✅ All notifications cleared")
    }

    private func resetHealthKitState() async {
        // Note: iOS does not allow programmatic revocation of HealthKit permissions
        // Users must manually revoke in Settings > Privacy > Health
        // We can only reset our internal state

        await MainActor.run {
            // Reset HealthKit manager connection state
            HealthKitManager.shared.connectionState = .disconnected

            // Clear any cached health data
            store.clearAllRuns()

            print("✅ HealthKit state reset (user must manually revoke permissions in Settings)")
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
