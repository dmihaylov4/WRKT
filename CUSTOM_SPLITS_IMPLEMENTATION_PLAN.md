# Custom Splits Implementation Plan - UPDATED

## Overview
Extend the split planner to support user-created custom splits while maintaining backward compatibility with predefined templates. This plan incorporates validation, intelligent guidance, and future-proofs for trainer-client workout sharing.

---

## Design Principles

### **Constraints Based on Best Practices**
- **Max 4 parts** (e.g., Upper Power, Lower Power, Upper Hypertrophy, Lower Hypertrophy)
- **Min 3 exercises per part** (1 compound + 2 accessories minimum)
- **Max 10 exercises per part** (practical limit before 90+ min sessions)
- **Frequency: 1-6 days/week** (custom splits support full range)

### **Validation Strategy**
1. **Hard Blocks** → Prevent creation (incompatible settings, empty parts)
2. **Soft Warnings** → Show but allow (imbalanced splits, long sessions)
3. **Helpful Guidance** → Educational tips (exercise order, naming suggestions)

---

## Phase 1: Data Model Extensions

### 1.1 Update `SplitTemplate` Model
**File**: `Features/WorkoutSession/Models/SplitTemplates.swift`

```swift
struct SplitTemplate: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let shortName: String
    let description: String
    let days: [DayTemplate]
    let recommendedFrequency: Int
    let difficulty: Difficulty
    let focus: String
    let icon: String

    // NEW: Custom split metadata
    let isCustom: Bool
    let createdBy: String? // "user" or future trainer ID
    let createdAt: Date?
    let lastModified: Date?

    // Future: Import/export
    let shareableID: String? // UUID for sharing
    let version: Int // Schema version for compatibility

    // Default values for predefined splits
    init(id: String, name: String, shortName: String, description: String,
         days: [DayTemplate], recommendedFrequency: Int, difficulty: Difficulty,
         focus: String, icon: String,
         isCustom: Bool = false, createdBy: String? = nil,
         createdAt: Date? = nil, lastModified: Date? = nil,
         shareableID: String? = nil, version: Int = 1) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.description = description
        self.days = days
        self.recommendedFrequency = recommendedFrequency
        self.difficulty = difficulty
        self.focus = focus
        self.icon = icon
        self.isCustom = isCustom
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.shareableID = shareableID
        self.version = version
    }
}
```

### 1.2 Create `CustomSplitStore`
**File**: `Features/Planner/Services/CustomSplitStore.swift`

```swift
import Foundation
import Combine

@MainActor
final class CustomSplitStore: ObservableObject {
    static let shared = CustomSplitStore()

    @Published private(set) var customSplits: [SplitTemplate] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let storageURL: URL
    private let backupURL: URL

    // MARK: - Initialization

    init() {
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not accessible")
        }

        let storageDir = documentsDir.appendingPathComponent("WRKT_Storage", isDirectory: true)
        self.storageURL = storageDir.appendingPathComponent("custom_splits.json")
        self.backupURL = storageDir.appendingPathComponent("custom_splits_backup.json")

        try? fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Public API

    func add(_ split: SplitTemplate) {
        guard !customSplits.contains(where: { $0.id == split.id }) else {
            AppLogger.warning("Custom split already exists: \(split.id)", category: AppLogger.app)
            return
        }

        customSplits.append(split)
        customSplits.sort { $0.name < $1.name }
        save()

        AppLogger.success("Added custom split: \(split.name)", category: AppLogger.app)
    }

    func update(_ split: SplitTemplate) {
        guard let index = customSplits.firstIndex(where: { $0.id == split.id }) else {
            AppLogger.warning("Custom split not found: \(split.id)", category: AppLogger.app)
            return
        }

        customSplits[index] = split
        customSplits.sort { $0.name < $1.name }
        save()

        AppLogger.success("Updated custom split: \(split.name)", category: AppLogger.app)
    }

    func delete(_ splitID: String) {
        guard let index = customSplits.firstIndex(where: { $0.id == splitID }) else {
            AppLogger.warning("Custom split not found: \(splitID)", category: AppLogger.app)
            return
        }

        let name = customSplits[index].name
        customSplits.remove(at: index)
        save()

        AppLogger.success("Deleted custom split: \(name)", category: AppLogger.app)
    }

    func export(_ splitID: String) -> URL? {
        guard let split = customSplits.first(where: { $0.id == splitID }) else {
            return nil
        }

        do {
            let data = try encoder.encode(split)
            let tempURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(split.name.replacingOccurrences(of: " ", with: "_")).wrkt")
            try data.write(to: tempURL)
            return tempURL
        } catch {
            AppLogger.error("Failed to export split", error: error, category: AppLogger.app)
            return nil
        }
    }

    func `import`(from url: URL) throws -> SplitTemplate {
        let data = try Data(contentsOf: url)
        let split = try decoder.decode(SplitTemplate.self, from: data)

        // Validate exercises exist
        try validateExercises(split)

        return split
    }

    // MARK: - Validation

    private func validateExercises(_ split: SplitTemplate) throws {
        let repo = ExerciseRepository.shared

        for day in split.days {
            for exercise in day.exercises {
                guard repo.byID[exercise.exerciseID] != nil else {
                    throw SplitImportError.exerciseNotFound(exercise.exerciseName)
                }
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            AppLogger.debug("No custom splits file found", category: AppLogger.app)
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let splits = try decoder.decode([SplitTemplate].self, from: data)
            self.customSplits = splits.sorted { $0.name < $1.name }
            AppLogger.success("Loaded \(splits.count) custom splits", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to load custom splits", error: error, category: AppLogger.app)

            // Try backup
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    let data = try Data(contentsOf: backupURL)
                    let splits = try decoder.decode([SplitTemplate].self, from: data)
                    self.customSplits = splits.sorted { $0.name < $1.name }
                    AppLogger.success("Restored \(splits.count) custom splits from backup", category: AppLogger.app)
                } catch {
                    AppLogger.error("Failed to restore from backup", error: error, category: AppLogger.app)
                }
            }
        }
    }

    private func save() {
        do {
            // Create backup
            if fileManager.fileExists(atPath: storageURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: storageURL, to: backupURL)
            }

            // Save current
            let data = try encoder.encode(customSplits)
            try data.write(to: storageURL, options: [.atomic])

            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: storageURL.path
            )

            AppLogger.debug("Saved \(customSplits.count) custom splits", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to save custom splits", error: error, category: AppLogger.app)
        }
    }
}

enum SplitImportError: LocalizedError {
    case exerciseNotFound(String)
    case invalidFormat
    case incompatibleVersion

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound(let name):
            return "Exercise '\(name)' not found in your exercise library"
        case .invalidFormat:
            return "Invalid split file format"
        case .incompatibleVersion:
            return "This split was created with a newer version of the app"
        }
    }
}
```

