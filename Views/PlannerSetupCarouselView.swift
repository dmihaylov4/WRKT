//
//  PlannerSetupCarouselView.swift
//  WRKT
//
//  Multi-step carousel for setting up workout plans

import SwiftUI
import Combine
import SwiftData

struct PlannerSetupCarouselView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var context

    @State private var currentStep = 0
    @StateObject private var config = PlanConfig()
    @State private var showExistingSplitAlert = false
    @State private var existingSplit: WorkoutSplit?

    private let totalSteps = 6

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
                    Step1ChooseSplit(config: config) {
                        // Auto-advance callback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                case 1:
                    Step2TrainingFrequency(config: config) {
                        // Auto-advance callback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                case 2:
                    Step3RestDays(config: config) {
                        // Auto-advance callback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                case 3:
                    Step4CustomizeExercises(config: config) {
                        // Auto-advance callback for when user chooses "Use Defaults"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                case 4:
                    Step5ProgramLength(config: config) {
                        // Auto-advance callback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                case 5:
                    Step6Review(config: config, onGenerate: generatePlan)
                default:
                    Step1ChooseSplit(config: config) {
                        // Auto-advance callback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
                .background(.white.opacity(0.08))
            // Navigation buttons
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
        .navigationTitle("Create Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkForExistingSplit()
        }
        .alert("Active Plan Exists", isPresented: $showExistingSplitAlert) {
            Button("Replace with New Plan", role: .destructive) {
                // User confirmed - proceed with current flow
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
    }

    private var canProceed: Bool {
        let result: Bool
        switch currentStep {
        case 0: result = config.selectedTemplate != nil
        case 1: result = config.trainingDaysPerWeek > 0
        case 2: result = config.restDayPlacement != nil
        case 3: result = config.wantsToCustomize != nil // Can proceed once user has made a choice
        case 4: result = config.programWeeks > 0
        default: result = true
        }
        print("📊 Step \(currentStep) - canProceed: \(result), selectedTemplate: \(config.selectedTemplate?.name ?? "none")")
        return result
    }

    private func checkForExistingSplit() {
        do {
            let activeSplit = try dependencies.plannerStore.activeSplit()
            if let split = activeSplit {
                existingSplit = split
                showExistingSplitAlert = true
            }
        } catch {
            print("❌ Error checking for existing split: \(error)")
        }
    }

    private func generatePlan() {
        guard let template = config.selectedTemplate else { return }

        do {
            // Deactivate any existing active split first
            if let oldSplit = existingSplit {
                oldSplit.isActive = false
            }

            // Convert template days to PlanBlocks with rest days interspersed
            let planBlocks = try generatePlanBlocks(
                template: template,
                trainingDaysPerWeek: config.trainingDaysPerWeek,
                restDayPlacement: config.restDayPlacement
            )

            // Debug: Log the plan blocks
            print("📋 Generated \(planBlocks.count) blocks for \(config.trainingDaysPerWeek) training days:")
            for (index, block) in planBlocks.enumerated() {
                print("  Day \(index): \(block.isRestDay ? "Rest" : block.dayName)")
            }

            // Get PlannerStore instance
            let plannerStore = dependencies.plannerStore

            // Ensure start date is normalized to start of day
            let normalizedStartDate = Calendar.current.startOfDay(for: config.startDate)
            print("📅 Start date: \(normalizedStartDate.formatted(date: .abbreviated, time: .omitted))")

            // Create the split with user-selected start date
            let split = WorkoutSplit(
                name: template.name,
                planBlocks: planBlocks,
                anchorDate: normalizedStartDate,
                reschedulePolicy: .strict
            )

            context.insert(split)
            try context.save()

            // Generate planned workouts for the next programWeeks
            try plannerStore.generatePlannedWorkouts(for: split, days: config.programWeeks * 7)

            print("✅ Successfully created workout plan: \(template.name)")
            dismiss()
        } catch {
            print("❌ Failed to generate plan: \(error)")
        }
    }

    /// Generate plan blocks with rest days properly interspersed
    private func generatePlanBlocks(
        template: SplitTemplate,
        trainingDaysPerWeek: Int,
        restDayPlacement: PlanConfig.RestDayPlacement?
    ) throws -> [PlanBlock] {
        var blocks: [PlanBlock] = []

        // Convert template days to plan blocks, using customized exercises if available
        let workoutBlocks = template.days.map { dayTemplate in
            let exercises = config.customizedDays[dayTemplate.id] ?? dayTemplate.exercises

            return PlanBlock(
                dayName: dayTemplate.name,
                exercises: exercises.enumerated().map { index, ex in
                    PlanBlockExercise(
                        exerciseID: ex.exerciseID,
                        exerciseName: ex.exerciseName,
                        sets: ex.sets,
                        reps: ex.reps,
                        startingWeight: ex.startingWeight,
                        progressionStrategy: ex.progressionStrategy,
                        order: index
                    )
                },
                isRestDay: false
            )
        }

        // Add rest days based on placement strategy
        guard let placement = restDayPlacement else {
            // No rest day placement specified, just return the workout blocks
            return workoutBlocks
        }

        switch placement {
        case .afterEachWorkout:
            // Distribute workouts and rest days evenly throughout the week
            // Pattern: workout -> rest -> workout -> rest, etc.
            var workoutIndex = 0
            var workoutsAdded = 0
            let totalRestDays = 7 - trainingDaysPerWeek

            // Simple alternating pattern
            while blocks.count < 7 {
                if workoutsAdded < trainingDaysPerWeek {
                    // Add workout
                    blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
                    workoutIndex += 1
                    workoutsAdded += 1

                    // Add rest after workout if we have rest days remaining and space in the week
                    let restDaysAdded = blocks.count - workoutsAdded
                    if restDaysAdded < totalRestDays && blocks.count < 7 {
                        blocks.append(PlanBlock(dayName: "Rest", exercises: [], isRestDay: true))
                    }
                } else {
                    // Fill remaining days with rest
                    blocks.append(PlanBlock(dayName: "Rest", exercises: [], isRestDay: true))
                }
            }

        case .weekends:
            // Build a 7-day week: train on weekdays, rest on weekends
            // Days 0-4 are Mon-Fri (training), 5-6 are Sat-Sun (rest)
            var workoutIndex = 0

            for dayIndex in 0..<7 {
                if dayIndex < 5 && workoutIndex < trainingDaysPerWeek {
                    // Weekday - add workout
                    blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
                    workoutIndex += 1
                } else {
                    // Weekend or excess weekday - add rest
                    blocks.append(PlanBlock(dayName: "Rest", exercises: [], isRestDay: true))
                }
            }

        case .custom(let restDayIndices):
            // Build a 7-day week with custom rest days
            var workoutIndex = 0
            for dayIndex in 0..<7 {
                if restDayIndices.contains(dayIndex) {
                    blocks.append(PlanBlock(dayName: "Rest", exercises: [], isRestDay: true))
                } else if workoutIndex < trainingDaysPerWeek {
                    blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
                    workoutIndex += 1
                } else {
                    // More rest days than planned
                    blocks.append(PlanBlock(dayName: "Rest", exercises: [], isRestDay: true))
                }
            }
        }

        return blocks
    }
}

// MARK: - Plan Configuration

class PlanConfig: ObservableObject {
    @Published var selectedTemplate: SplitTemplate?
    @Published var trainingDaysPerWeek: Int = 0
    @Published var restDayPlacement: RestDayPlacement?
    @Published var wantsToCustomize: Bool? = nil // nil = not chosen, true = customize, false = use defaults
    @Published var customizedDays: [String: [ExerciseTemplate]] = [:] // dayID -> exercises
    @Published var programWeeks: Int = 0 // Don't pre-select - let user choose
    @Published var includeDeload: Bool = true
    @Published var startDate: Date = Calendar.current.startOfDay(for: .now) // Default to today

    enum RestDayPlacement: Equatable {
        case afterEachWorkout
        case weekends
        case custom([Int]) // Day indices (0=Mon, 6=Sun)
    }

    var isValid: Bool {
        selectedTemplate != nil &&
        trainingDaysPerWeek > 0 &&
        restDayPlacement != nil &&
        wantsToCustomize != nil &&
        programWeeks > 0
    }
}

// MARK: - Step 1: Choose Split

private struct Step1ChooseSplit: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your training split")
                    .font(.title2.bold())
                    .padding(.horizontal)

                Text("Select a program that matches your goals and schedule.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(SplitTemplates.all) { template in
                    SplitTemplateCard(
                        template: template,
                        isSelected: config.selectedTemplate?.id == template.id
                    ) {
                        print("🎯 Selected template: \(template.name)")
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config.selectedTemplate = template
                            // Don't pre-select training days - let user choose
                        }
                        // Auto-advance to next step
                        onAutoAdvance()
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, 20) // Extra padding at bottom to prevent cutoff
        }
        .scrollIndicators(.hidden)
    }
}

private struct SplitTemplateCard: View {
    let template: SplitTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundStyle(DS.Palette.marone)
                        .frame(width: 44, height: 44)
                        .background(DS.Palette.marone.opacity(0.1), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Label("\(template.recommendedFrequency) days/week", systemImage: "calendar")
                            Text("•")
                            Text(template.difficulty.rawValue)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DS.Palette.marone)
                    }
                }

                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label(template.focus, systemImage: "target")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(template.days.count) workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(isSelected ? DS.Palette.marone.opacity(0.1) : DS.Semantic.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.Palette.marone : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// MARK: - Step 2: Training Frequency

private struct Step2TrainingFrequency: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    private var availableFrequencies: [Int] {
        guard let template = config.selectedTemplate else { return [3, 4, 5, 6] }

        // PPL can be 3x or 6x
        if template.id == "ppl" { return [3, 6] }

        // Upper/Lower is typically 4x (2 upper, 2 lower)
        if template.id == "upper-lower" { return [2, 4] }

        // Full body can be 2-4x
        if template.id == "full-body" { return [2, 3, 4] }

        // Bro split is typically 5x
        if template.id == "bro-split" { return [5, 6] }

        return [3, 4, 5, 6]
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How many days per week?")
                    .font(.title2.bold())

                Text("Choose how often you want to train each week.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                ForEach(availableFrequencies, id: \.self) { days in
                    FrequencyButton(
                        days: days,
                        isSelected: config.trainingDaysPerWeek == days,
                        onTap: {
                            config.trainingDaysPerWeek = days
                        },
                        onAutoAdvance: onAutoAdvance
                    )
                }
            }
            .padding(.horizontal)

            if config.trainingDaysPerWeek > 0 {
                VStack(spacing: 8) {
                    Text("Rest days: \(7 - config.trainingDaysPerWeek) per week")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let template = config.selectedTemplate {
                        Text(frequencyNote(for: template, days: config.trainingDaysPerWeek))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }

    private func frequencyNote(for template: SplitTemplate, days: Int) -> String {
        if template.id == "ppl" && days == 6 {
            return "Running PPL twice per week for maximum growth"
        } else if template.id == "ppl" && days == 3 {
            return "Each muscle group trained once per week"
        } else if template.id == "upper-lower" && days == 4 {
            return "Upper and lower body each trained twice per week"
        }
        return "Balanced training frequency"
    }
}

private struct FrequencyButton: View {
    let days: Int
    let isSelected: Bool
    let onTap: () -> Void
    var onAutoAdvance: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onTap()
            // Auto-advance after selection
            if let advance = onAutoAdvance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    advance()
                }
            }
        }) {
            VStack(spacing: 8) {
                Text("\(days)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .primary)

                Text(days == 1 ? "day" : "days")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(isSelected ? DS.Palette.marone.opacity(0.12) : DS.Semantic.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? DS.Palette.marone : Color.gray.opacity(0.2), lineWidth: isSelected ? 2.5 : 1.5)
            )
            .shadow(color: isSelected ? DS.Palette.marone.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3: Rest Days

private struct Step3RestDays: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("When do you want rest days?")
                    .font(.title2.bold())

                Text("Choose how to schedule your recovery days.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            VStack(spacing: 16) {
                RestDayOptionCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "After Each Workout",
                    description: "Alternate between training and rest days for maximum recovery",
                    isSelected: config.restDayPlacement == .afterEachWorkout
                ) {
                    config.restDayPlacement = .afterEachWorkout
                    onAutoAdvance()
                }

                RestDayOptionCard(
                    icon: "calendar.badge.clock",
                    title: "Weekends",
                    description: "Rest on Saturday and Sunday, train weekdays",
                    isSelected: config.restDayPlacement == .weekends
                ) {
                    config.restDayPlacement = .weekends
                    onAutoAdvance()
                }
            }
            .padding(.horizontal)

            if let placement = config.restDayPlacement {
                VStack(spacing: 8) {
                    Text(restDayDescription(for: placement))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }

    private func restDayDescription(for placement: PlanConfig.RestDayPlacement) -> String {
        switch placement {
        case .afterEachWorkout:
            return "You'll have \(7 - config.trainingDaysPerWeek) rest days alternating with your \(config.trainingDaysPerWeek) training days"
        case .weekends:
            return "Training Monday-Friday, resting on weekends"
        case .custom:
            return "Custom rest day schedule"
        }
    }
}

private struct RestDayOptionCard: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(DS.Palette.marone)
                    .frame(width: 50, height: 50)
                    .background(DS.Palette.marone.opacity(isSelected ? 0.15 : 0.1), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Always reserve space for checkmark to prevent text shifting
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Palette.marone)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding()
            .background(isSelected ? DS.Palette.marone.opacity(0.1) : DS.Semantic.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.Palette.marone : Color.gray.opacity(0.3), lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Customize Exercises

private struct Step4CustomizeExercises: View {
    @ObservedObject var config: PlanConfig
    @EnvironmentObject var repo: ExerciseRepository
    let onAutoAdvance: () -> Void

    @State private var selectedDayIndex: Int = 0
    @StateObject private var searchVM = ExerciseSearchVM()

    var body: some View {
        VStack(spacing: 0) {
            // Show choice screen if user hasn't chosen yet
            if config.wantsToCustomize == nil {
                customizeChoiceScreen
            } else if config.wantsToCustomize == true {
                // Show customization interface with Done button
                customizationInterface
            } else {
                // User chose defaults - show confirmation (this state shouldn't be visible as we auto-advance)
                defaultsConfirmation
            }
        }
    }

    // MARK: - Choice Screen
    private var customizeChoiceScreen: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize exercises?")
                    .font(.title2.bold())

                Text("You can use the default exercises or customize them to your preferences.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            VStack(spacing: 16) {
                RestDayOptionCard(
                    icon: "checkmark.circle",
                    title: "Use Default Exercises",
                    description: "Start with the recommended exercises for this split",
                    isSelected: config.wantsToCustomize == false
                ) {
                    config.wantsToCustomize = false
                    onAutoAdvance()
                }

                RestDayOptionCard(
                    icon: "slider.horizontal.3",
                    title: "Customize Exercises",
                    description: "Modify exercises, sets, reps, and starting weights",
                    isSelected: config.wantsToCustomize == true
                ) {
                    config.wantsToCustomize = true
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
    }

    // MARK: - Defaults Confirmation
    private var defaultsConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(DS.Palette.marone)

            Text("Using Default Exercises")
                .font(.title3.bold())

            Text("You can always customize exercises later")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Customization Interface
    private var customizationInterface: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize exercises")
                    .font(.title2.bold())

                Text("Modify the exercises for each workout day.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 16)

            // Day tabs
            if let template = config.selectedTemplate {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(template.days.enumerated()), id: \.offset) { index, day in
                            DayTab(
                                title: day.name,
                                isSelected: selectedDayIndex == index
                            ) {
                                selectedDayIndex = index
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)

                // Exercise list for selected day
                let selectedDay = template.days[selectedDayIndex]

                ScrollView {
                    VStack(spacing: 12) {
                        // Current exercises
                        if let exercises = config.customizedDays[selectedDay.id] ?? Optional(selectedDay.exercises), !exercises.isEmpty {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                ExerciseRowEditable(
                                    exercise: exercise,
                                    onRemove: {
                                        removeExercise(dayID: selectedDay.id, index: index)
                                    },
                                    onEdit: { sets, reps, weight in
                                        updateExercise(dayID: selectedDay.id, index: index, sets: sets, reps: reps, weight: weight)
                                    }
                                )
                            }
                        }

                        // Add exercise button
                        Button {
                            searchVM.isShowingSearch = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add Exercise")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(DS.Palette.marone)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Palette.marone.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DS.Palette.marone.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $searchVM.isShowingSearch) {
            ExerciseSearchSheet(
                searchVM: searchVM,
                onSelect: { exercise in
                    guard let template = config.selectedTemplate else { return }
                    let selectedDay = template.days[selectedDayIndex]
                    addExercise(dayID: selectedDay.id, exercise: exercise)
                    searchVM.isShowingSearch = false
                }
            )
            .environmentObject(repo)
        }
    }

    private func addExercise(dayID: String, exercise: Exercise) {
        guard let template = config.selectedTemplate else { return }
        guard let dayTemplate = template.days.first(where: { $0.id == dayID }) else { return }

        var exercises = config.customizedDays[dayID] ?? dayTemplate.exercises

        let newExercise = ExerciseTemplate(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            sets: 3,
            reps: 10,
            startingWeight: nil,
            progressionStrategy: .linear(increment: 2.5)
        )

        exercises.append(newExercise)
        config.customizedDays[dayID] = exercises
    }

    private func removeExercise(dayID: String, index: Int) {
        guard let template = config.selectedTemplate else { return }
        guard let dayTemplate = template.days.first(where: { $0.id == dayID }) else { return }

        var exercises = config.customizedDays[dayID] ?? dayTemplate.exercises
        exercises.remove(at: index)
        config.customizedDays[dayID] = exercises
    }

    private func updateExercise(dayID: String, index: Int, sets: Int, reps: Int, weight: Double?) {
        guard let template = config.selectedTemplate else { return }
        guard let dayTemplate = template.days.first(where: { $0.id == dayID }) else { return }

        var exercises = config.customizedDays[dayID] ?? dayTemplate.exercises
        guard index < exercises.count else { return }

        // Create a new ExerciseTemplate with updated values
        let oldExercise = exercises[index]
        let updatedExercise = ExerciseTemplate(
            exerciseID: oldExercise.exerciseID,
            exerciseName: oldExercise.exerciseName,
            sets: sets,
            reps: reps,
            startingWeight: weight,
            progressionStrategy: oldExercise.progressionStrategy,
            notes: oldExercise.notes
        )

        exercises[index] = updatedExercise
        config.customizedDays[dayID] = exercises
    }
}

// MARK: - Day Tab
private struct DayTab: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.marone)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? DS.Palette.marone.opacity(0.15) : DS.Palette.marone.opacity(0.05))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? DS.Palette.marone : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise Row Editable
private struct ExerciseRowEditable: View {
    let exercise: ExerciseTemplate
    let onRemove: () -> Void
    let onEdit: (Int, Int, Double?) -> Void

    @State private var showEditSheet = false

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text("\(exercise.sets) sets × \(exercise.reps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let weight = exercise.startingWeight, weight > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.1f", weight)) kg")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.marone)
                        }
                    }
                }

                Spacer()

                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Palette.marone.opacity(0.7))

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(DS.Semantic.surface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditSheet) {
            ExerciseEditSheet(
                exercise: exercise,
                onSave: { sets, reps, weight in
                    onEdit(sets, reps, weight)
                    showEditSheet = false
                }
            )
        }
    }
}

