//
//  PlannerSetupCarouselView.swift
//  WRKT
//
//  Multi-step carousel coordinator for setting up workout plans

import SwiftUI
import Combine
import SwiftData
import OSLog

struct PlannerSetupCarouselView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var context

    @State private var currentStep = 0
    @StateObject private var config = PlanConfig()
    @State private var showExistingSplitAlert = false
    @State private var existingSplit: WorkoutSplit?
    @State private var errorAlert: ErrorAlert?
    @State private var isEditingExistingSplit = false
    @State private var selectedDayIndex = 0

    private let totalSteps = PlannerConstants.Steps.total

    struct ErrorAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                .tint(DS.Palette.marone)
                .padding(.horizontal)
                .padding(.top, 8)

            // Step indicator
            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Content
            Group {
                switch currentStep {
                case 0:
                    Step1ChooseSplit(config: config, onAutoAdvance: autoAdvance)
                case 1:
                    if config.isCreatingCustom {
                        CustomSplitStep1NameAndParts(config: config)
                    } else {
                        Step2TrainingFrequency(config: config, onAutoAdvance: autoAdvance)
                    }
                case 2:
                    if config.isCreatingCustom {
                        CustomSplitStep2AddExercises(config: config)
                    } else {
                        Step3RestDays(config: config, onAutoAdvance: autoAdvance)
                    }
                case 3:
                    if config.isCreatingCustom {
                        CustomSplitStep3FrequencyAndRest(config: config, onAutoAdvance: autoAdvance)
                    } else {
                        Step4CustomizeExercises(config: config, onAutoAdvance: autoAdvance, selectedDayIndex: $selectedDayIndex)
                    }
                case 4:
                    Step5ProgramLength(config: config, onAutoAdvance: autoAdvance)
                case 5:
                    Step6Review(config: config, onGenerate: generatePlan)
                default:
                    Step1ChooseSplit(config: config, onAutoAdvance: autoAdvance)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(.white.opacity(0.08))

            // Navigation buttons
            navigationButtons
        }
        .navigationTitle(isEditingExistingSplit ? "Edit Workout Plan" : "Create Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(currentStep > 0)
        .toolbar {
            if currentStep > 0 {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        handleBackNavigation()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Back")
                        }
                        .foregroundStyle(DS.Palette.marone)
                    }
                }
            }
        }
        .onAppear {
            checkForExistingSplit()
        }
        .alert("Active Plan Exists", isPresented: $showExistingSplitAlert) {
            Button("Replace with New Plan", role: .destructive) {
                isEditingExistingSplit = false
                existingSplit = nil
            }
            Button("Edit Current Split") {
                isEditingExistingSplit = true
                loadExistingSplitIntoConfig()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            if let split = existingSplit {
                Text("You already have an active plan: \"\(split.name)\". You can replace it, edit it, or cancel.")
            } else {
                Text("You already have an active plan. You can replace it, edit it, or cancel.")
            }
        }
        .alert(item: $errorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Spacer()

            // Show "Next" button when viewing or customizing exercises (step 3, not creating custom split)
            if currentStep == 3 && !config.isCreatingCustom && config.wantsToCustomize != nil {
                Button {
                    handleNextDayOrStep()
                } label: {
                    HStack(spacing: 8) {
                        Text(nextButtonTitle)
                            .font(.body.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(DS.Palette.marone)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DS.Palette.marone.opacity(0.15))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.Palette.marone, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            } else if currentStep < totalSteps - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(canProceed ? DS.Palette.marone : DS.Palette.marone.opacity(0.3))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canProceed)
            } else {
                Button {
                    generatePlan()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.body.weight(.semibold))
                        Text("Save Split")
                            .font(.body.weight(.semibold))
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 24)
                    .background(config.isValid ? DS.Palette.marone.opacity(0.15) : DS.Palette.marone.opacity(0.08))
                    .foregroundStyle(config.isValid ? DS.Palette.marone : DS.Palette.marone.opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(config.isValid ? DS.Palette.marone : DS.Palette.marone.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!config.isValid)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground).opacity(0),
                    Color(uiColor: .systemBackground).opacity(0.8),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Helper Functions

    private var nextButtonTitle: String {
        guard let template = config.selectedTemplate else { return "Next" }
        let totalDays = template.days.count
        return selectedDayIndex < totalDays - 1 ? "Next" : "Done"
    }

    private func handleNextDayOrStep() {
        guard let template = config.selectedTemplate else { return }
        let totalDays = template.days.count

        if selectedDayIndex < totalDays - 1 {
            // Move to next day
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedDayIndex += 1
            }
        } else {
            // Last day - advance to next step
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedDayIndex = 0 // Reset for next time
                currentStep += 1
            }
        }
    }

    private func handleBackNavigation() {
        // Handle day-by-day navigation within step 3
        if currentStep == 3 && !config.isCreatingCustom && config.wantsToCustomize != nil && selectedDayIndex > 0 {
            // Go back one day
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedDayIndex -= 1
            }
            return
        }

        // When going back from step 4 to step 3, reset day index to start
        if currentStep == 4 && !config.isCreatingCustom {
            selectedDayIndex = 0
        }

        // Reset customize choice when navigating back FROM step 3 TO step 2
        if currentStep == 3 && !config.isCreatingCustom && config.wantsToCustomize != nil {
            config.wantsToCustomize = nil
            selectedDayIndex = 0 // Reset day index
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep -= 1
        }
    }

    private func autoAdvance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + PlannerConstants.Timing.autoAdvanceDelay) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        }
    }

    private var canProceed: Bool {
        return PlanConfigValidator.canProceedFromStep(currentStep, config: config)
    }

    private func checkForExistingSplit() {
        do {
            let activeSplit = try dependencies.plannerStore.activeSplit()
            if let split = activeSplit {
                existingSplit = split
                showExistingSplitAlert = true
            }
        } catch {
            AppLogger.error("Error checking for existing split: \(error)", category: AppLogger.app)
        }
    }

    private func loadExistingSplitIntoConfig() {
        guard let split = existingSplit else { return }

        AppLogger.info("Loading existing split '\(split.name)' for editing", category: AppLogger.app)

        // Set start date to anchor date
        config.startDate = split.anchorDate

        // Count training days and rest days in one cycle
        let trainingDaysInCycle = split.planBlocks.filter { !$0.isRestDay }.count
        let totalDaysInCycle = split.planBlocks.count

        // Deduce training days per week based on cycle length
        // If cycle is 7 days, it's a full week
        // If cycle is less, training days = training days in cycle
        config.trainingDaysPerWeek = min(trainingDaysInCycle, 7)

        // Analyze rest day placement pattern
        config.restDayPlacement = analyzeRestDayPlacement(planBlocks: split.planBlocks)

        // Set a default program length (user can change this)
        config.programWeeks = 12

        // Try to match to a predefined template
        let predefinedTemplates = SplitTemplates.all
        let customTemplates = dependencies.customSplitStore.customSplits
        let allTemplates = predefinedTemplates + customTemplates

        // Match by name first
        if let matchedTemplate = allTemplates.first(where: { $0.name == split.name }) {
            config.selectedTemplate = matchedTemplate
            config.isCreatingCustom = matchedTemplate.isCustom

            if matchedTemplate.isCustom {
                // Load custom split details
                config.customSplitName = matchedTemplate.name
                config.numberOfParts = matchedTemplate.days.filter { !$0.isRestDay }.count
                config.partNames = matchedTemplate.days.filter { !$0.isRestDay }.map { $0.name }

                // Load exercises for each part
                for day in matchedTemplate.days where !day.isRestDay {
                    config.partExercises[day.name] = day.exercises
                }
            }

            // Load customized exercises if they differ from template
            for (index, block) in split.planBlocks.enumerated() where !block.isRestDay {
                if index < matchedTemplate.days.count {
                    let templateDay = matchedTemplate.days[index]
                    // Convert PlanBlockExercise to ExerciseTemplate
                    let currentExercises = block.exercises.map { blockEx -> ExerciseTemplate in
                        ExerciseTemplate(
                            exerciseID: blockEx.exerciseID,
                            exerciseName: blockEx.exerciseName,
                            sets: blockEx.sets,
                            reps: blockEx.reps,
                            startingWeight: blockEx.startingWeight,
                            progressionStrategy: blockEx.progressionStrategy
                        )
                    }
                    config.customizedDays[templateDay.id] = currentExercises
                }
            }
        } else {
            // No template match - treat as custom split
            config.isCreatingCustom = true
            config.customSplitName = split.name

            let workoutBlocks = split.planBlocks.filter { !$0.isRestDay }
            config.numberOfParts = workoutBlocks.count
            config.partNames = workoutBlocks.map { $0.dayName }

            // Load exercises for each part
            for block in workoutBlocks {
                let exercises = block.exercises.map { blockEx -> ExerciseTemplate in
                    ExerciseTemplate(
                        exerciseID: blockEx.exerciseID,
                        exerciseName: blockEx.exerciseName,
                        sets: blockEx.sets,
                        reps: blockEx.reps,
                        startingWeight: blockEx.startingWeight,
                        progressionStrategy: blockEx.progressionStrategy
                    )
                }
                config.partExercises[block.dayName] = exercises
            }
        }

        AppLogger.success("Loaded existing split configuration for editing", category: AppLogger.app)
    }

    private func analyzeRestDayPlacement(planBlocks: [PlanBlock]) -> PlanConfig.RestDayPlacement {
        guard !planBlocks.isEmpty else { return .weekends }

        // Find rest day indices
        let restDayIndices = planBlocks.enumerated().compactMap { index, block in
            block.isRestDay ? index : nil
        }

        guard !restDayIndices.isEmpty else {
            // No rest days
            return .afterEverySecondWorkout
        }

        // Check for weekends pattern (indices 5, 6 in 7-day cycle)
        if planBlocks.count == 7 && Set(restDayIndices) == Set([5, 6]) {
            return .weekends
        }

        // Check for after each workout pattern
        let workoutBlocks = planBlocks.filter { !$0.isRestDay }
        if restDayIndices.count == workoutBlocks.count {
            // Check if rest days alternate with workout days
            var isAlternating = true
            for i in 0..<planBlocks.count - 1 {
                if planBlocks[i].isRestDay == planBlocks[i + 1].isRestDay {
                    isAlternating = false
                    break
                }
            }
            if isAlternating {
                return .afterEachWorkout
            }
        }

        // Check for after every second workout pattern
        // This is more complex - look for pattern like: W W R W W R
        var workoutCount = 0
        var matchesPattern = true
        for block in planBlocks {
            if !block.isRestDay {
                workoutCount += 1
            } else {
                if workoutCount != 2 {
                    matchesPattern = false
                    break
                }
                workoutCount = 0
            }
        }
        if matchesPattern && workoutCount == 0 {
            return .afterEverySecondWorkout
        }

        // Fall back to custom pattern
        return .custom(restDayIndices)
    }

    private func generatePlan() {
        // If creating custom split, first create and save the template
        var template: SplitTemplate
        if config.isCreatingCustom {
            let days = config.partNames.map { partName -> DayTemplate in
                let exercises = config.partExercises[partName] ?? []
                return DayTemplate(
                    id: UUID().uuidString,
                    name: partName,
                    exercises: exercises,
                    isRestDay: false
                )
            }

            template = SplitTemplate(
                id: UUID().uuidString,
                name: config.customSplitName,
                shortName: String(config.customSplitName.prefix(3)).uppercased(),
                description: "Custom split with \(config.numberOfParts) parts",
                days: days,
                recommendedFrequency: config.numberOfParts,
                difficulty: .intermediate,
                focus: "Custom training",
                icon: "person.fill",
                isCustom: true,
                createdBy: "user",
                createdAt: Date(),
                lastModified: Date(),
                shareableID: UUID().uuidString,
                version: 1
            )

            do {
                try dependencies.customSplitStore.add(template)
            } catch {
                AppLogger.error("Failed to add custom split", error: error, category: AppLogger.app)
                errorAlert = ErrorAlert(
                    title: "Cannot Create Split",
                    message: error.localizedDescription
                )
                return
            }
        } else {
            guard let selectedTemplate = config.selectedTemplate else {
                errorAlert = ErrorAlert(
                    title: "No Template Selected",
                    message: "Please select a workout template to continue."
                )
                return
            }
            template = selectedTemplate
        }

        do {
            if let oldSplit = existingSplit {
                oldSplit.isActive = false
            }

            let planBlocks = try generatePlanBlocks(
                template: template,
                trainingDaysPerWeek: config.trainingDaysPerWeek,
                restDayPlacement: config.restDayPlacement
            )

            let plannerStore = dependencies.plannerStore
            let normalizedStartDate = Calendar.current.startOfDay(for: config.startDate)

            let split = WorkoutSplit(
                name: template.name,
                planBlocks: planBlocks,
                anchorDate: normalizedStartDate,
                reschedulePolicy: .strict
            )

            context.insert(split)
            try context.save()
            try plannerStore.generatePlannedWorkouts(for: split, days: config.programWeeks * 7)

            Haptics.soft()
            AppLogger.success("Generated \(config.programWeeks)-week plan: \(template.name)", category: AppLogger.app)
            dismiss()
        } catch {
            AppLogger.error("Failed to generate plan", error: error, category: AppLogger.app)
            errorAlert = ErrorAlert(
                title: "Plan Creation Failed",
                message: "Unable to create your workout plan. Please check your configuration and try again."
            )
        }
    }

    private func generatePlanBlocks(
        template: SplitTemplate,
        trainingDaysPerWeek: Int,
        restDayPlacement: PlanConfig.RestDayPlacement?
    ) throws -> [PlanBlock] {
        guard let placement = restDayPlacement else {
            throw NSError(domain: "PlanConfig", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rest day placement not set"])
        }

        var workoutBlocks = template.days.filter { !$0.isRestDay }.map { day -> PlanBlock in
            let exerciseTemplates = config.customizedDays[day.id] ?? day.exercises
            let planBlockExercises = exerciseTemplates.enumerated().map { index, template in
                PlanBlockExercise(
                    exerciseID: template.exerciseID,
                    exerciseName: template.exerciseName,
                    sets: template.sets,
                    reps: template.reps,
                    startingWeight: template.startingWeight,
                    progressionStrategy: template.progressionStrategy,
                    order: index
                )
            }
            return PlanBlock(dayName: day.name, exercises: planBlockExercises, isRestDay: false)
        }

        guard !workoutBlocks.isEmpty else {
            throw NSError(domain: "PlanConfig", code: -2, userInfo: [NSLocalizedDescriptionKey: "No workout days in template"])
        }

        // Use strategy pattern for rest day placement
        let strategy = RestDayStrategyFactory.strategy(for: placement)
        return strategy.generateWeek(workoutBlocks: workoutBlocks, trainingDaysPerWeek: trainingDaysPerWeek)
    }
}