### 1.3 Update `PlanConfig`
**File**: `Features/Planner/PlannerSetupCarouselView.swift`

```swift
class PlanConfig: ObservableObject {
    // Existing
    @Published var selectedTemplate: SplitTemplate?
    @Published var trainingDaysPerWeek: Int = 0
    @Published var restDayPlacement: RestDayPlacement?
    @Published var wantsToCustomize: Bool? = nil
    @Published var customizedDays: [String: [ExerciseTemplate]] = [:]
    @Published var programWeeks: Int = 0
    @Published var includeDeload: Bool = true
    @Published var startDate: Date = Calendar.current.startOfDay(for: .now)

    // NEW: Custom split workflow
    @Published var isCreatingCustom: Bool = false
    @Published var customSplitName: String = ""
    @Published var numberOfParts: Int = 0 // 2, 3, or 4
    @Published var partNames: [String] = []
    @Published var partExercises: [String: [ExerciseTemplate]] = [:] // partName -> exercises

    enum RestDayPlacement: Equatable {
        case afterEachWorkout
        case afterEverySecondWorkout // NEW
        case weekends
        case custom([Int]) // Day indices (0=Mon, 6=Sun)
    }

    // MARK: - Validation

    var isValid: Bool {
        if isCreatingCustom {
            return isCustomSplitValid
        } else {
            return selectedTemplate != nil &&
                   trainingDaysPerWeek > 0 &&
                   restDayPlacement != nil &&
                   wantsToCustomize != nil &&
                   programWeeks > 0
        }
    }

    var isCustomSplitValid: Bool {
        // Name validation
        guard !customSplitName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }

        // Parts validation
        guard numberOfParts >= 2 && numberOfParts <= 4 else {
            return false
        }

        // Part names validation
        guard partNames.count == numberOfParts,
              !partNames.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }),
              Set(partNames).count == numberOfParts else { // No duplicates
            return false
        }

        // Exercises validation
        guard partExercises.count == numberOfParts else {
            return false
        }

        for partName in partNames {
            guard let exercises = partExercises[partName],
                  exercises.count >= 3,
                  exercises.count <= 10 else {
                return false
            }
        }

        // Rest day compatibility
        guard isRestPlacementCompatible else {
            return false
        }

        return trainingDaysPerWeek > 0 && programWeeks > 0
    }

    // Check if rest placement works with current configuration
    var isRestPlacementCompatible: Bool {
        guard let placement = restDayPlacement else { return false }

        switch placement {
        case .afterEachWorkout:
            return numberOfParts * 2 <= 7
        case .afterEverySecondWorkout:
            let totalDays = numberOfParts + (numberOfParts / 2)
            return totalDays <= 7
        case .weekends:
            return trainingDaysPerWeek <= 5
        case .custom:
            return true
        }
    }

    // Get available rest options based on current config
    func availableRestOptions() -> [RestDayPlacement] {
        var options: [RestDayPlacement] = []

        // After each workout
        if numberOfParts * 2 <= 7 && trainingDaysPerWeek < 6 {
            options.append(.afterEachWorkout)
        }

        // After every second workout
        if numberOfParts + (numberOfParts / 2) <= 7 && trainingDaysPerWeek <= 4 {
            options.append(.afterEverySecondWorkout)
        }

        // Weekends
        if trainingDaysPerWeek <= 5 {
            options.append(.weekends)
        }

        // Custom always available
        options.append(.custom([]))

        return options
    }
}
```

### 1.4 Add Validation Helpers
**File**: `Features/Planner/Models/SplitValidation.swift`