// MARK: - Exercise Edit Sheet
private struct ExerciseEditSheet: View {
    let exercise: ExerciseTemplate
    let onSave: (Int, Int, Double?) -> Void

    @State private var sets: Int
    @State private var reps: Int
    @State private var weight: String
    @Environment(\.dismiss) private var dismiss

    init(exercise: ExerciseTemplate, onSave: @escaping (Int, Int, Double?) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _sets = State(initialValue: exercise.sets)
        _reps = State(initialValue: exercise.reps)
        _weight = State(initialValue: exercise.startingWeight.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Exercise") {
                    Text(exercise.exerciseName)
                        .font(.headline)
                }

                Section("Sets") {
                    Stepper("\(sets) sets", value: $sets, in: 1...10)
                }

                Section("Reps") {
                    Stepper("\(reps) reps", value: $reps, in: 1...30)
                }

                Section("Starting Weight (kg)") {
                    TextField("Weight (optional)", text: $weight)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let weightValue = Double(weight)
                        onSave(sets, reps, weightValue)
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

// MARK: - Exercise Search ViewModel
@MainActor
final class ExerciseSearchVM: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var debouncedSearch: String = ""
    @Published var isShowingSearch: Bool = false
    @Published var equipmentFilter: EquipBucket = .all
    @Published var movementFilter: MoveBucket = .all
    @Published private var lastFilters: ExerciseFilters?

    private var searchDebounceTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    var currentFilters: ExerciseFilters {
        ExerciseFilters(
            muscleGroup: nil,
            equipment: equipmentFilter,
            moveType: movementFilter,
            searchQuery: debouncedSearch
        )
    }

    init() {
        // Debounce search input (300ms delay)
        $searchQuery
            .removeDuplicates()
            .sink { [weak self] newSearch in
                self?.searchDebounceTask?.cancel()
                self?.searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    guard !(Task.isCancelled) else { return }
                    await MainActor.run {
                        self?.debouncedSearch = newSearch
                    }
                }
            }
            .store(in: &bag)
    }

    func loadInitialPage(repo: ExerciseRepository) async {
        if lastFilters == nil {
            await repo.loadFirstPage(with: currentFilters)
            lastFilters = currentFilters
        }
    }

    func handleFiltersChanged(repo: ExerciseRepository) async {
        if lastFilters != currentFilters {
            await repo.resetPagination(with: currentFilters)
            lastFilters = currentFilters
        }
    }

    /// Reset to default state (call when sheet closes)
    func reset() {
        searchQuery = ""
        debouncedSearch = ""
        equipmentFilter = .all
        movementFilter = .all
        lastFilters = nil
        searchDebounceTask?.cancel()
    }
}

// MARK: - Exercise Search Sheet
private struct ExerciseSearchSheet: View {
    @ObservedObject var searchVM: ExerciseSearchVM
    @EnvironmentObject var repo: ExerciseRepository
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Exercise) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filters
                FiltersBar(equip: $searchVM.equipmentFilter, move: $searchVM.movementFilter)

