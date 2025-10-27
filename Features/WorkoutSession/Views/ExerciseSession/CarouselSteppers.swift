//
//  CarouselSteppers.swift
//  WRKT
//
//  Carousel and stepper input components for exercise sessions
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Carousel Stepper (Int)

struct CarouselStepperInt: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: String
    var onChange: () -> Void = {}

    @State private var selection: Int? = nil
    @State private var isEditing = false
    @State private var isScrolling = false
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private var values: [Int] {
        stride(from: range.lowerBound, through: range.upperBound, by: step).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .textCase(.uppercase)

            ZStack {
                // Background container for better visibility
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .frame(height: 40)

                // Scroll wheel (hidden when editing)
                if !isEditing {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 4) {
                                ForEach(values, id: \.self) { v in
                                    Text("\(v)")
                                        .font(.callout.monospacedDigit().weight(v == value ? .bold : .regular))
                                        .foregroundStyle(v == value ? Theme.accent : Theme.secondary)
                                        .frame(width: 44, height: 36)
                                        .background {
                                            if v == value {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Theme.surface2)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1.5)
                                                    )
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if v == value {
                                                isEditing = true
                                                isFocused = true
                                            } else {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    value = v
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    onChange()
                                                }
                                            }
                                        }
                                        .id(v)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.never)
                        .scrollPosition(id: $selection, anchor: .center)
                        .frame(height: 40)
                        .onChange(of: selection) { _, newSelection in
                            // Debounce value updates during fast scrolling
                            guard let newSelection = newSelection, newSelection != value else { return }

                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                                guard !Task.isCancelled else { return }

                                if newSelection != value {
                                    value = newSelection
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onChange()
                                }
                            }
                        }
                        .onChange(of: value) { _, new in
                            // Cancel debounce if value changes programmatically
                            debounceTask?.cancel()
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(new, anchor: .center)
                            }
                            selection = new
                        }
                        .onAppear {
                            if !values.contains(value) {
                                value = values.first ?? range.lowerBound
                            }
                            selection = value
                            proxy.scrollTo(value, anchor: .center)
                        }
                    }
                }

                // Manual input (shown when editing)
                if isEditing {
                    TextField("", value: $value, format: .number)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(height: 40)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 2)
                        )
                        .onChange(of: value) { _, _ in
                            onChange()
                        }
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    isEditing = false
                }
            }
        }
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                        isEditing = false
                    }
                }
            }
        }
    }
}

// MARK: - Carousel Stepper (Double)

struct CarouselStepperDouble: View {
    @Binding var value: Double
    let lowerBound: Double
    let upperBound: Double
    let step: Double
    let label: String
    var suffix: String = ""
    var onManual: () -> Void = {}

    @State private var selection: Double? = nil
    @State private var isEditing = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var isUpdatingFromScroll = false
    @FocusState private var isFocused: Bool

    private var values: [Double] {
        var arr: [Double] = []
        var cur = lowerBound
        while cur <= upperBound + 1e-9 {
            let snapped = (cur / step).rounded() * step
            arr.append(snapped)
            cur += step
        }
        return Array(Set(arr)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .textCase(.uppercase)

                if !suffix.isEmpty {
                    Text("(\(suffix))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondary.opacity(0.7))
                }
            }

            ZStack {
                // Background container for better visibility
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .frame(height: 40)

                // Scroll wheel (hidden when editing)
                if !isEditing {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 4) {
                                ForEach(values, id: \.self) { v in
                                    Text("\(formatValue(v))")
                                        .font(.callout.monospacedDigit().weight(abs(v - value) < 0.01 ? .bold : .regular))
                                        .foregroundStyle(abs(v - value) < 0.01 ? Theme.accent : Theme.secondary)
                                        .frame(width: 52, height: 36)
                                        .background {
                                            if abs(v - value) < 0.01 {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Theme.surface2)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1.5)
                                                    )
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if abs(v - value) < 0.01 {
                                                isEditing = true
                                                isFocused = true
                                            } else {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    value = v
                                                    onManual()
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                }
                                            }
                                        }
                                        .id(v)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.never)
                        .scrollPosition(id: $selection, anchor: .center)
                        .frame(height: 40)
                        .onChange(of: selection) { _, newSelection in
                            // Debounce value updates during fast scrolling
                            guard let newSelection = newSelection, abs(newSelection - value) > 0.01 else { return }

                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                                guard !Task.isCancelled else { return }

                                if abs(newSelection - value) > 0.01 {
                                    isUpdatingFromScroll = true
                                    // Ensure we use a value that exists in the array
                                    value = closestValue(newSelection)
                                    isUpdatingFromScroll = false
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onManual()
                                }
                            }
                        }
                        .onChange(of: value) { _, new in
                            // Skip if this value change came from scrolling
                            guard !isUpdatingFromScroll else { return }

                            // Cancel debounce if value changes programmatically
                            debounceTask?.cancel()
                            let snapped = closestValue(new)
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(snapped, anchor: .center)
                            }
                            selection = snapped
                        }
                        .onAppear {
                            let snapped = closestValue(value)
                            selection = snapped
                            proxy.scrollTo(snapped, anchor: .center)
                        }
                    }
                }

                // Manual input (shown when editing)
                if isEditing {
                    TextField("", value: $value, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(height: 40)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 2)
                        )
                        .onChange(of: value) { _, _ in
                            onManual()
                        }
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    isEditing = false
                    // Snap to nearest step value when done editing
                    let snapped = closestValue(value)
                    if abs(value - snapped) > 0.01 {
                        value = snapped
                        selection = snapped
                        onManual()
                    }
                }
            }
        }
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                        isEditing = false
                    }
                }
            }
        }
    }

    private func snap(_ v: Double) -> Double {
        let clamped = min(max(v, lowerBound), upperBound)
        return (clamped / step).rounded() * step
    }

    // Find the closest value that actually exists in the values array
    private func closestValue(_ v: Double) -> Double {
        guard !values.isEmpty else { return lowerBound }
        return values.min(by: { abs($0 - v) < abs($1 - v) }) ?? v
    }

    private func formatValue(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", v)
        } else {
            return String(format: "%.1f", v)
        }
    }
}