```swift
import Foundation

// MARK: - Split Warnings (Non-blocking)

enum SplitWarning: Identifiable {
    case noLegWork
    case noBackWork
    case noPushWork
    case noPullWork
    case imbalancedPushPull(push: Int, pull: Int)
    case allIsolationExercises(part: String)
    case sessionTooLong(minutes: Int, part: String)
    case lowVolume(sets: Int, part: String)
    case noCompoundMovements(part: String)

    var id: String {
        switch self {
        case .noLegWork: return "no-legs"
        case .noBackWork: return "no-back"
        case .noPushWork: return "no-push"
        case .noPullWork: return "no-pull"
        case .imbalancedPushPull: return "push-pull-ratio"
        case .allIsolationExercises(let part): return "isolation-\(part)"
        case .sessionTooLong(_, let part): return "too-long-\(part)"
        case .lowVolume(_, let part): return "low-volume-\(part)"
        case .noCompoundMovements(let part): return "no-compounds-\(part)"
        }
    }

    var severity: Severity {
        switch self {
        case .noLegWork, .noBackWork, .imbalancedPushPull:
            return .high
        case .sessionTooLong, .allIsolationExercises:
            return .medium
        case .lowVolume, .noCompoundMovements, .noPushWork, .noPullWork:
            return .low
        }
    }

    enum Severity {
        case low, medium, high

        var icon: String {
            switch self {
            case .low: return "info.circle"
            case .medium: return "exclamationmark.triangle"
            case .high: return "exclamationmark.octagon"
            }
        }

        var color: String {
            switch self {
            case .low: return "blue"
            case .medium: return "orange"
            case .high: return "red"
            }
        }
    }

    var message: String {
        switch self {
        case .noLegWork:
            return "No leg exercises detected. Consider adding squats, deadlifts, or leg press for balanced development."
        case .noBackWork:
            return "No back exercises detected. Add rows or pulldowns for posture and balance."
        case .noPushWork:
            return "Limited pushing exercises. Consider adding pressing movements."
        case .noPullWork:
            return "Limited pulling exercises. Consider adding rows or pulldowns."
        case .imbalancedPushPull(let push, let pull):
            return "Push:Pull ratio is \(push):\(pull). For shoulder health, aim for 1:1 or 2:3 (more pulling)."
        case .allIsolationExercises(let part):
            return "'\(part)' contains only isolation exercises. Start with at least one compound movement."
        case .sessionTooLong(let minutes, let part):
            return "'\(part)' estimated at \(minutes) minutes. Consider reducing exercises for better recovery."
        case .lowVolume(let sets, let part):
            return "'\(part)' has only \(sets) total sets. Consider adding 1-2 more exercises for adequate volume."
        case .noCompoundMovements(let part):
            return "'\(part)' has no compound movements. Add exercises like squats, deadlifts, bench press, or rows."
        }
    }

    var suggestion: String {
        switch self {
        case .noLegWork:
            return "Add: Squats, Leg Press, or Romanian Deadlifts"
        case .noBackWork:
            return "Add: Barbell Rows, Pull-ups, or Lat Pulldowns"
        case .noPushWork:
            return "Add: Bench Press, Overhead Press, or Push-ups"
        case .noPullWork:
            return "Add: Rows, Pull-ups, or Face Pulls"
        case .imbalancedPushPull:
            return "Add more pulling exercises or reduce pushing volume"
        case .allIsolationExercises:
            return "Start with a compound movement, then add isolation work"
        case .sessionTooLong:
            return "Remove 1-2 exercises or split into two sessions"
        case .lowVolume:
            return "Add 1-2 more exercises or increase sets"
        case .noCompoundMovements:
            return "Add a heavy compound lift as your first exercise"
        }
    }
}

// MARK: - Validation Logic

@MainActor
struct SplitValidator {
    let repo: ExerciseRepository

    func validateSplit(
        partExercises: [String: [ExerciseTemplate]]
    ) -> [SplitWarning] {
        var warnings: [SplitWarning] = []

        // Collect all exercises
        let allExercises = partExercises.values.flatMap { $0 }
        let exerciseDetails = allExercises.compactMap { repo.byID[$0.exerciseID] }

        // Check major muscle groups
        warnings.append(contentsOf: checkMuscleGroupCoverage(exerciseDetails))

        // Check push/pull balance
        if let balanceWarning = checkPushPullBalance(exerciseDetails) {
            warnings.append(balanceWarning)
        }

        // Check each part individually
        for (partName, exercises) in partExercises {
            warnings.append(contentsOf: validatePart(name: partName, exercises: exercises))
        }

        return warnings.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    private func checkMuscleGroupCoverage(_ exercises: [Exercise]) -> [SplitWarning] {
        var warnings: [SplitWarning] = []

        let primaryMuscles = exercises.flatMap { $0.primaryMuscles.map { $0.lowercased() } }

        // Check legs
        let legMuscles = ["quads", "quadriceps", "hamstrings", "glutes", "calves", "leg"]
        let hasLegs = primaryMuscles.contains { muscle in
            legMuscles.contains { muscle.contains($0) }
        }
        if !hasLegs {
            warnings.append(.noLegWork)
        }

        // Check back
        let backMuscles = ["lats", "latissimus", "traps", "trapezius", "back", "rhomboids"]
        let hasBack = primaryMuscles.contains { muscle in
            backMuscles.contains { muscle.contains($0) }
        }
        if !hasBack {
            warnings.append(.noBackWork)
        }

        return warnings
    }

    private func checkPushPullBalance(_ exercises: [Exercise]) -> SplitWarning? {
        let pushCount = exercises.filter { $0.moveBucket == .push }.count
        let pullCount = exercises.filter { $0.moveBucket == .pull }.count

        guard pullCount > 0 else {
            return .noPullWork
        }

        guard pushCount > 0 else {
            return .noPushWork
        }

        let ratio = Double(pushCount) / Double(pullCount)
        if ratio > 1.5 {
            return .imbalancedPushPull(push: pushCount, pull: pullCount)
        }

        return nil
    }

    private func validatePart(name: String, exercises: [ExerciseTemplate]) -> [SplitWarning] {
        var warnings: [SplitWarning] = []

        let exerciseDetails = exercises.compactMap { repo.byID[$0.exerciseID] }

        // Check for compounds
        let hasCompound = exerciseDetails.contains { $0.mechanic?.lowercased() == "compound" }
        if !hasCompound {
            warnings.append(.noCompoundMovements(part: name))
        }

        // Check if all isolation
        let allIsolation = !exerciseDetails.isEmpty && exerciseDetails.allSatisfy {
            $0.mechanic?.lowercased() == "isolation"
        }
        if allIsolation {
            warnings.append(.allIsolationExercises(part: name))
        }

        // Check volume
        let totalSets = exercises.reduce(0) { $0 + $1.sets }
        if totalSets < 12 {
            warnings.append(.lowVolume(sets: totalSets, part: name))
        }

        // Check duration
        let estimatedMinutes = estimateSessionDuration(exercises)
        if estimatedMinutes > 75 {
            warnings.append(.sessionTooLong(minutes: estimatedMinutes, part: name))
        }

        return warnings
    }

    func estimateSessionDuration(_ exercises: [ExerciseTemplate]) -> Int {
        let exerciseDetails = exercises.compactMap { repo.byID[$0.exerciseID] }

        var totalMinutes = 0

        for (template, exercise) in zip(exercises, exerciseDetails) {
            let isCompound = exercise.mechanic?.lowercased() == "compound"
            let minutesPerSet = isCompound ? 4 : 2.5 // Compound needs more rest
            totalMinutes += Int(Double(template.sets) * minutesPerSet)
        }

        return totalMinutes
    }
}

// MARK: - Name Validation

struct NameValidator {
    static func validateSplitName(
        _ name: String,
        existingNames: [String]
    ) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // Empty check
        guard !trimmed.isEmpty else {
            return .invalid(message: "Name cannot be empty", suggestion: nil)
        }

        // Length check
        guard trimmed.count <= 30 else {
            return .invalid(
                message: "Name too long (max 30 characters)",
                suggestion: String(trimmed.prefix(30))
            )
        }

        // Uniqueness check
        if existingNames.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            return .invalid(
                message: "'\(trimmed)' already exists",
                suggestion: "\(trimmed) (Custom)"
            )
        }

        return .valid
    }
}

enum ValidationResult {
    case valid
    case invalid(message: String, suggestion: String?)
}
```

