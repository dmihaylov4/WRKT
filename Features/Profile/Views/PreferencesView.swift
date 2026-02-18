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
import OSLog

struct PreferencesView: View {
    // Stored app settings (use your existing keys where possible)
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("user_bodyweight_kg") private var userBodyweightKg: Double = 70.0
    @AppStorage("user_age") private var userAge: Int = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    @AppStorage("streak_reminder_enabled") private var streakReminderEnabled: Bool = false
    @AppStorage("streak_reminder_hour") private var streakReminderHour: Int = 20
    @AppStorage("smart_nudges_enabled") private var smartNudgesEnabled: Bool = false

    @State private var showResetAlert = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showClearWorkoutsAlert = false
    @State private var showClearPlansAlert = false
    @State private var showExportSheet = false
    @State private var showResetTimersAlert = false
    @State private var csvDocument: CSVDocument?
    @State private var showFileExporter = false
    @State private var showAgePicker = false
    @State private var showWeightPicker = false

    @Query private var goals: [WeeklyGoal]
    @Query private var plannedWorkouts: [PlannedWorkout]
    @Query private var workoutSplits: [WorkoutSplit]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: WorkoutStoreV2

    // Rest timer preferences
    @ObservedObject private var timerPrefs = RestTimerPreferences.shared

    // Custom exercises
    @EnvironmentObject private var customStore: CustomExerciseStore
    @EnvironmentObject private var repo: ExerciseRepository
    @State private var editingExercise: Exercise?

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }

    var body: some View {
        Form {
            // SECTION 1: Profile & Units
            Section {
                // Age
                Button {
                    showAgePicker = true
                } label: {
                    HStack {
                        Text("Age")
                            .foregroundStyle(.primary)
                        Spacer()
                        if userAge > 0 {
                            Text("\(userAge) years")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Bodyweight
                Button {
                    showWeightPicker = true
                } label: {
                    HStack {
                        Text("Bodyweight")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: "%.1f kg", userBodyweightKg))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Profile")
            } footer: {
                Text("Age is used for heart rate zones (Max HR = 220 - age). Bodyweight is used for bodyweight exercise volume.")
                    .font(.caption)
            }

            // SECTION 2: Workout Preferences
            Section {
                // Haptics
                Toggle(isOn: $hapticsEnabled) {
                    Label("Haptic feedback", systemImage: "hand.tap.fill")
                }

                // Rest Timer
                Toggle(isOn: $timerPrefs.isEnabled) {
                    Label("Rest timer", systemImage: "timer")
                }

                if timerPrefs.isEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Compound exercises", systemImage: "dumbbell.fill")
                            .font(.subheadline)

                        TimeStepper(
                            seconds: $timerPrefs.defaultCompoundSeconds,
                            lowerBound: 30,
                            upperBound: 600,
                            step: 30
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Isolation exercises", systemImage: "figure.strengthtraining.traditional")
                            .font(.subheadline)

                        TimeStepper(
                            seconds: $timerPrefs.defaultIsolationSeconds,
                            lowerBound: 30,
                            upperBound: 600,
                            step: 30
                        )
                    }

                    Button(role: .destructive) {
                        showResetTimersAlert = true
                    } label: {
                        Label("Reset all custom timers", systemImage: "arrow.counterclockwise")
                    }
                }
            } header: {
                Text("Workout Preferences")
            } footer: {
                if timerPrefs.isEnabled {
                    Text("Rest timer starts automatically after saving sets. Custom timers for specific exercises override these defaults.")
                        .font(.caption)
                } else {
                    Text("Control haptic feedback and rest timer behavior during workouts.")
                        .font(.caption)
                }
            }

            // SECTION 3: Heart Rate Zones
            HeartRateZonesSection()

            // SECTION 4: Custom Exercises
            Section {
                if customStore.customExercises.isEmpty {
                    Text("No custom exercises yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(customStore.customExercises, id: \.id) { exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.body)
                                HStack(spacing: 8) {
                                    Text(exercise.primaryMuscles.first ?? "Unknown")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let mechanic = exercise.mechanic {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(mechanic.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let equipment = exercise.equipment {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(equipment)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                editingExercise = exercise
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(DS.Palette.marone)
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                customStore.delete(exercise.id)
                                Task {
                                    await repo.reloadWithCustomExercises()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Custom Exercises")
            } footer: {
                Text("Create custom exercises from the exercise browser by tapping the + button. Swipe left to delete.")
                    .font(.caption)
            }

            // SECTION 5: Social Features
            if let authService = SupabaseAuthService.shared.currentUser {
                Section {
                    Toggle(isOn: Binding(
                        get: { authService.profile?.autoPostPRs ?? true },
                        set: { newValue in
                            Task {
                                try? await SupabaseAuthService.shared.updateProfile(autoPostPRs: newValue)
                            }
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-post PRs")
                                    .font(.body)
                                Text("Automatically share Personal Records to your social feed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "trophy.fill")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { authService.profile?.autoPostCardio ?? true },
                        set: { newValue in
                            Task {
                                try? await SupabaseAuthService.shared.updateProfile(autoPostCardio: newValue)
                            }
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-post runs")
                                    .font(.body)
                                Text("Automatically share runs over 1km with map, heart rate, and stats")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "figure.run")
                        }
                    }
                } header: {
                    Text("Social Features")
                } footer: {
                    Text("When enabled, workouts will be automatically posted to your social feed for friends to see.")
                        .font(.caption)
                }
            }

            // SECTION 6: Notifications & Reminders
            Section {
                Toggle(isOn: $smartNudgesEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart nudges")
                                .font(.body)
                            Text("Get notifications when friends work out")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge.fill")
                    }
                }
                .onChange(of: smartNudgesEnabled) { _, newValue in
                    handleSmartNudgesToggle(newValue)
                }

                // Show permission status if needed
                if smartNudgesEnabled && notificationStatus != .authorized {
                    Button {
                        openNotificationSettings()
                    } label: {
                        Label("Enable in Settings", systemImage: "gear")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Notifications & Reminders")
            } footer: {
                if smartNudgesEnabled {
                    Text("You'll receive notifications when friends complete workouts to help keep you motivated and accountable.")
                        .font(.caption)
                } else {
                    Text("Enable smart nudges to receive motivational notifications based on friend activity.")
                        .font(.caption)
                }
            }

            // SECTION 7: Data Management
            Section {
                Button {
                    exportWorkoutsToCSV()
                } label: {
                    Label("Export workouts as CSV", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("Export your workout history to CSV for analysis in other apps.")
                    .font(.caption)
            }

            // SECTION 8: About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                        .font(.subheadline.monospacedDigit())
                }

                if let privacyURL = URL(string: "https://dmihaylov4.github.io/trak-privacy/") {
                    Link(destination: privacyURL) {
                        Label("Privacy policy", systemImage: "lock.shield")
                    }
                }
            } header: {
                Text("About")
            }

            // SECTION 9: App Settings
            Section {
                Button {
                    showClearPlansAlert = true
                } label: {
                    Label("Clear all plans and workouts", systemImage: "calendar.badge.minus")
                        .foregroundStyle(.orange)
                }

                if let goal = goals.first, goal.isSet {
                    Button {
                        goal.isSet = false
                        try? context.save()
                    } label: {
                        Label("Reset weekly goal", systemImage: "arrow.counterclockwise.circle")
                            .foregroundStyle(.orange)
                    }
                }

                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset all data", systemImage: "exclamationmark.triangle.fill")
                }
            } header: {
                Text("App Settings")
            } footer: {
                Text("⚠️ Reset all data will permanently delete workouts, stats, XP, level, PR dex, favorites, and custom timers. Runs/cardio from HealthKit will be preserved.")
                    .font(.caption)
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
        .alert("Clear all plans and workouts?", isPresented: $showClearPlansAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear \(plannedWorkouts.count) plans", role: .destructive) {
                clearAllPlans()
            }
        } message: {
            Text("This will permanently delete all \(plannedWorkouts.count) planned workouts and \(workoutSplits.count) workout splits from the planner. This cannot be undone.")
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "WRKT_Workouts_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-"))"
        ) { result in
            switch result {
            case .success(let url):
                AppLogger.info("CSV exported to: \(url)", category: AppLogger.storage)
            case .failure(let error):
                AppLogger.error("Failed to export CSV: \(error)", category: AppLogger.storage)
            }
            csvDocument = nil
        }
        .sheet(item: $editingExercise) { exercise in
            CreateExerciseView(
                preselectedMuscle: exercise.primaryMuscles.first ?? "Unknown",
                editingExercise: exercise
            )
            .environmentObject(customStore)
            .environmentObject(repo)
        }
        .sheet(isPresented: $showAgePicker) {
            AgePickerSheet(age: Binding(
                get: { userAge > 0 ? userAge : 30 },
                set: { newAge in
                    userAge = newAge
                    HRZoneCalculator.shared.userAge = newAge
                    // Sync birth year to Supabase for partner HR zone calculation
                    let birthYear = Calendar.current.component(.year, from: Date()) - newAge
                    Task {
                        try? await SupabaseAuthService.shared.updateProfile(birthYear: birthYear)
                    }
                }
            ))
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showWeightPicker) {
            WeightPickerSheet(weight: $userBodyweightKg)
                .presentationDetents([.height(280)])
        }
        .task {
            // Check notification permission status on appear
            await NotificationManager.shared.checkAuthorizationStatus()
            notificationStatus = NotificationManager.shared.authorizationStatus
        }
    }

    // MARK: - Helpers

    private func handleSmartNudgesToggle(_ enabled: Bool) {
        Task {
            if enabled {
                // Check permission first
                await NotificationManager.shared.checkAuthorizationStatus()
                let status = NotificationManager.shared.authorizationStatus

                if status == .authorized {
                    // Permission already granted - just enable
                    SmartNudgeManager.shared.setEnabled(true)
                    await SmartNudgeManager.shared.setupNotificationCategories()
                } else if status == .notDetermined {
                    // Request permission
                    do {
                        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                        if granted {
                            SmartNudgeManager.shared.setEnabled(true)
                            await SmartNudgeManager.shared.setupNotificationCategories()
                            await MainActor.run {
                                notificationStatus = .authorized
                            }
                        } else {
                            // Permission denied - revert toggle
                            await MainActor.run {
                                smartNudgesEnabled = false
                            }
                        }
                    } catch {
                        AppLogger.error("Failed to request notification permission", error: error, category: AppLogger.app)
                        await MainActor.run {
                            smartNudgesEnabled = false
                        }
                    }
                } else {
                    // Permission denied - show settings prompt
                    await MainActor.run {
                        notificationStatus = status
                    }
                }
            } else {
                // Disable nudges
                SmartNudgeManager.shared.setEnabled(false)
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func exportWorkoutsToCSV() {
        let csv = generateCSV()
        csvDocument = CSVDocument(csv: csv)
        showFileExporter = true
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
            AppLogger.info("Starting reset all data...", category: AppLogger.storage)

            // Clear workouts and PRs from store
            store.clearAllWorkouts()
            AppLogger.info("Workouts cleared", category: AppLogger.storage)

            // Reset rewards (XP, level, dex, PRs in SwiftData)
            RewardsEngine.shared.resetAll()
            AppLogger.info("Rewards reset complete", category: AppLogger.storage)

            // Clear favorites
            FavoritesStore.shared.clearAll()

            // Clear custom exercises
            for exercise in customStore.customExercises {
                customStore.delete(exercise.id)
            }

            // Reset custom timers
            timerPrefs.resetAllOverrides()

            // Clear stats (async) - WAIT for this to complete
            if let stats = store.stats {
                await stats.resetAll()
                AppLogger.info("Stats reset complete", category: AppLogger.storage)
            }

            // Delete persisted JSON files (old storage) to prevent reload on next launch
            await Persistence.shared.wipeAllDevOnly()
            AppLogger.success("Legacy persisted JSON files deleted", category: AppLogger.storage)

            // Wipe all data from new unified storage (including PR index)
            try? await WorkoutStorage.shared.wipeAllData()
            AppLogger.success("New storage wiped (workouts, PRs, runs)", category: AppLogger.storage)

            // Reset HealthKit state
            await resetHealthKitState()

            // Reset weekly goal (optional - uncomment if you want to clear the goal setup)
            // if let goal = goals.first {
            //     goal.isSet = false
            //     AppLogger.info("Weekly goal reset", category: AppLogger.storage)
            // }

            // Reset onboarding flags
            UserDefaults.standard.set(false, forKey: "has_completed_onboarding")
            OnboardingManager.shared.resetAllTutorials()
            AppLogger.success("Onboarding flags reset", category: AppLogger.app)

            // IMPORTANT: Save context and verify the RewardProgress was actually reset
            do {
                try context.save()
                AppLogger.success("Context saved to disk", category: AppLogger.storage)

                // Verify the reset worked
                await MainActor.run {
                    if let progress = RewardsEngine.shared.progress {
                        AppLogger.info("After reset - Weekly streak: \(progress.weeklyGoalStreakCurrent), Super streak: \(progress.weeklySuperStreakCurrent)", category: AppLogger.storage)
                    }
                }
            } catch {
                AppLogger.error("Failed to save reset changes: \(error)", category: AppLogger.storage)
            }

            AppLogger.success("All data reset complete", category: AppLogger.storage)
        }
    }

    private func clearAllPlans() {
        // Delete all planned workouts
        for plan in plannedWorkouts {
            context.delete(plan)
        }

        // Delete all workout splits
        for split in workoutSplits {
            context.delete(split)
        }

        // Save changes
        do {
            try context.save()
            AppLogger.success("Cleared \(plannedWorkouts.count) planned workouts and \(workoutSplits.count) splits", category: AppLogger.storage)
        } catch {
            AppLogger.error("Failed to clear plans: \(error)", category: AppLogger.storage)
        }
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

            AppLogger.success("HealthKit state reset (user must manually revoke permissions in Settings)", category: AppLogger.health)
        }
    }
}

// MARK: - Time Stepper Component

/// A stepper for time values that displays in mm:ss format and allows editing
private struct TimeStepper: View {
    @Binding var seconds: Int
    let lowerBound: Int
    let upperBound: Int
    let step: Int

    @State private var editing = false
    @State private var editText = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Minus button
            Button {
                bump(-step)
            } label: {
                Text("−")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            // Time display / editor
            Group {
                if editing {
                    TextField("", text: $editText)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focused)
                        .multilineTextAlignment(.center)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            editText = formatTime(seconds)
                            focused = true
                        }
                        .onChange(of: editText) { _, newValue in
                            // Auto-format as user types
                            let filtered = newValue.filter { $0.isNumber || $0 == ":" }
                            if filtered != newValue {
                                editText = filtered
                            }
                        }
                } else {
                    Text(formatTime(seconds))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editing = true
                        }
                }
            }
            .padding(.horizontal, 8)

            // Plus button
            Button {
                bump(+step)
            } label: {
                Text("+")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                editing = false
                // Parse the time string when done editing
                if let parsed = parseTime(editText) {
                    seconds = max(lowerBound, min(upperBound, parsed))
                }
                editText = ""
            }
        }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                        editing = false
                    }
                }
            }
        }
    }

    private func bump(_ delta: Int) {
        let newValue = max(lowerBound, min(upperBound, seconds + delta))
        if newValue != seconds {
            seconds = newValue
            Haptics.light()
        }
    }

    private func formatTime(_ secs: Int) -> String {
        let minutes = secs / 60
        let remainingSeconds = secs % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    /// Parses time string in formats like "3:00", "3:30", "300", "90" etc.
    private func parseTime(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(":") {
            // Format: "m:ss" or "mm:ss"
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Int(parts[0]),
                  let secs = Int(parts[1]) else {
                return nil
            }
            return minutes * 60 + secs
        } else {
            // Format: just seconds as a number
            return Int(trimmed)
        }
    }
}

// MARK: - CSV Document

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var csv: String

    init(csv: String = "") {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        csv = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = csv.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Heart Rate Zones Section

private struct HeartRateZonesSection: View {
    @ObservedObject private var calculator = HRZoneCalculator.shared
    @State private var showZoneDetails = false

    var body: some View {
        Section {
            // Max HR display
            HStack {
                Label("Max heart rate", systemImage: "heart.fill")
                Spacer()
                Text("\(calculator.maxHR) bpm")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
            }

            // Zone boundaries (expandable)
            DisclosureGroup("Zone boundaries", isExpanded: $showZoneDetails) {
                ForEach(calculator.zoneBoundaries(), id: \.zone) { boundary in
                    HStack {
                        Circle()
                            .fill(boundary.color)
                            .frame(width: 10, height: 10)
                        Text("Zone \(boundary.zone)")
                            .font(.subheadline)
                        Text("(\(boundary.name))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(boundary.rangeString)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Heart Rate Zones")
        } footer: {
            Text(calculator.methodDescription)
                .font(.caption)
        }
    }
}

// MARK: - Age Picker Sheet

private struct AgePickerSheet: View {
    @Binding var age: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Age", selection: $age) {
                    ForEach(10...100, id: \.self) { year in
                        Text("\(year) years").tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 200)
            }
            .navigationTitle("Your Age")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Weight Picker Sheet

private struct WeightPickerSheet: View {
    @Binding var weight: Double
    @Environment(\.dismiss) private var dismiss

    // Split weight into whole and decimal parts for picker
    private var wholeKg: Int {
        Int(weight)
    }

    private var decimalKg: Int {
        Int((weight - Double(wholeKg)) * 10)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Whole kg picker
                    Picker("Kilograms", selection: Binding(
                        get: { wholeKg },
                        set: { weight = Double($0) + Double(decimalKg) / 10.0 }
                    )) {
                        ForEach(30...200, id: \.self) { kg in
                            Text("\(kg)").tag(kg)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(".")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    // Decimal picker
                    Picker("Decimals", selection: Binding(
                        get: { decimalKg },
                        set: { weight = Double(wholeKg) + Double($0) / 10.0 }
                    )) {
                        ForEach(0...9, id: \.self) { decimal in
                            Text("\(decimal)").tag(decimal)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 60)

                    Text("kg")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 16)
                }
                .frame(maxHeight: 200)
            }
            .navigationTitle("Your Bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