// MARK: - Plan Configuration

class PlanConfig: ObservableObject {

    // MARK: - Common Configuration (Both Predefined & Custom)

    /// Number of training days per week (3-6)
    @Published var trainingDaysPerWeek: Int = 0

    /// How rest days should be distributed throughout the week
    @Published var restDayPlacement: RestDayPlacement?

    /// Total length of the program in weeks
    @Published var programWeeks: Int = 0

    /// Whether to include deload weeks every 4th week
    @Published var includeDeload: Bool = true

    /// When the plan should start
    @Published var startDate: Date = Calendar.current.startOfDay(for: .now)

    // MARK: - Workflow Type

    /// Whether user is creating a custom split vs using a predefined template
    @Published var isCreatingCustom: Bool = false

    // MARK: - Predefined Split Configuration

    /// The selected predefined split template (nil if creating custom)
    @Published var selectedTemplate: SplitTemplate?

    /// Whether user wants to customize exercises in the template
    @Published var wantsToCustomize: Bool?

    /// User's customized exercises by day ID (only if wantsToCustomize = true)
    @Published var customizedDays: [String: [ExerciseTemplate]] = [:]

    // MARK: - Custom Split Configuration

    /// Name of the custom split (e.g., "My Push Pull Legs")
    @Published var customSplitName: String = ""

    /// Number of parts in the split (2-4)
    @Published var numberOfParts: Int = 0

    /// Names of each part (e.g., ["Push", "Pull", "Legs"])
    @Published var partNames: [String] = []

    /// Exercises for each part by part name
    @Published var partExercises: [String: [ExerciseTemplate]] = [:]

    // MARK: - Rest Day Placement Options

    enum RestDayPlacement: Equatable {
        case afterEachWorkout
        case afterEverySecondWorkout
        case weekends
        case custom([Int]) // Day indices (0=Mon, 6=Sun)
    }

    // MARK: - Validation

    var isValid: Bool {
        return PlanConfigValidator.isValidConfiguration(self)
    }

    func availableRestOptions() -> [RestDayPlacement] {
        return PlanConfigValidator.availableRestOptions(for: self)
    }
}