---

## Phase 2: UI Implementation

### 2.1 Step 1: Split Selection (Enhanced)
**File**: `PlannerSetupCarouselView.swift` - `Step1ChooseSplit`

```swift
private struct Step1ChooseSplit: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void
    @EnvironmentObject var customStore: CustomSplitStore

    private var allSplits: [SplitTemplate] {
        SplitTemplates.all + customStore.customSplits
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your training split")
                    .font(.title2.bold())
                    .padding(.horizontal)

                Text("Select a program that matches your goals and schedule.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Predefined splits
                ForEach(SplitTemplates.all) { template in
                    SplitTemplateCard(
                        template: template,
                        isSelected: config.selectedTemplate?.id == template.id
                    ) {
                        withAnimation {
                            config.selectedTemplate = template
                            config.isCreatingCustom = false
                            onAutoAdvance()
                        }
                    }
                }

                // Divider with "OR"
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("OR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                }
                .padding(.vertical, 8)
                .padding(.horizontal)

                // Custom splits section
                CustomSplitCard(
                    isSelected: config.isCreatingCustom
                ) {
                    withAnimation {
                        config.isCreatingCustom = true
                        config.selectedTemplate = nil
                        onAutoAdvance()
                    }
                }

                // Existing custom splits
                if !customStore.customSplits.isEmpty {
                    Text("Your Custom Splits")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ForEach(customStore.customSplits) { template in
                        CustomSplitTemplateCard(
                            template: template,
                            isSelected: config.selectedTemplate?.id == template.id,
                            onSelect: {
                                withAnimation {
                                    config.selectedTemplate = template
                                    config.isCreatingCustom = false
                                    onAutoAdvance()
                                }
                            },
                            onEdit: {
                                // Load into custom creation flow
                                loadCustomSplitForEditing(template)
                            },
                            onDelete: {
                                customStore.delete(template.id)
                            }
                        )
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func loadCustomSplitForEditing(_ template: SplitTemplate) {
        config.isCreatingCustom = true
        config.customSplitName = template.name
        config.numberOfParts = template.days.count
        config.partNames = template.days.map { $0.name }
        config.partExercises = Dictionary(
            uniqueKeysWithValues: template.days.map { ($0.name, $0.exercises) }
        )
        onAutoAdvance()
    }
}

// Custom Split Card
private struct CustomSplitCard: View {
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 40))
                    .foregroundStyle(DS.Palette.marone)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DS.Palette.marone.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Create Custom Split")
                            .font(.headline)
                        Spacer()
                        Text("ADVANCED")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DS.Palette.marone, in: Capsule())
                    }

                    Text("Design your own program from scratch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Palette.marone)
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? DS.Palette.marone : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
```

### 2.2 Step 1a: Custom Split Name (NEW)
**Only shown if `config.isCreatingCustom == true`**

