//
//  StatsDebugView.swift
//  WRKT
//
//  Debug view to diagnose statistics issues

import SwiftUI
import SwiftData

#if DEBUG
struct StatsDebugView: View {
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var repo: ExerciseRepository
    @Environment(\.modelContext) private var modelContext

    @Query private var pushPull: [PushPullBalance]
    @Query private var muscleFreq: [MuscleGroupFrequency]
    @Query private var exVolumes: [ExerciseVolumeSummary]

    @State private var diagnosticResults: [String] = []
    @State private var isRunning = false
    @State private var storageWorkouts: [CompletedWorkout] = []
    @State private var loadingStorage = false
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var testExerciseID: String = ""
    @State private var testResults: String = ""

    var body: some View {
        List {
            Section("⚠️ DATA COMPARISON") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("In-Memory Store")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(store.completedWorkouts.count) workouts")
                            .font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("JSON Storage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if loadingStorage {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("\(storageWorkouts.count) workouts")
                                .font(.headline)
                        }
                    }
                }
                .padding(.vertical, 4)

                if !loadingStorage && store.completedWorkouts.count != storageWorkouts.count {
                    Text("⚠️ MISMATCH! Memory and storage have different workout counts")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                Button {
                    loadingStorage = true
                    Task {
                        await loadStorageWorkouts()
                        loadingStorage = false
                    }
                } label: {
                    Label("Check Storage", systemImage: "arrow.clockwise")
                }
                .disabled(loadingStorage)
            }

