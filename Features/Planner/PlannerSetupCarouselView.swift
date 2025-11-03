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
                        Step4CustomizeExercises(config: config, onAutoAdvance: autoAdvance)
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
        .navigationTitle("Create Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkForExistingSplit()
        }
        .alert("Active Plan Exists", isPresented: $showExistingSplitAlert) {
            Button("Replace with New Plan", role: .destructive) {
                existingSplit = nil
            }
            Button("Keep Current Plan", role: .cancel) {
                dismiss()
            }
        } message: {
            if let split = existingSplit {
                Text("You already have an active plan: \"\(split.name)\". Creating a new plan will replace it.")
            } else {
                Text("You already have an active plan. Creating a new plan will replace it.")
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
            if currentStep > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DS.Palette.marone)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Show "Done" button when customizing exercises
            if currentStep == 3 && config.wantsToCustomize == true {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep += 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Done")
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
                        Text("Import to Calendar")
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