```swift
private struct Step1aCustomName: View {
    @ObservedObject var config: PlanConfig
    @EnvironmentObject var customStore: CustomSplitStore
    let onContinue: () -> Void

    @State private var validationResult: ValidationResult = .valid

    private var existingNames: [String] {
        SplitTemplates.all.map { $0.name } +
        customStore.customSplits.map { $0.name }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name your custom split")
                    .font(.title2.bold())

                Text("Give it a descriptive name that reflects your goals.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Split Name", text: $config.customSplitName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .autocapitalization(.words)
                    .onChange(of: config.customSplitName) { _, newValue in
                        validationResult = NameValidator.validateSplitName(
                            newValue,
                            existingNames: existingNames
                        )
                    }

                if case .invalid(let message, let suggestion) = validationResult {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let suggestion = suggestion {
                        Button("Use '\(suggestion)'") {
                            config.customSplitName = suggestion
                        }
                        .font(.caption)
                    }
                }

                Text("Examples: 'Athletic Performance', 'Powerbuilding 4-Day', 'Upper/Lower Power'")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Palette.marone)
            .disabled(case .invalid = validationResult)
            .padding()
        }
    }
}
```

### 2.3 Step 2: Training Frequency (Enhanced)
```swift
private struct Step2TrainingFrequency: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    private var availableFrequencies: [Int] {
        config.isCreatingCustom ? [1, 2, 3, 4, 5, 6] : [3, 4, 5, 6]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How many days per week?")
                    .font(.title2.bold())
                    .padding(.horizontal)

                Text(config.isCreatingCustom
                     ? "Choose your training frequency (1-6 days)"
                     : "This split works best with these frequencies")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(availableFrequencies, id: \.self) { days in
                    FrequencyCard(
                        days: days,
                        isSelected: config.trainingDaysPerWeek == days,
                        isRecommended: days == config.selectedTemplate?.recommendedFrequency
                    ) {
                        withAnimation {
                            config.trainingDaysPerWeek = days
                            onAutoAdvance()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}
```

### 2.4 Step 3: Rest Days (Enhanced with Conditional Logic)
```swift
private struct Step3RestDays: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    @State private var showCustomSelector = false
    @State private var customRestDays: Set<Int> = []

    private var availableOptions: [(RestDayPlacement, Bool, String?)] {
        let options: [(RestDayPlacement, Bool, String?)] = [
            (
                .afterEachWorkout,
                config.numberOfParts * 2 <= 7 && config.trainingDaysPerWeek < 6,
                config.trainingDaysPerWeek >= 6 ? "Not available for 6 days/week" : nil
            ),
            (
                .afterEverySecondWorkout,
                config.numberOfParts + (config.numberOfParts / 2) <= 7 && config.trainingDaysPerWeek <= 4,
                config.trainingDaysPerWeek > 4 ? "Only available for 2-4 days/week" : nil
            ),
            (
                .weekends,
                config.trainingDaysPerWeek <= 5,
                config.trainingDaysPerWeek > 5 ? "Not available for 6 days/week" : nil
            ),
            (
                .custom([]),
                true,
                nil
            )
        ]

        return options
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When do you rest?")
                    .font(.title2.bold())
                    .padding(.horizontal)

                Text("Choose how rest days fit into your schedule")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(availableOptions, id: \.0) { option, isAvailable, disabledReason in
                    RestDayCard(
                        option: option,
                        isSelected: matches(config.restDayPlacement, option),
                        isDisabled: !isAvailable,
                        disabledReason: disabledReason
                    ) {
                        withAnimation {
                            if case .custom = option {
                                showCustomSelector = true
                            } else {
                                config.restDayPlacement = option
                                onAutoAdvance()
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showCustomSelector) {
            CustomWeekdaySelector(
                selectedDays: $customRestDays,
                onSave: {
                    config.restDayPlacement = .custom(Array(customRestDays).sorted())
                    showCustomSelector = false
                    onAutoAdvance()
                }
            )
        }
    }

    private func matches(_ placement: RestDayPlacement?, _ option: RestDayPlacement) -> Bool {
        guard let placement = placement else { return false }

        switch (placement, option) {
        case (.afterEachWorkout, .afterEachWorkout),
             (.afterEverySecondWorkout, .afterEverySecondWorkout),
             (.weekends, .weekends):
            return true
        case (.custom, .custom):
            return true
        default:
            return false
        }
    }
}

private struct RestDayCard: View {
    let option: PlanConfig.RestDayPlacement
    let isSelected: Bool
    let isDisabled: Bool
    let disabledReason: String?
    let onSelect: () -> Void

    private var title: String {
        switch option {
        case .afterEachWorkout: return "After Each Workout"
        case .afterEverySecondWorkout: return "After Every 2nd Workout"
        case .weekends: return "Weekends"
        case .custom: return "Custom Days"
        }
    }

    private var description: String {
        switch option {
        case .afterEachWorkout: return "Train, rest, train, rest..."
        case .afterEverySecondWorkout: return "Train 2 days, rest 1 day"
        case .weekends: return "Rest Saturday and Sunday"
        case .custom: return "Choose specific days"
        }
    }

    var body: some View {
        Button(action: isDisabled ? {} : onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isDisabled, let reason = disabledReason {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                            Text(reason)
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Palette.marone)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? DS.Palette.marone : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.horizontal)
    }
}

private struct CustomWeekdaySelector: View {
    @Binding var selectedDays: Set<Int>
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Select your rest days")
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    ForEach(0..<7, id: \.self) { index in
                        WeekdayToggle(
                            day: weekdays[index],
                            isSelected: selectedDays.contains(index)
                        ) {
                            if selectedDays.contains(index) {
                                selectedDays.remove(index)
                            } else {
                                selectedDays.insert(index)
                            }
                        }
                    }
                }
                .padding()

                Spacer()

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Palette.marone)
                .disabled(selectedDays.isEmpty)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WeekdayToggle: View {
    let day: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 4) {
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .black : .secondary)
            }
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? DS.Palette.marone : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}
```

