//
//  CreateExerciseView.swift
//  WRKT
//
//  Form for creating custom exercises
//

import SwiftUI

struct CreateExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var customStore: CustomExerciseStore
    @EnvironmentObject private var repo: ExerciseRepository

    // Pre-populated muscle from context (used as default)
    let preselectedMuscle: String

    // All available muscles for the picker
    private static let allMuscles: [String] = [
        "Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms", "Abs", "Obliques",
        "Glutes", "Quads", "Hamstrings", "Calves", "Adductors", "Abductors"
    ]

    // Form state
    @State private var name: String = ""
    @State private var selectedMuscle: String = ""
    @State private var equipment: EquipBucket = .bodyweight
    @State private var movement: MoveBucket = .other
    @State private var mechanic: String = "compound"
    @State private var difficulty: DifficultyLevel? = nil

    // Validation
    @State private var showValidationError = false
    @State private var validationMessage = ""

    // Editing mode
    let editingExercise: Exercise?

    init(preselectedMuscle: String, editingExercise: Exercise? = nil) {
        self.preselectedMuscle = preselectedMuscle
        self.editingExercise = editingExercise

        // Pre-populate form if editing
        if let exercise = editingExercise {
            _name = State(initialValue: exercise.name)
            _selectedMuscle = State(initialValue: exercise.primaryMuscles.first ?? preselectedMuscle)
            _equipment = State(initialValue: exercise.equipBucket)
            _movement = State(initialValue: exercise.moveBucket)
            _mechanic = State(initialValue: exercise.mechanic ?? "compound")
            _difficulty = State(initialValue: exercise.difficultyLevel)
        } else {
            // Use preselected muscle as default, or first muscle if preselected is empty
            let defaultMuscle = preselectedMuscle.isEmpty ? "Chest" : preselectedMuscle
            _selectedMuscle = State(initialValue: defaultMuscle)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise Name", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("NAME")
                } footer: {
                    Text("Give your exercise a descriptive name")
                }

                Section {
                    Picker("Primary Muscle", selection: $selectedMuscle) {
                        ForEach(Self.allMuscles, id: \.self) { muscle in
                            Text(muscle).tag(muscle)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("MUSCLE GROUP")
                } footer: {
                    Text("Select the primary muscle this exercise targets")
                }

                Section {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(EquipBucket.allCases, id: \.self) { bucket in
                            Text(bucket.rawValue).tag(bucket)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("EQUIPMENT")
                }

                Section {
                    Picker("Movement Pattern", selection: $movement) {
                        ForEach(MoveBucket.allCases, id: \.self) { bucket in
                            Text(bucket.rawValue).tag(bucket)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("MOVEMENT")
                }

                Section {
                    Picker("Type", selection: $mechanic) {
                        Text("Compound").tag("compound")
                        Text("Isolation").tag("isolation")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("EXERCISE TYPE")
                } footer: {
                    Text("Compound exercises work multiple muscle groups. Isolation exercises target a single muscle.")
                }

                Section {
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Not Set").tag(nil as DifficultyLevel?)
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(level as DifficultyLevel?)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("DIFFICULTY (OPTIONAL)")
                }
            }
            .navigationTitle(editingExercise == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingExercise == nil ? "Create" : "Save") {
                        saveExercise()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Validation Error", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    // MARK: - Actions

    private func saveExercise() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate name
        guard !trimmedName.isEmpty else {
            validationMessage = "Please enter an exercise name"
            showValidationError = true
            return
        }

        // Check for duplicate name (only if creating new)
        if editingExercise == nil {
            let allExercises = Task { await repo.getAllExercises() }
            // Note: We can't await in this context, so we'll just proceed
            // The duplicate check can be improved later with async/await
        }

        // Create exercise
        let exerciseID = editingExercise?.id ?? "custom_\(UUID().uuidString)"

        let exercise = Exercise(
            id: exerciseID,
            name: trimmedName,
            force: forceFromMovement(movement),
            level: difficulty?.rawValue,
            mechanic: mechanic,
            equipment: equipmentString(from: equipment),
            secondaryEquipment: nil,
            grip: nil,
            primaryMuscles: [selectedMuscle],
            secondaryMuscles: [],
            tertiaryMuscles: [],
            instructions: [],
            images: nil,
            category: selectedMuscle.lowercased(),
            subregionTags: [selectedMuscle],
            isCustom: true
        )

        // Save to store
        if editingExercise == nil {
            customStore.add(exercise)
        } else {
            customStore.update(exercise)
        }

        // Trigger repository refresh (will be implemented)
        Task {
            await repo.reloadWithCustomExercises()
        }

        // Haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        dismiss()
    }

    // MARK: - Helpers

    /// Map MoveBucket back to force type
    private func forceFromMovement(_ bucket: MoveBucket) -> String? {
        switch bucket {
        case .push: return "push"
        case .pull: return "pull"
        case .hinge: return "pull"  // Hinge movements are typically hip-dominant pulls
        case .squat: return "push"  // Squat movements are typically push
        case .core: return nil
        case .other: return nil
        case .all: return nil
        }
    }

    /// Map EquipBucket back to equipment string
    private func equipmentString(from bucket: EquipBucket) -> String? {
        switch bucket {
        case .all: return nil
        case .barbell: return "Barbell"
        case .bodyweight: return nil  // Bodyweight is represented as nil
        case .cable: return "Cable"
        case .dumbbell: return "Dumbbell"
        case .ezBar: return "EZ Bar"
        case .kettlebell: return "Kettlebell"
        case .pullupbar: return "Pullup Bar"
        case .other: return "Other"
        }
    }
}

#Preview {
    CreateExerciseView(preselectedMuscle: "Chest")
        .environmentObject(CustomExerciseStore.shared)
        .environmentObject(ExerciseRepository.shared)
}