                Divider()

                // Exercise List
                List {
                    // Summary row
                    if repo.totalExerciseCount > 0 {
                        Text("\(repo.exercises.count) of \(repo.totalExerciseCount) exercises")
                            .font(.caption).foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }

                    // Exercise rows with pagination
                    ForEach(Array(repo.exercises.enumerated()), id: \.element.id) { index, ex in
                        Button {
                            onSelect(ex)
                        } label: {
                            PlannerExerciseRow(ex: ex)
                                .onAppear {
                                    // Load more when approaching end of list
                                    if shouldLoadMore(at: index) {
                                        Task {
                                            await repo.loadNextPage()
                                        }
                                    }
                                }
                        }
                        .listRowSeparator(.hidden)
                    }

                    // Loading indicator
                    if repo.isLoadingPage {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchVM.searchQuery, placement: .navigationBarDrawer(displayMode: .always))
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await searchVM.loadInitialPage(repo: repo)
            }
            .onChange(of: searchVM.currentFilters) { _, _ in
                Task {
                    await searchVM.handleFiltersChanged(repo: repo)
                }
            }
            .onDisappear {
                // Reset both search VM and repository to default state when sheet closes
                searchVM.reset()
                Task {
                    let defaultFilters = ExerciseFilters(
                        muscleGroup: nil,
                        equipment: .all,
                        moveType: .all,
                        searchQuery: ""
                    )
                    await repo.resetPagination(with: defaultFilters)
                }
            }
        }
    }

    /// Determine if we should load more exercises
    private func shouldLoadMore(at index: Int) -> Bool {
        guard repo.hasMorePages && !repo.isLoadingPage else { return false }
        return index >= repo.exercises.count - 10
    }
}

