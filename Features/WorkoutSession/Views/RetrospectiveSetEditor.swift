//
//  RetrospectiveSetEditor.swift
//  WRKT
//
//  Editor for retrospective workout sets
//

import SwiftUI

struct RetrospectiveSetEditor: View {
    @Binding var entry: WorkoutEntry
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: WorkoutStoreV2
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var step: Double { unit == .kg ? 2.5 : 5 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Sets section
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Sets (\(entry.sets.count))")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(DS.Semantic.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()

                        // Set rows
                        ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                            RetrospectiveSetRow(
                                setNumber: index + 1,
                                set: binding(for: index),
                                unit: unit,
                                step: step,
                                onDelete: {
                                    entry.sets.remove(at: index)
                                }
                            )

                            if index < entry.sets.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }

                        // Add set button
                        Button {
                            addSet()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Set")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundStyle(DS.Theme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(DS.Theme.cardTop)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
                }
                .padding(16)
            }
            .background(DS.Semantic.surface)
            .navigationTitle(entry.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func binding(for index: Int) -> Binding<SetInput> {
        $entry.sets[index]
    }

    private func addSet() {
        if let lastSet = entry.sets.last {
            entry.sets.append(SetInput(reps: lastSet.reps, weight: lastSet.weight, isCompleted: true))
        } else {
            entry.sets.append(SetInput(reps: 10, weight: 0, isCompleted: true))
        }
        Haptics.light()
    }
}

// MARK: - Retrospective Set Row

private struct RetrospectiveSetRow: View {
    let setNumber: Int
    @Binding var set: SetInput
    let unit: WeightUnit
    let step: Double
    let onDelete: () -> Void

    @State private var isEditingReps = false
    @State private var isEditingWeight = false
    @FocusState private var focusedField: Field?

    enum Field {
        case reps, weight
    }

    private var displayWeight: Double {
        unit == .kg ? set.weight : (set.weight * 2.20462)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Set \(setNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                // Delete button
                Button {
                    onDelete()
                    Haptics.light()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Input controls
            HStack(spacing: 16) {
                // Reps input
                VStack(spacing: 6) {
                    Text("REPS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)

                    HStack(spacing: 8) {
                        StepperButton(
                            systemName: "minus.circle.fill",
                            isEnabled: set.reps > 1
                        ) {
                            if set.reps > 1 {
                                set.reps -= 1
                                Haptics.light()
                            }
                        }

                        if isEditingReps {
                            TextField("", value: $set.reps, format: .number)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .reps)
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(minWidth: 40)
                        } else {
                            Text("\(set.reps)")
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(minWidth: 40)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isEditingReps = true
                                    focusedField = .reps
                                }
                        }

                        StepperButton(
                            systemName: "plus.circle.fill",
                            isEnabled: true
                        ) {
                            set.reps += 1
                            Haptics.light()
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(DS.Semantic.border)
                    .frame(width: 1, height: 60)

                // Weight input
                VStack(spacing: 6) {
                    Text("WEIGHT (\(unit.rawValue))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)

                    HStack(spacing: 8) {
                        StepperButton(
                            systemName: "minus.circle.fill",
                            isEnabled: displayWeight > 0
                        ) {
                            let newWeight = max(0, displayWeight - step)
                            let kg = (unit == .kg) ? newWeight : newWeight / 2.20462
                            set.weight = kg
                            Haptics.light()
                        }

                        if isEditingWeight {
                            TextField("", value: Binding(
                                get: { displayWeight },
                                set: { newValue in
                                    let kg = (unit == .kg) ? newValue : newValue / 2.20462
                                    set.weight = kg
                                }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 70, maxWidth: 100)
                        } else {
                            Text(String(format: "%.1f", displayWeight))
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(minWidth: 70, maxWidth: 100)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isEditingWeight = true
                                    focusedField = .weight
                                }
                        }

                        StepperButton(
                            systemName: "plus.circle.fill",
                            isEnabled: true
                        ) {
                            let newWeight = displayWeight + step
                            let kg = (unit == .kg) ? newWeight : newWeight / 2.20462
                            set.weight = kg
                            Haptics.light()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                isEditingReps = false
                isEditingWeight = false
            }
        }
    }
}

// MARK: - Stepper Button

private struct StepperButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    @GestureState private var isPressingDown = false
    @State private var longPressTimer: Timer?

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(isEnabled ? DS.Theme.accent : DS.Semantic.textSecondary.opacity(0.3))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressingDown) { _, state, _ in
                        state = true
                    }
                    .onChanged { _ in
                        if isEnabled && longPressTimer == nil {
                            // First action on press
                            action()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()

                            // Start timer after brief delay for long press
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if isPressingDown && isEnabled {
                                    startLongPress()
                                }
                            }
                        }
                    }
            )
            .onChange(of: isPressingDown) { _, pressing in
                if !pressing {
                    stopLongPress()
                }
            }
            .onDisappear { stopLongPress() }
    }

    private func startLongPress() {
        guard longPressTimer == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Repeat action every 0.1 seconds while holding
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if isEnabled {
                action()
            } else {
                stopLongPress()
            }
        }
    }

    private func stopLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
}
