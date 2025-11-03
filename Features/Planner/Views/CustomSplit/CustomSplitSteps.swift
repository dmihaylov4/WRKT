//
//  CustomSplitSteps.swift
//  WRKT
//
//  Custom split creation steps

import SwiftUI

// MARK: - Custom TextField Style

struct PlannerTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .foregroundStyle(.white)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Custom Split Step 1: Name and Parts

struct CustomSplitStep1NameAndParts: View {
    @ObservedObject var config: PlanConfig
    @FocusState private var focusedField: CustomSplitField?

    enum CustomSplitField: Hashable {
        case splitName
        case partName(Int)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Split Name
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name Your Split")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    Text("Give your custom training split a memorable name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    TextField("e.g., My Push Pull Legs", text: $config.customSplitName)
                        .textFieldStyle(PlannerTextFieldStyle())
                        .focused($focusedField, equals: .splitName)
                        .padding(.horizontal)

                    Text("\(config.customSplitName.count)/\(PlannerConstants.CustomSplit.maxNameLength) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Divider().padding(.vertical)

                // Number of Parts
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Split Structure")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    Text("How many different workout parts?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ForEach([2, 3, 4], id: \.self) { count in
                        PartsOptionButton(
                            number: count,
                            isSelected: config.numberOfParts == count
                        ) {
                            config.numberOfParts = count
                            config.partNames = Array(repeating: "", count: count)
                            config.partExercises = [:]
                            focusedField = nil // Dismiss keyboard
                        }
                    }
                }

                // Part Names (if parts selected)
                if config.numberOfParts > 0 {
                    Divider().padding(.vertical)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Name Your Workout Parts")
                            .font(.title2.bold())
                            .padding(.horizontal)

                        ForEach(0..<config.numberOfParts, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Part \(index + 1)")
                                    .font(.headline)

                                TextField("e.g., Push, Pull, Legs", text: Binding(
                                    get: { config.partNames[safe: index] ?? "" },
                                    set: { newValue in
                                        if index < config.partNames.count {
                                            config.partNames[index] = newValue
                                        }
                                    }
                                ))
                                .textFieldStyle(PlannerTextFieldStyle())
                                .focused($focusedField, equals: .partName(index))
                            }
                            .padding(.horizontal)
                        }

                        // Quick fill
                        if config.numberOfParts == 3 {
                            Button {
                                config.partNames = ["Push", "Pull", "Legs"]
                                focusedField = nil // Dismiss keyboard
                            } label: {
                                Text("Quick Fill: Push / Pull / Legs")
                                    .font(.caption)
                                    .foregroundStyle(DS.Theme.accent)
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            focusedField = nil // Dismiss keyboard when tapping outside
        }
    }
}

// MARK: - Parts Option Button

struct PartsOptionButton: View {
    let number: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("\(number)-Part Split")
                    .font(.headline)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Palette.marone)
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

// MARK: - Custom Split Step 2: Add Exercises

struct CustomSplitStep2AddExercises: View {
    @ObservedObject var config: PlanConfig
    @EnvironmentObject var exerciseRepo: ExerciseRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Exercises")
                    .font(.title2.bold())
                    .padding(.horizontal)

                Text("Select \(PlannerConstants.ExerciseLimits.minPerPart)-\(PlannerConstants.ExerciseLimits.maxPerPart) exercises for each workout part")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(config.partNames, id: \.self) { partName in
                    ExercisePickerCard(config: config, partName: partName)
                }

                Spacer()
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Exercise Picker Card

struct ExercisePickerCard: View {
    @ObservedObject var config: PlanConfig
    let partName: String
    @State private var showPicker = false

    private var exercises: [ExerciseTemplate] {
        config.partExercises[partName] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(partName)
                    .font(.headline)

                Spacer()

                Text("\(exercises.count)/\(PlannerConstants.ExerciseLimits.maxPerPart)")
                    .font(.caption)
                    .foregroundStyle(exercises.count >= PlannerConstants.ExerciseLimits.minPerPart ? DS.Theme.accent : .orange)
            }

            if !exercises.isEmpty {
                ForEach(exercises) { exercise in
                    HStack {
                        Text(exercise.exerciseName)
                            .font(.subheadline)

                        Spacer()

                        Text("\(exercise.sets) × \(exercise.reps)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                showPicker = true
            } label: {
                Label(exercises.isEmpty ? "Add Exercises" : "Edit Exercises",
                      systemImage: exercises.isEmpty ? "plus.circle.fill" : "pencil.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(DS.Palette.marone.opacity(0.1))
                    .foregroundStyle(DS.Palette.marone)
                    .cornerRadius(10)
            }
            .sheet(isPresented: $showPicker) {
                CustomSplitExercisePicker(config: config, partName: partName)
            }
        }
        .padding()
        .background(DS.Semantic.surface)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Custom Split Step 3: Frequency and Rest

struct CustomSplitStep3FrequencyAndRest: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Training Frequency
                VStack(alignment: .leading, spacing: 12) {
                    Text("Training Frequency")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    Text("How many days per week will you train?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ForEach([3, 4, 5, 6], id: \.self) { days in
                        Button {
                            config.trainingDaysPerWeek = days
                        } label: {
                            HStack {
                                Text("\(days) days per week")
                                    .font(.headline)

                                Spacer()

                                if config.trainingDaysPerWeek == days {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DS.Palette.marone)
                                }
                            }
                            .padding()
                            .background(config.trainingDaysPerWeek == days ? DS.Palette.marone.opacity(0.1) : DS.Semantic.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(config.trainingDaysPerWeek == days ? DS.Palette.marone : Color.clear, lineWidth: 2)
                            )
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                Divider().padding(.vertical)

                // Rest Days
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rest Days")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    Text("How should rest days be distributed?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    RestDayOptionCard(
                        icon: "calendar",
                        title: "After Each Workout",
                        description: "Alternate training and rest days",
                        isSelected: config.restDayPlacement == .afterEachWorkout
                    ) {
                        config.restDayPlacement = .afterEachWorkout
                        onAutoAdvance()
                    }

                    RestDayOptionCard(
                        icon: "calendar.badge.clock",
                        title: "Weekends",
                        description: "Train weekdays, rest weekends",
                        isSelected: config.restDayPlacement == .weekends
                    ) {
                        config.restDayPlacement = .weekends
                        onAutoAdvance()
                    }
                }

                Spacer()
            }
            .padding(.vertical)
        }
    }
}
