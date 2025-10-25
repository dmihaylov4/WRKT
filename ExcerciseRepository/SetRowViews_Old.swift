//
//  SetRowViews.swift
//  WRKT
//
//  Set row components for exercise sessions
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Set Row Unified (Main Set Row with Scroll Wheels)

struct SetRowUnified: View {
    let index: Int
    @Binding var set: SetInput
    let unit: WeightUnit
    let exercise: Exercise
    let isActive: Bool
    let isGhost: Bool
    let onDuplicate: () -> Void
    let onActivate: () -> Void

    @EnvironmentObject private var store: WorkoutStoreV2

    private let defaultWorkingReps = 10
    private var step: Double { unit == .kg ? 2.5 : 5 }
    private var displayWeight: Double { unit == .kg ? set.weight : (set.weight * 2.20462) }

    // Tutorial frame capture callbacks (only for first set)
    var onSetTypeFrameCaptured: ((CGRect) -> Void)? = nil
    var onCarouselsFrameCaptured: ((CGRect) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Header row with index, completion checkmark, and tag
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(index)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isGhost ? Theme.secondary.opacity(0.6) : Theme.secondary)

                    if set.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 32, alignment: .leading)

                Spacer()

                // Ghost indicator
                if isGhost {
                    Text("PLANNED")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surface2)
                        .clipShape(Capsule())
                }
            }

            // Scroll wheels row with divider
            HStack(spacing: 0) {
                // Reps scroll wheel
                CarouselStepperInt(
                    value: $set.reps,
                    range: 1...50,
                    step: 1,
                    label: "Reps",
                    onChange: {
                        // Disable auto-weight when user manually changes reps
                        set.autoWeight = false
                    }
                )
                .frame(maxWidth: .infinity)
                .disabled(isGhost)

                // Vertical divider
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1, height: 40)
                    .padding(.horizontal, 12)

                // Weight scroll wheel
                CarouselStepperDouble(
                    value: Binding(
                        get: { displayWeight },
                        set: { newDisplay in
                            let kg = (unit == .kg) ? max(0, newDisplay) : max(0, newDisplay / 2.20462)
                            set.weight = kg
                        }
                    ),
                    lowerBound: 0,
                    upperBound: unit == .kg ? 300 : 660,
                    step: step,
                    label: "Weight",
                    suffix: unit.rawValue,
                    onManual: { set.autoWeight = false }
                )
                .frame(maxWidth: .infinity)
                .disabled(isGhost)
            }
            .captureFrame(in: .global) { frame in
                onCarouselsFrameCaptured?(frame)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .opacity(set.isCompleted ? 0.6 : (isGhost ? 0.5 : 1.0))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isActive ? Theme.accent : Theme.surface,
                    lineWidth: isActive ? 1 : 1
                )
        )
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                // Tapping any set selects it
                onActivate()
                hideKeyboard()
            }
        )
        .contextMenu {
            Button("Duplicate") { onDuplicate() }
            if !isGhost {
                Button(set.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                    set.isCompleted.toggle()
                }
            }
        }
        .onAppear {
            seedFromMemoryIfNeeded()
            if set.tag == .working { applyWeightSuggestion() }
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
}

// MARK: - Set Row Compact (Alternative Compact View)

struct SetRowCompact: View {
    let index: Int
    @Binding var set: SetInput
    let unit: WeightUnit
    let exercise: Exercise
    let onDuplicate: () -> Void

    @EnvironmentObject private var store: WorkoutStoreV2

    private let defaultWorkingReps = 10
    private var step: Double { unit == .kg ? 2.5 : 5 }
    private var displayWeight: Double { unit == .kg ? set.weight : (set.weight * 2.20462) }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(index)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, alignment: .leading)

            // Tag chip: tap to cycle, long-press for menu
            TagCycler(tag: $set.tag)
                .onChange(of: set.tag) { newTag in
                    if newTag == .working {
                        seedFromMemoryIfNeeded()
                        applyWeightSuggestion()
                    }
                }

            // Reps
            CompactStepperInt(value: $set.reps, label: "Reps", lower: 0, upper: 500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: set.reps) { _ in
                       if set.tag == .working, set.autoWeight {
                           applyWeightSuggestion()
                       }
                   }

            // Weight
            CompactStepperDouble(
                valueDisplay: Binding(
                    get: { displayWeight },
                    set: { newDisplay in
                        let kg = (unit == .kg) ? max(0, newDisplay) : max(0, newDisplay / 2.20462)
                        set.weight = kg
                    }
                ),
                step: step,
                  label: "Weight",
                  suffix: unit.rawValue,
                  onManualEdit: { set.autoWeight = false }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .contextMenu { Button("Duplicate") { onDuplicate() } }
        .onAppear {
            if set.tag == .working { applySuggestionsIfAllowed() }
        }
        .onAppear {
            seedFromMemoryIfNeeded()
            if set.tag == .working { applyWeightSuggestion() }
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

    private func applySuggestionsIfAllowed() {
        guard set.autoWeight else { return }

        if let last = store.lastWorkingSet(exercise: exercise) {
            set.reps = last.reps
            set.weight = last.weightKg
            return
        }

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
}

// MARK: - Tag Dot Cycler

struct TagDotCycler: View {
    @Binding var tag: SetTag

    var body: some View {
        Button {
            cycle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tag.color).frame(width: 10, height: 10)
                Text(tag.short)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(SetTag.allCases, id: \.self) { t in Button(t.label) { tag = t } }
        }
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

// MARK: - Tag Cycler (Alternative Style)

struct TagCycler: View {
    @Binding var tag: SetTag

    var body: some View {
        let label = tag.label
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tag.color, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 0.75))
            .onTapGesture { cycle() }
            .contextMenu {
                ForEach(SetTag.allCases, id: \.self) { t in
                    Button(t.label) { tag = t }
                }
            }
            .accessibilityLabel("Set type \(label)")
    }

    private func cycle() {
        let all = SetTag.allCases
        if let idx = all.firstIndex(of: tag) {
            let next = all.index(after: idx)
            tag = next < all.endIndex ? all[next] : all.first!
        } else {
            tag = .working
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
