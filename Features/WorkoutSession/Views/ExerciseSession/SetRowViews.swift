//
//  SetRowViews.swift (Redesigned)
//  WRKT
//
//  Simplified set row components with clear active state
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Set Row Unified (Redesigned - Simple & Clear)

struct SetRowUnified: View {
    let index: Int
    @Binding var set: SetInput
    let unit: WeightUnit
    let exercise: Exercise
    let isActive: Bool
    let isGhost: Bool
    let hasActiveTimer: Bool  // Whether this set has an active rest timer
    let onDuplicate: () -> Void
    let onActivate: () -> Void
    let onLogSet: () -> Void  // New: explicit log action

    @EnvironmentObject private var store: WorkoutStoreV2
    @ObservedObject private var timerManager = RestTimerManager.shared

    private let defaultWorkingReps = 10
    private var step: Double { unit == .kg ? 2.5 : 5 }
    private var displayWeight: Double { unit == .kg ? set.weight : (set.weight * 2.20462) }

    @State private var isEditingReps = false
    @State private var isEditingWeight = false
    @FocusState private var focusedField: Field?

    enum Field {
        case reps
        case weight
    }

    // Tutorial frame capture callbacks (only for first set)
    var onSetTypeFrameCaptured: ((CGRect) -> Void)? = nil
    var onCarouselsFrameCaptured: ((CGRect) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header: Set number, status, and type
            HStack(spacing: 12) {
                // Set number with status indicator
                HStack(spacing: 6) {
                    if set.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    } else if isActive {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .strokeBorder(Theme.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    }

                    Text("Set \(index)")
                        .font(.subheadline.weight(isActive ? .bold : .semibold))
                        .foregroundStyle(
                            set.isCompleted && hasActiveTimer ? Theme.text.opacity(0.7) :
                            set.isCompleted ? Theme.secondary :
                            Theme.text
                        )
                }

                // Rest timer (if active for this set)
                if hasActiveTimer && timerManager.isRunning {
                    Button {
                        // Skip the rest timer
                        timerManager.skipTimer()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption.weight(.medium))
                            Text(formatTime(timerManager.remainingSeconds))
                                .font(.caption.monospacedDigit().weight(.semibold))
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Set type badge
                TagDotCycler(tag: $set.tag)
                    .disabled(set.isCompleted || isGhost)
                    .opacity(set.isCompleted ? 0.5 : 1.0)
                    .captureFrame(in: .global) { frame in
                        onSetTypeFrameCaptured?(frame)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .background(Theme.border)
                .padding(.horizontal, 16)

            // Input controls (optimized for one-handed use)
            HStack(spacing: 16) {
                // Reps input
                VStack(spacing: 2) {
                    Text("REPS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)

                    HStack(spacing: 8) {
                        StepperButton(
                            systemName: "minus.circle.fill",
                            isEnabled: !set.isCompleted && !isGhost && set.reps > 1,
                            color: Theme.accent.opacity(0.8)
                        ) {
                            if set.reps > 1 {
                                set.reps -= 1
                                set.autoWeight = false
                                set.isAutoGeneratedPlaceholder = false
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }

                        // Tap to type - Reps
                        if isEditingReps {
                            TextField("", value: $set.reps, format: .number)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .reps)
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.center)
                                .frame(minWidth: 40)
                                .onChange(of: set.reps) { _, _ in
                                    set.autoWeight = false
                                    set.isAutoGeneratedPlaceholder = false
                                }
                        } else {
                            Text("\(set.reps)")
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(set.isCompleted ? Theme.secondary : Theme.text)
                                .frame(minWidth: 40)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !set.isCompleted && !isGhost {
                                        isEditingReps = true
                                        focusedField = .reps
                                    }
                                }
                        }

                        StepperButton(
                            systemName: "plus.circle.fill",
                            isEnabled: !set.isCompleted && !isGhost,
                            color: Theme.accent
                        ) {
                            set.reps += 1
                            set.autoWeight = false
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1, height: 50)

                // Weight input
                VStack(spacing: 2) {
                    Text("WEIGHT (\(unit.rawValue))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)

                    HStack(spacing: 8) {
                        StepperButton(
                            systemName: "minus.circle.fill",
                            isEnabled: !set.isCompleted && !isGhost && displayWeight > 0,
                            color: Theme.accent.opacity(0.8)
                        ) {
                            let newWeight = max(0, displayWeight - step)
                            let kg = (unit == .kg) ? newWeight : newWeight / 2.20462
                            set.weight = kg
                            set.autoWeight = false
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }

                        // Tap to type - Weight
                        if isEditingWeight {
                            TextField("", value: Binding(
                                get: { displayWeight },
                                set: { newDisplay in
                                    let kg = (unit == .kg) ? newDisplay : newDisplay / 2.20462
                                    set.weight = max(0, kg)
                                }
                            ), format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.center)
                                .frame(minWidth: 60)
                                .onChange(of: set.weight) { _, _ in
                                    set.autoWeight = false
                                    set.isAutoGeneratedPlaceholder = false
                                }
                        } else {
                            Text(String(format: "%.1f", displayWeight))
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(set.isCompleted ? Theme.secondary : Theme.text)
                                .frame(minWidth: 60)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !set.isCompleted && !isGhost {
                                        isEditingWeight = true
                                        focusedField = .weight
                                    }
                                }
                        }

                        StepperButton(
                            systemName: "plus.circle.fill",
                            isEnabled: !set.isCompleted && !isGhost,
                            color: Theme.accent
                        ) {
                            let newWeight = displayWeight + step
                            let kg = (unit == .kg) ? newWeight : newWeight / 2.20462
                            set.weight = kg
                            set.autoWeight = false
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .captureFrame(in: .global) { frame in
                onCarouselsFrameCaptured?(frame)
            }

            // Active set: Show "Log This Set" button
            if isActive && !set.isCompleted && !isGhost {
                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)

                Button(action: onLogSet) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log This Set")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isActive ? 2 : 1)
        )
        .opacity(rowOpacity)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(.easeInOut(duration: 0.2), value: set.isCompleted)
        .animation(.easeInOut(duration: 0.2), value: hasActiveTimer)
        .onTapGesture {
            // Dismiss keyboard if editing, otherwise activate set
            if focusedField != nil {
                focusedField = nil
                isEditingReps = false
                isEditingWeight = false
            } else if !set.isCompleted {
                // Clear placeholder flag when user activates the set
                set.isAutoGeneratedPlaceholder = false
                onActivate()
            }
        }
        .onChange(of: focusedField) { _, newValue in
            // Reset editing states when focus changes
            if newValue != .reps {
                isEditingReps = false
            }
            if newValue != .weight {
                isEditingWeight = false
            }
        }
        .onAppear {
            seedFromMemoryIfNeeded()
            if set.tag == .working { applyWeightSuggestion() }
        }
    }

    private var backgroundColor: Color {
        if set.isCompleted && hasActiveTimer {
            // Completed with active timer - slightly highlighted to show it's "resting"
            return Theme.accent.opacity(0.08)
        } else if set.isCompleted {
            // Completed without timer - muted
            return Theme.accent.opacity(0.04)
        } else if isActive {
            // Active set
            return Theme.surface2
        } else {
            // Inactive set
            return Theme.surface
        }
    }

    private var borderColor: Color {
        if set.isCompleted && hasActiveTimer {
            // Completed with active timer - more prominent border
            return Theme.accent.opacity(0.5)
        } else if set.isCompleted {
            // Completed without timer - subtle border
            return Theme.accent.opacity(0.2)
        } else if isActive {
            // Active set - full accent border
            return Theme.accent
        } else {
            // Inactive set
            return Theme.border
        }
    }

    private var rowOpacity: Double {
        if set.isCompleted && hasActiveTimer {
            // Completed with timer - more visible to emphasize resting
            return 0.85
        } else if set.isCompleted {
            // Completed without timer - more muted
            return 0.65
        } else {
            // Active or inactive - full opacity
            return 1.0
        }
    }

    private func seedFromMemoryIfNeeded() {
        guard set.tag == .working, set.autoWeight, !set.didSeedFromMemory else { return }
        let looksEmpty = (set.reps == 0 && set.weight == 0)
        guard looksEmpty else { return }
        if let last = store.lastWorkingSet(exercise: exercise) {
            set.reps = last.reps
            set.weight = last.weightKg
            set.didSeedFromMemory = true
            return
        }
        set.reps = (set.reps > 0) ? set.reps : defaultWorkingReps
        set.didSeedFromMemory = true
    }

    private func applyWeightSuggestion() {
        guard set.autoWeight else { return }
        if set.reps <= 0 { set.reps = defaultWorkingReps }
        if let w = store.suggestedWorkingWeight(for: exercise, targetReps: set.reps) {
            let snapped: Double
            if unit == .kg {
                snapped = (w / step).rounded() * step
            } else {
                let lb = w * 2.20462
                snapped = ((lb / step).rounded() * step) / 2.20462
            }
            set.weight = max(0, snapped)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Tag Dot Cycler (Simplified)

struct TagDotCycler: View {
    @Binding var tag: SetTag

    var body: some View {
        Button {
            cycle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tag.color)
                    .frame(width: 8, height: 8)
                Text(tag.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tag.color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tag.color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
       
        .accessibilityLabel("Set type \(tag.label)")
    }

    private func cycle() {
        let all = SetTag.allCases
        if let idx = all.firstIndex(of: tag) {
            let next = all.index(after: idx)
            tag = next < all.endIndex ? all[next] : all.first!
        } else { tag = .working }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Stepper Button (Optimized for One-Handed Use)

private struct StepperButton: View {
    let systemName: String
    let isEnabled: Bool
    let color: Color
    let action: () -> Void

    @GestureState private var isPressingDown = false
    @State private var longPressTimer: Timer?

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(isEnabled ? color : Theme.secondary.opacity(0.3))
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