### 2.5 Step 3a: Define Parts (NEW - Custom Only)
```swift
private struct Step3aDefineParts: View {
    @ObservedObject var config: PlanConfig
    let onContinue: () -> Void

    @State private var showSuggestions = true

    private var suggestions: [String] {
        switch config.numberOfParts {
        case 2: return ["Upper", "Lower"]
        case 3: return ["Push", "Pull", "Legs"]
        case 4: return ["Upper Power", "Lower Power", "Upper Hypertrophy", "Lower Hypertrophy"]
        default: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Design your split")
                        .font(.title2.bold())

                    Text("Define the structure of your training program")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Number of parts selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("How many parts?")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(2...4, id: \.self) { num in
                            PartNumberButton(
                                number: num,
                                isSelected: config.numberOfParts == num
                            ) {
                                withAnimation {
                                    config.numberOfParts = num
                                    // Reset part names
                                    config.partNames = Array(repeating: "", count: num)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                if config.numberOfParts > 0 {
                    Divider()
                        .padding(.vertical)

                    // Part naming
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Name each part")
                                .font(.headline)

                            Spacer()

                            if !suggestions.isEmpty && showSuggestions {
                                Button {
                                    config.partNames = suggestions
                                    showSuggestions = false
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lightbulb.fill")
                                        Text("Use Suggestion")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.marone)
                                }
                            }
                        }

                        if !suggestions.isEmpty && showSuggestions {
                            Text("💡 Suggested: " + suggestions.joined(separator: " / "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(DS.Palette.marone.opacity(0.1))
                                )
                        }

                        ForEach(0..<config.numberOfParts, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Part \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextField("e.g., \(suggestions.isEmpty ? "Upper Body" : suggestions[safe: index] ?? "Body Part")",
                                         text: Binding(
                                            get: { config.partNames[safe: index] ?? "" },
                                            set: { newValue in
                                                if config.partNames.indices.contains(index) {
                                                    config.partNames[index] = newValue
                                                }
                                            }
                                         ))
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.words)
                            }
                        }

                        Text("Common patterns: Push/Pull/Legs, Upper/Lower, Power/Hypertrophy")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Palette.marone)
                .disabled(!isValid)
                .padding()
            }
        }
    }

    private var isValid: Bool {
        config.numberOfParts >= 2 &&
        config.numberOfParts <= 4 &&
        config.partNames.count == config.numberOfParts &&
        !config.partNames.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) &&
        Set(config.partNames).count == config.numberOfParts // No duplicates
    }
}

private struct PartNumberButton: View {
    let number: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text("\(number)")
                    .font(.title2.bold())
                Text("parts")
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? .black : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? DS.Palette.marone : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

### 2.6 Step 4: Customize Exercises (Enhanced)
```swift
private struct Step4CustomizeExercises: View {
    @ObservedObject var config: PlanConfig
    @EnvironmentObject var repo: ExerciseRepository
    let onAutoAdvance: () -> Void

    @State private var selectedPartIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            if config.isCreatingCustom {
                // Custom split: show tabs for each part
                TabView(selection: $selectedPartIndex) {
                    ForEach(0..<config.numberOfParts, id: \.self) { index in
                        PartExerciseEditor(
                            partName: config.partNames[index],
                            exercises: Binding(
                                get: { config.partExercises[config.partNames[index]] ?? [] },
                                set: { config.partExercises[config.partNames[index]] = $0 }
                            )
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

            } else {
                // Predefined split: existing customize UI
                // ... existing code
            }
        }
    }
}

private struct PartExerciseEditor: View {
    let partName: String
    @Binding var exercises: [ExerciseTemplate]
    @EnvironmentObject var repo: ExerciseRepository

    @State private var showExercisePicker = false
    @State private var editingExercise: ExerciseTemplate?

    private var estimatedDuration: Int {
        SplitValidator(repo: repo).estimateSessionDuration(exercises)
    }