            Section("Workout Data (from Store)") {
                Text("Completed Workouts: \(store.completedWorkouts.count)")

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Exercise Repository:")
                            .font(.subheadline)
                        Spacer()
                    }
                    HStack {
                        Text("Display Array:")
                        Spacer()
                        Text("\(repo.exercises.count) exercises")
                            .font(.caption.monospacedDigit())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Check byID Index") {
                        Task {
                            let allExercises = await repo.getAllExercises()
                            diagnosticResults = ["byID index has \(allExercises.count) total exercises"]
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)

                if let latest = store.completedWorkouts.last {
                    Text("Latest Workout (Store): \(latest.date.formatted(date: .long, time: .shortened))")
                        .foregroundStyle(isOld(latest.date) ? .red : .primary)
                    Text("Exercises in latest: \(latest.entries.count)")

                    ForEach(latest.entries.prefix(5), id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ID: \(entry.exerciseID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let exercise = repo.exercise(byID: entry.exerciseID)
                            if let ex = exercise {
                                Text("✅ Found: \(ex.name)")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text("Force: \(ex.force ?? "nil")")
                                    .font(.caption2)
                                Text("Primary: \(ex.primaryMuscles.joined(separator: ", "))")
                                    .font(.caption2)
                            } else {
                                Text("❌ NOT FOUND in repository")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }

            Section("Recent Workouts (from JSON Storage)") {
                if storageWorkouts.isEmpty {
                    Text("Tap 'Check Storage' above to load")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if let latestStorage = storageWorkouts.max(by: { $0.date < $1.date }) {
                        Text("Latest Workout (Storage): \(latestStorage.date.formatted(date: .long, time: .shortened))")
                            .foregroundStyle(isOld(latestStorage.date) ? .red : .green)
                    }

                    Text("Last 10 workouts:")
                        .font(.headline)
                        .padding(.top, 8)

                    let sortedWorkouts = storageWorkouts.sorted(by: { $0.date > $1.date })
                    ForEach(sortedWorkouts.prefix(10)) { workout in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                Text("\(workout.entries.count) exercises")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isToday(workout.date) {
                                Text("TODAY")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(6)
                            } else if isThisWeek(workout.date) {
                                Text("THIS WEEK")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            }

            Section("🧪 LIVE CLASSIFICATION TEST") {
                Text("Test exercises from recent workouts:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let recent = store.completedWorkouts.suffix(3).reversed().first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Workout: \(recent.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline.weight(.semibold))

                        ForEach(recent.entries, id: \.id) { entry in
                            let ex = repo.exercise(byID: entry.exerciseID)
                            VStack(alignment: .leading, spacing: 6) {
                                if let exercise = ex {
                                    let isPush = ExerciseClassifier.isPush(exercise: exercise)
                                    let isPull = ExerciseClassifier.isPull(exercise: exercise)
                                    let isBodyweight = ExerciseClassifier.isBodyweightExercise(exercise)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(exercise.name)
                                                .font(.subheadline)
                                            Spacer()

                                            if isPush && !isPull {
                                                Text("PUSH")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.blue)
                                                    .cornerRadius(6)
                                            } else if isPull && !isPush {
                                                Text("PULL")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.green)
                                                    .cornerRadius(6)
                                            } else if isPush && isPull {
                                                Text("BOTH??")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.orange)
                                                    .cornerRadius(6)
                                            } else {
                                                Text("NEITHER")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.red)
                                                    .cornerRadius(6)
                                            }

                                            if isBodyweight {
                                                Text("BW")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                                    .background(Color.purple)
                                                    .cornerRadius(6)
                                            }
                                        }

                                        // Show volume calculation for this exercise
                                        if let set = entry.sets.first(where: { $0.tag == .working }) {
                                            let userBodyweight = UserDefaults.standard.double(forKey: "user_bodyweight_kg")
                                            let bodyweight = userBodyweight > 0 ? userBodyweight : 70.0

                                            if set.weight > 0 {
                                                Text("Vol: \(set.reps) × \(set.weight.safeInt)kg = \((Double(set.reps) * set.weight).safeInt)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            } else if isBodyweight {
                                                let percentage = ExerciseClassifier.bodyweightPercentage(for: exercise)
                                                let vol = Double(set.reps) * (bodyweight * percentage)
                                                Text("Vol: \(set.reps) × (\(bodyweight.safeInt)kg × \((percentage * 100).safeInt)%) = \(vol.safeInt)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            } else {
                                                Text("Vol: NO WEIGHT + NOT BODYWEIGHT = SKIPPED ⚠️")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                    }

                                    Text("Force: '\(exercise.force ?? "nil")'")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Primary: \(exercise.primaryMuscles.joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("ID: \(entry.exerciseID)")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                    Text("❌ NOT FOUND IN REPO")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            Section("Stats Data") {
                Text("Push/Pull Records: \(pushPull.count)")
                Text("Muscle Frequency: \(muscleFreq.count)")
                Text("Exercise Volumes: \(exVolumes.count)")

                if let latest = pushPull.last {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Push/Pull:")
                            .font(.headline)
                        Text("Week: \(latest.weekStart.formatted(date: .abbreviated, time: .omitted))")
                        Text("Push Volume: \(latest.pushVolume.safeInt)")
                        Text("Pull Volume: \(latest.pullVolume.safeInt)")
                        Text("Ratio: \(String(format: "%.2f", latest.ratio))")
                    }
                }
            }

            Section("Exercise Volume Details") {
                if exVolumes.isEmpty {
                    Text("No exercise volumes recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(exVolumes.suffix(10).reversed(), id: \.key) { vol in
                        VStack(alignment: .leading, spacing: 4) {
                            let exercise = repo.exercise(byID: vol.exerciseID)
                            if let ex = exercise {
                                Text("✅ \(ex.name)")
                                    .font(.subheadline)
                                Text("Volume: \(vol.volume.safeInt) | Force: \(ex.force ?? "nil")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                let isPush = ExerciseClassifier.isPush(exercise: ex)
                                let isPull = ExerciseClassifier.isPull(exercise: ex)
                                Text("Classification: Push=\(isPush), Pull=\(isPull)")
                                    .font(.caption2)
                                    .foregroundStyle(isPush ? .blue : (isPull ? .green : .gray))
                            } else {
                                Text("❌ ID: \(vol.exerciseID)")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                Text("Volume: \(vol.volume.safeInt) | NOT FOUND")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            Section("Actions") {
                Button {
                    isRunning = true
                    diagnosticResults = []
                    Task {
                        await runDiagnostics()
                        isRunning = false
                    }
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Running diagnostics...")
                        }
                    } else {
                        Text("Run Full Diagnostics")
                    }
                }
                .disabled(isRunning)

                Button {
                    Task {
                        await exportDiagnostics()
                    }
                } label: {
                    Label("Export Diagnostic Data", systemImage: "square.and.arrow.up")
                }

                Button {
                    Task {
                        // Force reload workouts from storage
                        let storage = WorkoutStorage.shared
                        if let (workouts, _) = try? await storage.loadWorkouts() {
                            await MainActor.run {
                                // Manually update the store with fresh data
                                AppLogger.warning("Manual reload: \(workouts.count) workouts, latest: \(workouts.max(by: { $0.date < $1.date })?.date.formatted() ?? "none")", category: AppLogger.storage)
                            }
                        }

                        // Force reindex stats with fresh data
                        if let stats = store.stats {
                            if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                                await stats.reindex(all: store.completedWorkouts, cutoff: cutoff)
                            }
                        }
                    }
                } label: {
                    Label("Force Reload & Reindex", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(.orange)
                }

                Button("Force Reindex Stats Only") {
                    Task {
                        if let stats = store.stats {
                            if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                                await stats.reindex(all: store.completedWorkouts, cutoff: cutoff)
                            }
                        }
                    }
                }
            }

            if !diagnosticResults.isEmpty {
                Section("Diagnostic Results") {
                    ForEach(diagnosticResults, id: \.self) { result in
                        Text(result)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Stats Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func runDiagnostics() async {
        var results: [String] = []

        // Check 1: Exercise Repository
        results.append("✓ Exercise Repository: \(repo.exercises.count) exercises loaded")

        // Check 2: Workout Data
        results.append("✓ Completed Workouts: \(store.completedWorkouts.count)")

        if let latest = store.completedWorkouts.last {
            results.append("✓ Latest workout: \(latest.date.formatted())")

            // Check 3: Exercise ID matching
            var matched = 0
            var unmatched = 0
            for entry in latest.entries {
                if repo.exercise(byID: entry.exerciseID) != nil {
                    matched += 1
                } else {
                    unmatched += 1
                    results.append("❌ Exercise ID not found: \(entry.exerciseID)")
                }
            }
            results.append("✓ Matched: \(matched), Unmatched: \(unmatched)")
        }

        // Check 4: Stats Aggregator
        if store.stats != nil {
            results.append("✓ StatsAggregator is initialized")
        } else {
            results.append("❌ StatsAggregator is NOT initialized")
        }

        // Check 5: Balance data
        results.append("Push/Pull records: \(pushPull.count)")
        results.append("Exercise volumes: \(exVolumes.count)")

        // Check 6: Classification test
        if let latest = store.completedWorkouts.last {
            for entry in latest.entries.prefix(3) {
                if let ex = repo.exercise(byID: entry.exerciseID) {
                    let isPush = ExerciseClassifier.isPush(exercise: ex)
                    let isPull = ExerciseClassifier.isPull(exercise: ex)
                    results.append("Exercise: \(ex.name) - Push: \(isPush), Pull: \(isPull), Force: \(ex.force ?? "nil")")
                }
            }
        }

        await MainActor.run {
            diagnosticResults = results
        }
    }

    private func isOld(_ date: Date) -> Bool {
        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return daysSince > 7
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isThisWeek(_ date: Date) -> Bool {
        let now = Date()
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return false
        }
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return false
        }
        return date >= weekStart && date < weekEnd
    }

    private func loadStorageWorkouts() async {
        do {
            let storage = WorkoutStorage.shared
            let (workouts, _) = try await storage.loadWorkouts()
            await MainActor.run {
                storageWorkouts = workouts
                AppLogger.info("Loaded \(workouts.count) workouts from storage for diagnostics", category: AppLogger.storage)
            }
        } catch {
            await MainActor.run {
                storageWorkouts = []
                AppLogger.error("Failed to load workouts from storage: \(error)", category: AppLogger.storage)
            }
        }
    }

    private func exportDiagnostics() async {
        // Ensure storage workouts are loaded
        if storageWorkouts.isEmpty {
            await loadStorageWorkouts()
        }

        var report = "=== WRKT STATISTICS DIAGNOSTIC REPORT ===\n"
        report += "Generated: \(Date().formatted(date: .long, time: .complete))\n\n"

        // Data Comparison
        report += "--- DATA COMPARISON ---\n"
        report += "In-Memory Store: \(store.completedWorkouts.count) workouts\n"
        report += "JSON Storage: \(storageWorkouts.count) workouts\n"
        report += "Exercise Repository: \(repo.exercises.count) exercises\n\n"

        // Latest workouts
        report += "--- LATEST WORKOUTS ---\n"
        if let latest = store.completedWorkouts.last {
            report += "Store Latest: \(latest.date.formatted(date: .long, time: .shortened))\n"
        }
        if let latestStorage = storageWorkouts.max(by: { $0.date < $1.date }) {
            report += "Storage Latest: \(latestStorage.date.formatted(date: .long, time: .shortened))\n"
        }
        report += "\n"

        // Recent workouts from storage
        report += "--- RECENT WORKOUTS (Last 10 from Storage) ---\n"
        let sortedWorkouts = storageWorkouts.sorted(by: { $0.date > $1.date })
        for (index, workout) in sortedWorkouts.prefix(10).enumerated() {
            report += "\(index + 1). \(workout.date.formatted(date: .abbreviated, time: .shortened)) - \(workout.entries.count) exercises"
            if isToday(workout.date) {
                report += " [TODAY]"
            } else if isThisWeek(workout.date) {
                report += " [THIS WEEK]"
            }
            report += "\n"
        }
        report += "\n"

        // Stats Data
        report += "--- STATISTICS DATA ---\n"
        report += "Push/Pull Records: \(pushPull.count)\n"
        report += "Muscle Frequency: \(muscleFreq.count)\n"
        report += "Exercise Volumes: \(exVolumes.count)\n\n"

        if let latest = pushPull.last {
            report += "Latest Push/Pull:\n"
            report += "  Week: \(latest.weekStart.formatted(date: .abbreviated, time: .omitted))\n"
            report += "  Push Volume: \(latest.pushVolume.safeInt)\n"
            report += "  Pull Volume: \(latest.pullVolume.safeInt)\n"
            report += "  Ratio: \(String(format: "%.2f", latest.ratio))\n\n"
        }

        // Exercise Volume Details (last 20)
        report += "--- EXERCISE VOLUME DETAILS (Last 20) ---\n"
        for vol in exVolumes.suffix(20).reversed() {
            let exercise = repo.exercise(byID: vol.exerciseID)
            if let ex = exercise {
                let isPush = ExerciseClassifier.isPush(exercise: ex)
                let isPull = ExerciseClassifier.isPull(exercise: ex)
                report += "✓ \(ex.name)\n"
                report += "  Volume: \(vol.volume.safeInt) | Force: \(ex.force ?? "nil")\n"
                report += "  Classification: Push=\(isPush), Pull=\(isPull)\n"
                report += "  Primary Muscles: \(ex.primaryMuscles.joined(separator: ", "))\n"
            } else {
                report += "✗ ID: \(vol.exerciseID)\n"
                report += "  Volume: \(vol.volume.safeInt) | NOT FOUND in repo\n"
            }
            report += "\n"
        }

        // Sample workout details
        if let sampleWorkout = sortedWorkouts.first {
            report += "--- SAMPLE WORKOUT (Most Recent) ---\n"
            report += "Date: \(sampleWorkout.date.formatted(date: .long, time: .complete))\n"
            report += "Exercises: \(sampleWorkout.entries.count)\n\n"
            for entry in sampleWorkout.entries {
                let ex = repo.exercise(byID: entry.exerciseID)
                if let exercise = ex {
                    report += "Exercise: \(exercise.name)\n"
                    report += "  Sets: \(entry.sets.count)\n"
                    report += "  Force: \(exercise.force ?? "nil")\n"
                    report += "  Primary: \(exercise.primaryMuscles.joined(separator: ", "))\n"
                    let isPush = ExerciseClassifier.isPush(exercise: exercise)
                    let isPull = ExerciseClassifier.isPull(exercise: exercise)
                    report += "  Classification: Push=\(isPush), Pull=\(isPull)\n"
                } else {
                    report += "Exercise ID: \(entry.exerciseID) [NOT FOUND]\n"
                    report += "  Sets: \(entry.sets.count)\n"
                }
                report += "\n"
            }
        }

        report += "=== END OF REPORT ===\n"

        // Save to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "wrkt_diagnostics_\(Date().timeIntervalSince1970).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            await MainActor.run {
                exportedFileURL = fileURL
                showingShareSheet = true
            }
            AppLogger.info("Exported diagnostics to \(fileURL.path)", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to export diagnostics: \(error)", category: AppLogger.app)
        }
    }
}

// MARK: - ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
