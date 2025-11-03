//
//  ExerciseEditSheet.swift
//  WRKT
//
//  Sheet for editing exercise parameters

import SwiftUI

struct ExerciseEditSheet: View {
    let exercise: ExerciseTemplate
    let onSave: (Int, Int, Double?) -> Void

    @State private var sets: Int
    @State private var reps: Int
    @State private var weight: Double?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(exercise: ExerciseTemplate, onSave: @escaping (Int, Int, Double?) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _sets = State(initialValue: exercise.sets)
        _reps = State(initialValue: exercise.reps)
        _weight = State(initialValue: exercise.startingWeight)
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
                    TextField("Weight (optional)", value: $weight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
                        onSave(sets, reps, weight)
                    }
                    .fontWeight(.bold)
                }

                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        isFocused = false
                    }
                }
            }
        }
    }
}