    private var sortedExercises: [Exercise] {
        sortExercisesByRelevance(for: partName, allExercises: Array(repo.byID.values))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("\(partName) Exercises")
                    .font(.title2.bold())

                HStack {
                    Label("\(exercises.count) exercises", systemImage: "list.bullet")
                    Text("•")
                    Label("\(totalSets) sets", systemImage: "number.circle")
                    Text("•")
                    Label("\(estimatedDuration) min", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Min/max guidance
                if exercises.count < 3 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Add at least 3 exercises")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else if exercises.count > 10 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Consider reducing to 10 or fewer exercises")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(DS.Semantic.surface)

            // Exercise list
            List {
                ForEach(exercises) { exercise in
                    ExerciseTemplateRow(exercise: exercise) {
                        editingExercise = exercise
                    }
                }
                .onMove { from, to in
                    exercises.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { indexSet in
                    exercises.remove(atOffsets: indexSet)
                }

                // Add exercise button
                Button {
                    showExercisePicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DS.Palette.marone)
                        Text("Add Exercise")
                            .foregroundStyle(DS.Palette.marone)
                    }
                }
                .disabled(exercises.count >= 10)
            }
            .listStyle(.plain)

            // Tip
            if exercises.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("💡 Start with compound movements")
                        .font(.subheadline.weight(.semibold))

                    Text("Add big lifts first (bench press, squats, rows), then isolation exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(
                availableExercises: sortedExercises,
                onSelect: { exerciseID, exerciseName in
                    exercises.append(ExerciseTemplate(
                        exerciseID: exerciseID,
                        exerciseName: exerciseName,
                        sets: 3,
                        reps: 10
                    ))
                    showExercisePicker = false
                }
            )
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseTemplateEditor(
                exercise: exercise,
                onSave: { updatedExercise in
                    if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                        exercises[index] = updatedExercise
                    }
                    editingExercise = nil
                }
            )
        }
    }

    private var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets }
    }

    // Smart sorting: relevant exercises first
    private func sortExercisesByRelevance(
        for partName: String,
        allExercises: [Exercise]
    ) -> [Exercise] {
        let nameLower = partName.lowercased()

        return allExercises.sorted { a, b in
            // Priority 1: Primary muscle match
            let aPrimaryMatch = a.primaryMuscles.contains { muscle in
                nameLower.contains(muscle.lowercased()) ||
                muscle.lowercased().contains(nameLower)
            }
            let bPrimaryMatch = b.primaryMuscles.contains { muscle in
                nameLower.contains(muscle.lowercased()) ||
                muscle.lowercased().contains(nameLower)
            }
            if aPrimaryMatch != bPrimaryMatch { return aPrimaryMatch }

            // Priority 2: Compound before isolation
            let aCompound = a.mechanic?.lowercased() == "compound"
            let bCompound = b.mechanic?.lowercased() == "compound"
            if aCompound != bCompound { return aCompound }

            // Priority 3: Alphabetical
            return a.name < b.name
        }
    }
}
```

### 2.7 Step 6: Review (Enhanced with Warnings)
```swift
private struct Step6Review: View {
    @ObservedObject var config: PlanConfig
    @EnvironmentObject var repo: ExerciseRepository
    let onGenerate: () -> Void

    @State private var warnings: [SplitWarning] = []
    @State private var showWarningDetails = false

    private let validator = SplitValidator(repo: ExerciseRepository.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Review Your Split")
                    .font(.title.bold())
                    .padding(.horizontal)

                // Split info
                VStack(alignment: .leading, spacing: 12) {
                    if config.isCreatingCustom {
                        Text(config.customSplitName)
                            .font(.title3.weight(.semibold))
                        Text("\(config.numberOfParts)-Part Custom Split")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(config.selectedTemplate?.name ?? "")
                            .font(.title3.weight(.semibold))
                        Text(config.selectedTemplate?.description ?? "")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack {
                        Label("\(config.trainingDaysPerWeek) days/week", systemImage: "calendar")
                        Spacer()
                        Label("\(config.programWeeks) weeks", systemImage: "clock")
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Semantic.surface)
                )
                .padding(.horizontal)

                // Week schedule preview
                WeekSchedulePreview(config: config)
                    .padding(.horizontal)

                // Warnings (if any)
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Suggestions")
                                .font(.headline)
                            Spacer()
                            Button(showWarningDetails ? "Hide" : "Show") {
                                withAnimation {
                                    showWarningDetails.toggle()
                                }
                            }
                            .font(.caption)
                        }

                        if showWarningDetails {
                            ForEach(warnings) { warning in
                                WarningCard(warning: warning)
                            }
                        } else {
                            Text("\(warnings.count) suggestion\(warnings.count == 1 ? "" : "s") for your split")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal)
                }

                Spacer()

                // Generate button
                Button("Create Split") {
                    onGenerate()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Palette.marone)
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .onAppear {
            if config.isCreatingCustom {
                warnings = validator.validateSplit(partExercises: config.partExercises)
            }
        }
    }
}

private struct WeekSchedulePreview: View {
    let config: PlanConfig

    private var weekSchedule: [(day: String, workout: String?)] {
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        // Generate schedule based on config
        // ... implementation
        return [] // Placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week 1 Schedule")
                .font(.headline)

            ForEach(weekSchedule, id: \.day) { item in
                HStack {
                    Text(item.day)
                        .frame(width: 40, alignment: .leading)
                        .foregroundStyle(.secondary)

                    if let workout = item.workout {
                        Text(workout)
                            .foregroundStyle(DS.Palette.marone)
                            .fontWeight(.semibold)
                    } else {
                        Text("Rest")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }

            Text("Pattern repeats in following weeks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Semantic.surface)
        )
    }
}

private struct WarningCard: View {
    let warning: SplitWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: warning.severity.icon)
                    .foregroundStyle(colorForSeverity)
                Text(warning.message)
                    .font(.caption)
            }