// MARK: - Compact Stepper (Int)

struct CompactStepperInt: View {
    @Binding var value: Int
    let label: String
    let lower: Int
    let upper: Int

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .leading)

            HStack(spacing: 0) {
                Button { bump(-1) } label: { Text("−").font(.headline) }
                    .buttonStyle(CompactKnobStyle())

                Group {
                    if editing {
                        TextField("", value: $value, format: .number)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .onChange(of: focused) { if !$0 { editing = false } }
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 34, maxWidth: 48)
                            .onAppear { focused = true }
                    } else {
                        Text("\(value)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .frame(minWidth: 34, maxWidth: 48)
                            .onTapGesture { editing = true }
                    }
                }
                .padding(.horizontal, 6)

                Button { bump(+1) } label: { Text("+").font(.headline) }
                    .buttonStyle(CompactKnobStyle())
            }
            .pillBackground()
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .toolbar {
            if editing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                        editing = false
                    }
                }
            }
        }
    }

    private func bump(_ delta: Int) {
        let newValue = min(upper, max(lower, value + delta))
        if newValue != value {
            value = newValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Compact Stepper (Double)

struct CompactStepperDouble: View {
    @Binding var valueDisplay: Double
    let step: Double
    let label: String
    var suffix: String = ""
    var onManualEdit: () -> Void = {}

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
                .frame(width: 38, alignment: .leading)

            HStack(spacing: 0) {
                Button {
                    bump(-step)
                    onManualEdit()
                } label: { Text("−").font(.headline) }
                .buttonStyle(CompactKnobStyle())

                Group {
                    if editing {
                        TextField("",
                                  value: $valueDisplay,
                                  format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .onChange(of: focused) { if !$0 { editing = false } }
                            .onChange(of: valueDisplay) { _ in onManualEdit() }
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 56, maxWidth: 74)
                            .onAppear { focused = true }
                    } else {
                        Text("\(valueDisplay, specifier: "%.1f")\(suffix.isEmpty ? "" : " \(suffix)")")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .frame(minWidth: 56, maxWidth: 74)
                            .minimumScaleFactor(0.9)
                            .lineLimit(1)
                            .onTapGesture { editing = true }
                    }
                }
                .padding(.horizontal, 6)

                Button {
                    bump(+step)
                    onManualEdit()
                } label: { Text("+").font(.headline) }
                .buttonStyle(CompactKnobStyle())
            }
            .pillBackground()
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .toolbar {
            if editing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                        editing = false
                    }
                }
            }
        }
    }

    private func bump(_ delta: Double) {
        let newValue = max(0, valueDisplay + delta)
        if newValue != valueDisplay {
            valueDisplay = newValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Supporting Components

private struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.border.opacity(0.9), lineWidth: 0.75))
    }
}

private extension View {
    func pillBackground() -> some View {
        modifier(PillBackground())
    }
}

private struct CompactKnobStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 28, height: 28)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.26 : 0.18), in: Circle())
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.35 : 0.22),
                    radius: configuration.isPressed ? 6 : 4, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct StepCap: View {
    let systemName: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.text)
                .frame(width: width, height: height)
                .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