// MARK: - Planner Exercise Row (BodyBrowse style with + button)
private struct PlannerExerciseRow: View {
    let ex: Exercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ex.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    PremiumChip(
                        title: ex.equipBucket.rawValue,
                        icon: "dumbbell.fill",
                        color: .blue
                    )
                    PremiumChip(
                        title: ex.moveBucket.rawValue,
                        icon: ex.moveBucket == .pull ? "arrow.down.backward" :
                              ex.moveBucket == .push ? "arrow.up.forward" : "arrow.right",
                        color: chipColor(for: ex.moveBucket)
                    )
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(DS.Palette.marone)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func chipColor(for bucket: MoveBucket) -> Color {
        switch bucket {
        case .push: return .orange
        case .pull: return .green
        default: return .purple
        }
    }
}

// MARK: - Premium Chip Component (reused from BodyBrowse)
private struct PremiumChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                // Base dark background
                Capsule()
                    .fill(Color(hex: "#1A1A1A"))

                // Subtle color glow
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.4), color.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Step 5: Program Length

private struct Step5ProgramLength: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    private let weekOptions = [4, 6, 8, 12]

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How long should this program run?")
                    .font(.title2.bold())

                Text("Choose your training block length.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                ForEach(weekOptions, id: \.self) { weeks in
                    ProgramLengthButton(
                        weeks: weeks,
                        isSelected: config.programWeeks == weeks,
                        isRecommended: weeks == 8
                    ) {
                        config.programWeeks = weeks
                        onAutoAdvance()
                    }
                }
            }
            .padding(.horizontal)

            Toggle("Include deload weeks", isOn: $config.includeDeload)
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)

            if config.includeDeload {
                Text("Every 4th week will be a deload week at 70% volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }
}

private struct ProgramLengthButton: View {
    let weeks: Int
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text("\(weeks)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .primary)

                Text("weeks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .secondary)

                // Empty spacer that's visible only for recommended badge
                Group {
                    if isRecommended {
                        Text("RECOMMENDED")
                            .font(.caption2.bold())
                            .foregroundStyle(isSelected ? DS.Palette.marone : DS.Palette.marone.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isSelected ? DS.Palette.marone.opacity(0.15) : DS.Palette.marone.opacity(0.08),
                                in: Capsule()
                            )
                    } else {
                        Text(" ")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .opacity(0)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(isSelected ? DS.Palette.marone.opacity(0.12) : DS.Semantic.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? DS.Palette.marone : (isRecommended ? DS.Palette.marone.opacity(0.4) : Color.gray.opacity(0.2)),
                        lineWidth: isSelected ? 2.5 : (isRecommended ? 2 : 1.5)
                    )
            )
            .shadow(color: isSelected ? DS.Palette.marone.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 6: Review (Placeholder)

private struct Step6Review: View {
    @ObservedObject var config: PlanConfig
    let onGenerate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review your plan")
                    .font(.title2.bold())
                    .padding(.horizontal)

                // Start date picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("When do you want to start?")
                        .font(.headline)

                    DatePicker(
                        "Start Date",
                        selection: $config.startDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(DS.Palette.marone)
                }
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)

                // Configuration summary
                if let template = config.selectedTemplate {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(.headline)

                        Divider()

                        HStack {
                            Text("Split:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(template.name)
                                .bold()
                        }

                        HStack {
                            Text("Training Frequency:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(config.trainingDaysPerWeek) days/week")
                                .bold()
                        }

                        HStack {
                            Text("Rest Days:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(7 - config.trainingDaysPerWeek) days/week")
                                .bold()
                        }

                        HStack {
                            Text("Program Duration:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(config.programWeeks) weeks")
                                .bold()
                        }

                        if config.includeDeload {
                            HStack {
                                Text("Deload Weeks:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Every 4th week")
                                    .bold()
                            }
                        }

                        HStack {
                            Text("Start Date:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(config.startDate.formatted(date: .abbreviated, time: .omitted))
                                .bold()
                        }
                    }
                    .padding()
                    .background(DS.Semantic.surface)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.vertical)
        }
    }
}
