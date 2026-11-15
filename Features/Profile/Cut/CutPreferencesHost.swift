//
//  CutPreferencesHost.swift
//  WRKT
//
//  PreferencesView's state and flows behind the Cut page, step for step: the same AppStorage
//  keys, rest timer preferences, heart rate zones, custom exercise editor and delete, profile
//  saves (age through the auth service and the zone calculator, bodyweight in AppStorage),
//  social auto-post saves, the smart nudge permission flow, the CSV file exporter, and the four
//  confirmation alerts with their resets. The pure rules come from CutPreferencesLogic.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct CutPreferencesHost: View {
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("user_bodyweight_kg") private var userBodyweightKg: Double = 70.0
    @EnvironmentObject private var authService: SupabaseAuthService
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    @AppStorage("smart_nudges_enabled") private var smartNudgesEnabled: Bool = false
    @AppStorage("weight_step_kg") private var weightStepKg: Double = 2.5
    @AppStorage("auto_add_set_on_rest_timer") private var autoAddSetOnRestTimer: Bool = true

    @State private var showResetAlert = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showClearPlansAlert = false
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

    @ObservedObject private var timerPrefs = RestTimerPreferences.shared
    @ObservedObject private var calculator = HRZoneCalculator.shared

    @EnvironmentObject private var customStore: CustomExerciseStore
    @EnvironmentObject private var repo: ExerciseRepository
    @State private var editingExercise: Exercise?

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var model: CutPreferencesModel {
        let info = Bundle.main.infoDictionary
        return CutPreferencesLogic.model(CutPreferencesFacts(
            currentYear: currentYear,
            birthYear: authService.currentUser?.profile?.birthYear,
            bodyweightKg: userBodyweightKg,
            unit: WeightUnit(rawValue: weightUnitRaw),
            restTimerEnabled: timerPrefs.isEnabled,
            compoundSeconds: timerPrefs.defaultCompoundSeconds,
            isolationSeconds: timerPrefs.defaultIsolationSeconds,
            maxHR: calculator.maxHR,
            zones: calculator.zoneBoundaries().map {
                CutPreferencesFacts.Zone(zone: $0.zone, name: $0.name, range: $0.rangeString)
            },
            zonesMethodDescription: calculator.methodDescription,
            customExercises: customStore.customExercises.map {
                CutPreferencesFacts.CustomExercise(id: $0.id, name: $0.name, primaryMuscle: $0.primaryMuscles.first,
                                                   mechanic: $0.mechanic, equipment: $0.equipment)
            },
            isSignedIn: SupabaseAuthService.shared.currentUser != nil,
            smartNudgesEnabled: smartNudgesEnabled,
            notificationsAuthorized: notificationStatus == .authorized,
            hasWeeklyGoal: goals.first?.isSet == true,
            shortVersion: info?["CFBundleShortVersionString"] as? String,
            buildNumber: info?["CFBundleVersion"] as? String
        ))
    }

    private var controls: CutPreferencesControls {
        let user = SupabaseAuthService.shared.currentUser
        return CutPreferencesControls(
            haptics: $hapticsEnabled,
            weightUnit: $weightUnitRaw,
            weightStep: $weightStepKg,
            restTimer: $timerPrefs.isEnabled,
            autoAddSet: $autoAddSetOnRestTimer,
            compoundSeconds: $timerPrefs.defaultCompoundSeconds,
            isolationSeconds: $timerPrefs.defaultIsolationSeconds,
            autoPostPRs: Binding(
                get: { user?.profile?.autoPostPRs ?? true },
                set: { newValue in Task { try? await SupabaseAuthService.shared.updateProfile(autoPostPRs: newValue) } }
            ),
            autoPostRuns: Binding(
                get: { user?.profile?.autoPostCardio ?? true },
                set: { newValue in Task { try? await SupabaseAuthService.shared.updateProfile(autoPostCardio: newValue) } }
            ),
            autoPostWatch: Binding(
                get: { user?.profile?.autoPostWatchWorkouts ?? false },
                set: { newValue in Task { try? await SupabaseAuthService.shared.updateProfile(autoPostWatchWorkouts: newValue) } }
            ),
            smartNudges: $smartNudgesEnabled
        )
    }

    var body: some View {
        CutPreferencesView(model: model, controls: controls, actions: CutPreferencesActions(
            openAge: { showAgePicker = true },
            openBodyweight: { showWeightPicker = true },
            resetTimers: { showResetTimersAlert = true },
            editExercise: { id in editingExercise = customStore.customExercises.first { $0.id == id } },
            deleteExercise: { id in
                customStore.delete(id)
                Task { await repo.reloadWithCustomExercises() }
            },
            openNotificationSettings: openNotificationSettings,
            exportCSV: exportWorkoutsToCSV,
            clearPlans: { showClearPlansAlert = true },
            resetWeeklyGoal: {
                guard let goal = goals.first, goal.isSet else { return }
                goal.isSet = false
                try? context.save()
            },
            resetAll: { showResetAlert = true }
        ))
        .onChange(of: smartNudgesEnabled) { _, newValue in handleSmartNudgesToggle(newValue) }
        .alert("Reset ALL data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text(CutPreferencesLogic.resetAllMessage)
        }
        .alert("Reset custom timers?", isPresented: $showResetTimersAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                timerPrefs.resetAllOverrides()
            }
        } message: {
            Text(CutPreferencesLogic.resetTimersMessage)
        }
        .alert("Clear all plans and workouts?", isPresented: $showClearPlansAlert) {
            Button("Cancel", role: .cancel) {}
            Button(CutPreferencesLogic.clearPlansButton(plannedWorkouts.count), role: .destructive) {
                clearAllPlans()
            }
        } message: {
            Text(CutPreferencesLogic.clearPlansMessage(plans: plannedWorkouts.count, splits: workoutSplits.count))
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: CutPreferencesLogic.csvFileName(date: Date())
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
            CutAgePickerView(age: Binding(
                get: { CutPreferencesLogic.age(birthYear: authService.currentUser?.profile?.birthYear, currentYear: currentYear) },
                set: { newAge in
                    HRZoneCalculator.shared.userAge = newAge
                    let birthYear = CutPreferencesLogic.birthYear(age: newAge, currentYear: currentYear)
                    Task {
                        try? await authService.updateProfile(birthYear: birthYear)
                    }
                }
            ), done: { showAgePicker = false })
        }
        .sheet(isPresented: $showWeightPicker) {
            CutWeightPickerView(weight: $userBodyweightKg, done: { showWeightPicker = false })
        }
        .task {
            await NotificationManager.shared.checkAuthorizationStatus()
            notificationStatus = NotificationManager.shared.authorizationStatus
        }
    }

    // MARK: - The legacy flows

    private func handleSmartNudgesToggle(_ enabled: Bool) {
        Task {
            if enabled {
                await NotificationManager.shared.checkAuthorizationStatus()
                let status = NotificationManager.shared.authorizationStatus

                if status == .authorized {
                    SmartNudgeManager.shared.setEnabled(true)
                    await SmartNudgeManager.shared.setupNotificationCategories()
                } else if status == .notDetermined {
                    do {
                        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                        if granted {
                            SmartNudgeManager.shared.setEnabled(true)
                            await SmartNudgeManager.shared.setupNotificationCategories()
                            await MainActor.run {
                                notificationStatus = .authorized
                            }
                        } else {
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
                    await MainActor.run {
                        notificationStatus = status
                    }
                }
            } else {
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
        csvDocument = CSVDocument(csv: CutPreferencesLogic.csv(store.completedWorkouts))
        showFileExporter = true
    }

    private func resetAllData() {
        Task {
            AppLogger.info("Starting reset all data...", category: AppLogger.storage)

            store.currentWorkout = nil
            RestTimerManager.shared.stopTimer()

            store.clearAllWorkouts()
            AppLogger.info("Workouts cleared", category: AppLogger.storage)

            RewardsEngine.shared.resetAll()
            AppLogger.info("Rewards reset complete", category: AppLogger.storage)

            FavoritesStore.shared.clearAll()

            for exercise in customStore.customExercises {
                customStore.delete(exercise.id)
            }

            timerPrefs.resetAllOverrides()

            if let stats = store.stats {
                await stats.resetAll()
                AppLogger.info("Stats reset complete", category: AppLogger.storage)
            }

            await Persistence.shared.wipeWorkoutDataPreservingRunsDevOnly()
            AppLogger.success("Legacy workout files deleted, runs preserved", category: AppLogger.storage)

            try? await WorkoutStorage.shared.wipeWorkoutDataPreservingRuns()
            AppLogger.success("New storage wiped (workouts, PRs), runs preserved", category: AppLogger.storage)

            await resetHealthKitState()

            UserDefaults.standard.set(false, forKey: "has_completed_onboarding")
            OnboardingManager.shared.resetAllTutorials()
            AppLogger.success("Onboarding flags reset", category: AppLogger.app)

            do {
                try context.save()
                AppLogger.success("Context saved to disk", category: AppLogger.storage)

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
        for plan in plannedWorkouts {
            context.delete(plan)
        }
        for split in workoutSplits {
            context.delete(split)
        }
        do {
            try context.save()
            AppLogger.success("Cleared \(plannedWorkouts.count) planned workouts and \(workoutSplits.count) splits", category: AppLogger.storage)
        } catch {
            AppLogger.error("Failed to clear plans: \(error)", category: AppLogger.storage)
        }
    }

    private func resetHealthKitState() async {
        await MainActor.run {
            HealthKitManager.shared.isSyncing = false
            HealthKitManager.shared.syncError = nil
            HealthKitManager.shared.lastSyncDate = nil

            AppLogger.success("HealthKit sync state reset; connection and runs preserved", category: AppLogger.health)
        }
    }
}