            if !warning.suggestion.isEmpty {
                Text("→ " + warning.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var colorForSeverity: Color {
        switch warning.severity {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}
```

---

## Phase 3: Integration & Persistence

### 3.1 Save Custom Split
```swift
// In PlannerSetupCarouselView
private func generatePlan() {
    if config.isCreatingCustom {
        saveAndUseCustomSplit()
    } else {
        // Existing predefined split logic
    }
}

private func saveAndUseCustomSplit() {
    let customSplit = SplitTemplate(
        id: "custom_\(UUID().uuidString)",
        name: config.customSplitName,
        shortName: String(config.customSplitName.prefix(4)).uppercased(),
        description: "Custom \(config.numberOfParts)-part split",
        days: config.partNames.map { partName in
            DayTemplate(
                id: UUID().uuidString,
                name: partName,
                exercises: config.partExercises[partName] ?? [],
                isRestDay: false
            )
        },
        recommendedFrequency: config.trainingDaysPerWeek,
        difficulty: .intermediate,
        focus: "Custom program",
        icon: "slider.horizontal.3",
        isCustom: true,
        createdBy: "user",
        createdAt: Date(),
        lastModified: Date(),
        shareableID: UUID().uuidString,
        version: 1
    )

    CustomSplitStore.shared.add(customSplit)
    config.selectedTemplate = customSplit

    // Continue with workout plan generation
    // ... existing code
}
```

### 3.2 Inject CustomSplitStore
```swift
// In AppDependencies.swift
let customSplitStore: CustomSplitStore

// In init
self.customSplitStore = CustomSplitStore.shared

// In withDependencies extension
.environmentObject(dependencies.customSplitStore)
```

---

## Phase 4: Implementation Timeline

### **Week 1: Foundation (Days 1-5)**
- [ ] Data models: Update `SplitTemplate`, create `CustomSplitStore`
- [ ] Update `PlanConfig` with new properties
- [ ] Create `SplitValidation.swift` with warnings logic
- [ ] Add `CustomSplitStore` to `AppDependencies`
- [ ] Write tests for validation logic

### **Week 2: Basic UI (Days 6-10)**
- [ ] Update Step 1: Add custom split card
- [ ] Implement Step 1a: Name input with validation
- [ ] Enhance Step 2: Add 1-6 day frequency
- [ ] Update total steps count and navigation
- [ ] Test basic flow (name → frequency)

### **Week 3: Rest & Parts (Days 11-15)**
- [ ] Enhance Step 3: Add conditional rest options
- [ ] Implement "After Every 2nd Workout" option
- [ ] Create custom weekday selector
- [ ] Implement Step 3a: Define parts
- [ ] Add part naming suggestions
- [ ] Test rest day compatibility logic

### **Week 4: Exercise Assignment (Days 16-20)**
- [ ] Enhance Step 4: Tabbed view for parts
- [ ] Implement smart exercise sorting
- [ ] Add duration estimates
- [ ] Create exercise picker with relevance
- [ ] Add drag-to-reorder functionality
- [ ] Test exercise assignment flow

### **Week 5: Review & Warnings (Days 21-25)**
- [ ] Enhance Step 6: Add warnings display
- [ ] Implement week schedule preview
- [ ] Create warning cards with severity
- [ ] Add split balance validation
- [ ] Test complete custom split creation
- [ ] Fix bugs and edge cases

### **Week 6: Management & Polish (Days 26-30)**
- [ ] Display custom splits in Step 1
- [ ] Add edit functionality
- [ ] Add delete with confirmation
- [ ] Implement export to JSON
- [ ] Implement import from JSON
- [ ] Add onboarding tips throughout
- [ ] Final testing and bug fixes

---

## Testing Checklist

### **Unit Tests**
- [ ] `CustomSplitStore` save/load/delete
- [ ] Name validation logic
- [ ] Rest day compatibility checks
- [ ] Split balance warnings
- [ ] Duration estimation
- [ ] Exercise relevance sorting

### **Integration Tests**
- [ ] Complete custom split creation flow
- [ ] Edit existing custom split
- [ ] Delete custom split
- [ ] Export/import custom split
- [ ] Custom split with workout generation

### **UI Tests**
- [ ] All step navigation
- [ ] Form validation states
- [ ] Disabled options display correctly
- [ ] Warning cards show/hide
- [ ] Week preview displays correctly

### **Edge Cases**
- [ ] 1-day/week split
- [ ] 6-day/week split (limited rest options)
- [ ] 4 parts with various rest placements
- [ ] Empty exercise list
- [ ] 10+ exercise sessions
- [ ] Duplicate part names
- [ ] Duplicate split names
- [ ] Import incompatible split

---

## Future Enhancements (Post-MVP)

### **Phase 2 Features**
- [ ] Duplicate existing split as template
- [ ] Split templates library (community shares)
- [ ] Progressive overload suggestions
- [ ] Exercise substitution recommendations
- [ ] Video previews in exercise picker

### **Trainer-Client Features**
- [ ] Cloud sync for splits (Firebase/CloudKit)
- [ ] Trainer account type
- [ ] Send split to client
- [ ] Split versioning and updates
- [ ] Usage analytics
- [ ] Client feedback integration

---

## Summary of Key Decisions

✅ **Max 4 parts** (best practice for recovery)
✅ **3-10 exercises per part** (prevents ineffective or excessive sessions)
✅ **3-tier validation** (hard blocks, soft warnings, guidance)
✅ **Smart rest day logic** (conditional based on frequency/parts)
✅ **Relevance sorting** (appropriate exercises shown first)
✅ **Part naming suggestions** (reduces friction)
✅ **Week preview** (helps users understand cycling)
✅ **Duration estimates** (prevents overly long sessions)
✅ **Balance warnings** (educational, non-blocking)
✅ **Future-proof architecture** (ready for trainer-client features)

This comprehensive plan provides a **production-ready, maintainable, and user-friendly implementation** that aligns with training science best practices while maintaining flexibility for advanced users. 🎯
