//
//  CutSetLoggingView.swift
//  WRKT
//
//  Set logging in the Cut language: a short meta line, the exercise as the hero, weight and
//  reps as two huge numerals with round steppers, slanted set segments, and the lime "Log set"
//  bar pinned at the bottom. Everything the legacy rows offered stays reachable below as
//  hairline rows (set list, set menus, superset, add set, advice rows).
//
//  Takes plain values, a binding to the sets and closures, so fixtures can render every state.
//  ExerciseSessionView owns the data and wires each closure to its existing code.
//

import SwiftUI

/// What the controls do. ExerciseSessionView supplies its existing functions.
struct CutSetLoggingActions {
    var logSet: (Int) -> Void = { _ in }
    var activate: (Int) -> Void = { _ in }
    /// The legacy leading swipe: mark complete or incomplete.
    var toggleComplete: (Int) -> Void = { _ in }
    /// The legacy delete, after this view's confirmation (none for the last set: the view
    /// model asks itself).
    var deleteSet: (Int) -> Void = { _ in }
    var addSet: () -> Void = {}
    var toggleSuperset: () -> Void = {}
    var done: () -> Void = {}
    var nextExercise: () -> Void = {}
    var showInfo: () -> Void = {}
    /// A timed hold started (adds the exercise to the workout, as the legacy row did).
    var holdStarted: () -> Void = {}
    /// The plateau row's "+2.5 kg".
    var increaseRemaining: () -> Void = {}
    var cancelRest: () -> Void = {}
    var addRestTime: () -> Void = {}
    var skipRest: () -> Void = {}
}

/// Where the resting row reads its state from.
enum CutRestSource: Equatable {
    /// The rest timer, for this exercise: observed by a leaf view only.
    case live(exerciseID: String)
    /// A fixed countdown, for captures.
    case fixed(TimeInterval)
    case none
}

struct CutSetLoggingView: View {
    let model: CutSetLoggingModel
    @Binding var sets: [SetInput]
    @Binding var activeSetIndex: Int
    var rest: CutRestSource = .none
    var actions = CutSetLoggingActions()

    @FocusState private var focus: CutSetField?
    @State private var holdStart: Date?
    @State private var holdBase = 0
    @State private var pendingDeleteIndex: Int?
    @State private var plateauDismissed = false
    @State private var restZone: CutRestZone?
    @State private var restZoneWork: DispatchWorkItem?
    @AppStorage("rest_rec_strength_dismiss_count") private var strengthDismissCount = 0
    @AppStorage("rest_rec_pump_dismiss_count") private var pumpDismissCount = 0

    private var activeSet: SetInput? { sets[safe: activeSetIndex] }
    private var activeIsEditable: Bool {
        guard let set = activeSet else { return false }
        return !set.isGhost && !set.isCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                // Opaque, with a hairline, so scrolled content passes cleanly under it.
                .background(DS.Cut.Colors.background)
            CutHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroBlock
                    inputs
                        .padding(.top, 30)
                    CutSetSegments(sets: sets, activeSetIndex: activeSetIndex, mode: model.mode, unit: model.unit,
                                   onActivate: activate)
                        .padding(.top, 30)
                    if model.mode == .weighted, let set = activeSet, set.tag == .working, !set.isCompleted {
                        rpeRow(set)
                            .padding(.top, 24)
                    }
                    lists
                        .padding(.top, 28)
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Black behind the whole bar rectangle, so nothing shows in the cut corner's triangle.
            actionBar
                .background(DS.Cut.Colors.background.ignoresSafeArea(edges: .bottom))
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onChange(of: activeSet?.reps) { _, reps in
            if let reps { scheduleRestZone(reps: reps) }
        }
        .onChange(of: activeSetIndex) { _, _ in
            restZoneWork?.cancel()
            withAnimation(.easeInOut(duration: 0.2)) { restZone = nil }
        }
        .onDisappear { stopHold() }
        .alert("Delete set", isPresented: Binding(
            get: { pendingDeleteIndex != nil },
            set: { if !$0 { pendingDeleteIndex = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let index = pendingDeleteIndex {
                    actions.deleteSet(index)
                    pendingDeleteIndex = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteIndex = nil }
        } message: {
            Text("Are you sure you want to delete this set?")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Exercise info", systemImage: "info", action: actions.showInfo)
                .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 44))
            Spacer(minLength: 12)
            Button("Done") {
                Haptics.light()
                actions.done()
            }
            .font(DS.Cut.Typography.font(.title))
            .foregroundStyle(DS.Cut.Colors.lime)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.metaLine)
                .cutFont(.title)
                .foregroundStyle(DS.Cut.Colors.lime)
            // While a rest runs the countdown takes the hero's place; the inputs stay for the next set.
            CutRestSlot(source: rest, hasCompletedSet: sets.contains(where: \.isCompleted),
                        nextLine: CutRestLogic.nextLine(sets: sets, activeSetIndex: activeSetIndex, mode: model.mode, unit: model.unit),
                        actions: CutRestActions(addTime: actions.addRestTime, skip: actions.skipRest, cancel: actions.cancelRest)) {
                let lines = CutHeroText.balancedLines(model.exerciseName)
                CutHeroText(lines, hero: CutTrainLogic.heroSize(forLines: lines) == .xl ? .l : CutTrainLogic.heroSize(forLines: lines),
                            minimumScaleFactor: 0.25)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 8)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { supportLine; Spacer(minLength: 8); setTypeMenu }
                VStack(alignment: .leading, spacing: 10) { supportLine; setTypeMenu }
            }
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    private var supportLine: some View {
        if let line = model.supportLine {
            Text(line)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var setTypeMenu: some View {
        if let set = activeSet {
            let locked = set.isGhost || (model.mode == .timed && set.isCompleted)
            Menu {
                ForEach(SetTag.allCases, id: \.self) { tag in
                    Button {
                        sets[activeSetIndex].tag = tag
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if tag == set.tag {
                            Label(tag.label, systemImage: "checkmark")
                        } else {
                            Text(tag.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(set.tag.label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .overlay(Capsule().strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
                .contentShape(Capsule())
            }
            .disabled(locked)
            .opacity(locked ? 0.4 : 1)
            .fixedSize()
            .accessibilityLabel("Set type")
            .accessibilityValue(set.tag.label)
        }
    }

    // MARK: Inputs

    @ViewBuilder
    private var inputs: some View {
        if let set = activeSet {
            switch model.mode {
            case .weighted:
                HStack(alignment: .top, spacing: 0) {
                    weightColumn(set)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle()
                        .fill(DS.Cut.Colors.hairline)
                        .frame(width: DS.Cut.Metrics.hairline)
                        .accessibilityHidden(true)
                    repsColumn(set)
                        .padding(.leading, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            case .bodyweight:
                repsColumn(set)
            case .timed:
                durationBlock(set)
            }
        }
    }

    private func weightColumn(_ set: SetInput) -> some View {
        let editable = !set.isGhost && !set.isCompleted
        return CutValueColumn(
            label: "Weight, \(model.unit.rawValue)",
            accessibilityName: "Weight",
            value: CutSetLoggingLogic.weightNumeral(set.weight, unit: model.unit),
            accessibilityValue: "\(CutSetLoggingLogic.weightNumeral(set.weight, unit: model.unit)) \(model.unit == .kg ? "kilograms" : "pounds")",
            field: .weight,
            focus: $focus,
            canType: !set.isGhost,
            canDecrement: editable && CutSetEditing.canDecrementWeight(set, unit: model.unit),
            canIncrement: editable && CutSetEditing.canIncrement(set),
            onDecrement: { CutSetEditing.stepWeight(&sets[activeSetIndex], by: -model.weightStep, unit: model.unit) },
            onIncrement: { CutSetEditing.stepWeight(&sets[activeSetIndex], by: model.weightStep, unit: model.unit) }
        ) {
            TextField("", value: Binding(
                get: { model.unit.displayValue(sets[safe: activeSetIndex]?.weight ?? 0) },
                set: { CutSetEditing.setWeight(&sets[activeSetIndex], displayValue: $0, unit: model.unit) }
            ), format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
        }
    }

    private func repsColumn(_ set: SetInput) -> some View {
        let editable = !set.isGhost && !set.isCompleted
        let mode = model.mode
        return CutValueColumn(
            label: "Reps",
            accessibilityName: "Reps",
            value: "\(set.reps)",
            accessibilityValue: "\(set.reps)",
            field: .reps,
            focus: $focus,
            canType: !set.isGhost,
            canDecrement: editable && CutSetEditing.canDecrementReps(set),
            canIncrement: editable && CutSetEditing.canIncrement(set),
            onDecrement: { CutSetEditing.decrementReps(&sets[activeSetIndex], mode: mode) },
            onIncrement: { CutSetEditing.incrementReps(&sets[activeSetIndex], mode: mode) }
        ) {
            TextField("", value: Binding(
                get: { sets[safe: activeSetIndex]?.reps ?? 0 },
                set: { CutSetEditing.setReps(&sets[activeSetIndex], to: $0, mode: mode) }
            ), format: .number)
            .keyboardType(.numberPad)
        }
    }

    private func durationBlock(_ set: SetInput) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Duration")
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
            Group {
                if let holdStart {
                    CutHoldClock(start: holdStart, base: holdBase)
                } else {
                    Text(CutSetLoggingLogic.clock(set.durationSeconds))
                        .accessibilityLabel("Duration")
                        .accessibilityValue(Duration.seconds(set.durationSeconds).formatted(.units(allowed: [.minutes, .seconds])))
                }
            }
            .font(DS.Cut.Typography.numeral(.hero))
            .foregroundStyle(set.isCompleted ? DS.Cut.Colors.textSecondary : DS.Cut.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            if holdStart == nil, !set.isCompleted, !set.isGhost {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { durationSteps(set) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { durationSteps(set, range: 0..<2) }
                        HStack(spacing: 8) { durationSteps(set, range: 2..<4) }
                    }
                }
            }
            if !set.isCompleted, !set.isGhost {
                if holdStart != nil {
                    Button("Stop timer", systemImage: "stop.fill", action: stopHold)
                        .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                } else {
                    Button("Start timer", systemImage: "play.fill", action: startHold)
                        .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                }
            }
        }
    }

    @ViewBuilder
    private func durationSteps(_ set: SetInput, range: Range<Int> = 0..<4) -> some View {
        ForEach(Array(CutSetEditing.durationSteps[range]), id: \.self) { delta in
            Button(delta < 0 ? "\(delta) s" : "+\(delta) s") {
                CutSetEditing.stepDuration(&sets[activeSetIndex], by: delta)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .disabled(!CutSetEditing.canStepDuration(set, by: delta))
            .accessibilityLabel(delta < 0 ? "Subtract \(-delta) seconds" : "Add \(delta) seconds")
        }
    }

    private func startHold() {
        guard let set = activeSet else { return }
        holdBase = set.durationSeconds
        holdStart = .now
        actions.holdStarted()
        Haptics.light()
    }

    private func stopHold() {
        guard let start = holdStart else { return }
        let elapsed = holdBase + max(0, Int(Date.now.timeIntervalSince(start)))
        holdStart = nil
        if sets.indices.contains(activeSetIndex) {
            sets[activeSetIndex].durationSeconds = elapsed
        }
        Haptics.soft()
    }

    // MARK: RPE

    private func rpeRow(_ set: SetInput) -> some View {
        HStack(spacing: 12) {
            Text("RPE")
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CutSetEditing.rpeValues, id: \.self) { value in
                        let selected = set.rpe == value
                        Button {
                            CutSetEditing.toggleRPE(&sets[activeSetIndex], value)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(CutSetLoggingLogic.formatRPE(value))
                                .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                                .foregroundStyle(selected ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
                                .frame(minWidth: 52, minHeight: 44)
                                .background(Capsule().fill(selected ? DS.Cut.Colors.textPrimary : .clear))
                                .overlay(Capsule().strokeBorder(selected ? .clear : DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("RPE \(CutSetLoggingLogic.formatRPE(value))")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Lists

    private var lists: some View {
        CutHairlineList {
            if let zone = restZone {
                CutAdviceRow(text: zone.tip, actionTitle: nil, action: nil) {
                    withAnimation(.easeInOut(duration: 0.2)) { restZone = nil }
                    if zone == .strength { strengthDismissCount += 1 } else { pumpDismissCount += 1 }
                }
            }
            if model.plateauSessions >= 3 && !plateauDismissed {
                CutAdviceRow(
                    text: "\(model.plateauSessions) sessions at the same weight. Try increasing the load.",
                    actionTitle: CutSetLoggingLogic.plateauButtonTitle(stepKg: model.weightStepKg, unit: model.unit),
                    action: actions.increaseRemaining
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { plateauDismissed = true }
                }
            }
            ForEach(Array(sets.indices), id: \.self) { index in
                CutSetRow(index: index, set: sets[index], isActive: index == activeSetIndex, mode: model.mode, unit: model.unit,
                          onTap: { activate(index) },
                          onToggleComplete: { actions.toggleComplete(index) },
                          onDelete: { requestDelete(index) })
            }
            if model.canSuperset {
                CutSupersetRow(isOn: model.isInSuperset, onToggle: actions.toggleSuperset)
            }
            Button(action: actions.addSet) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .accessibilityHidden(true)
                        Text("Add set")
                            .cutFont(.title)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .frame(minHeight: 50)
                    .padding(.vertical, 10)
                    CutHairline()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func activate(_ index: Int) {
        guard let set = sets[safe: index],
              CutSetEditing.canActivate(set, isActive: index == activeSetIndex, mode: model.mode) else { return }
        focus = nil
        sets[index].isAutoGeneratedPlaceholder = false
        actions.activate(index)
    }

    private func requestDelete(_ index: Int) {
        if sets.count == 1 {
            actions.deleteSet(index)
        } else {
            pendingDeleteIndex = index
        }
    }

    // MARK: Rest advice

    private func scheduleRestZone(reps: Int) {
        restZoneWork?.cancel()
        let work = DispatchWorkItem {
            guard let set = activeSet else { return }
            let zone = CutSetEditing.restZone(
                reps: reps, currentRestSeconds: model.adviceRestSeconds, tag: set.tag, isGhost: set.isGhost,
                isActive: true, strengthDismissCount: strengthDismissCount, pumpDismissCount: pumpDismissCount)
            withAnimation(.easeInOut(duration: 0.2)) { restZone = model.mode == .weighted ? zone : nil }
        }
        restZoneWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Action bar

    @ViewBuilder
    private var actionBar: some View {
        switch CutSetLoggingLogic.bar(sets: sets, activeSetIndex: activeSetIndex, restSeconds: model.restSeconds,
                                      nextExerciseName: model.nextExercise?.name, holdRunning: holdStart != nil) {
        case .logSet(let restLine):
            CutActionBar("Log set", subtitle: restLine) {
                focus = nil
                actions.logSet(activeSetIndex)
            }
        case .nextExercise(let name):
            CutActionBar("Next exercise", subtitle: name, systemImage: "arrow.right", action: actions.nextExercise)
        case .done:
            CutActionBar("Done", subtitle: nil) {
                Haptics.light()
                actions.done()
            }
        case .hidden:
            EmptyView()
        case .addSet:
            CutActionBar("Add set", subtitle: nil, systemImage: "plus", action: actions.addSet)
        }
    }
}

enum CutSetField: Hashable { case weight, reps }

// MARK: - Value column

/// A label, a huge numeral (tap to type) and two round steppers under it.
private struct CutValueColumn<Field: View>: View {
    let label: String
    let accessibilityName: String
    let value: String
    let accessibilityValue: String
    let field: CutSetField
    var focus: FocusState<CutSetField?>.Binding
    let canType: Bool
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    @ViewBuilder let textField: () -> Field

    @State private var isTyping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .accessibilityHidden(true)
            Group {
                if isTyping {
                    textField()
                        .focused(focus, equals: field)
                        .multilineTextAlignment(.leading)
                        .tint(DS.Cut.Colors.lime)
                        .accessibilityLabel(accessibilityName)
                } else {
                    Text(value)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: startTyping)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityName)
                        .accessibilityValue(accessibilityValue)
                        .accessibilityHint(canType ? "Double tap to type a value" : "")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { startTyping() }
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: if canIncrement { onIncrement() }
                            case .decrement: if canDecrement { onDecrement() }
                            @unknown default: break
                            }
                        }
                }
            }
            .font(DS.Cut.Typography.numeral(.hero))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                CutStepperButton(systemName: "minus", accessibilityLabel: "Decrease \(accessibilityName.lowercased())",
                                 isEnabled: canDecrement, action: onDecrement)
                CutStepperButton(systemName: "plus", accessibilityLabel: "Increase \(accessibilityName.lowercased())",
                                 isEnabled: canIncrement, action: onIncrement)
            }
            .padding(.top, 4)
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            if newValue != field { isTyping = false }
        }
    }

    private func startTyping() {
        guard canType else { return }
        isTyping = true
        focus.wrappedValue = field
    }
}

/// Round stepper with the legacy press-and-hold repeat: one step on press, then a step every
/// 0.1 s after half a second. Haptics as the legacy StepperButton.
struct CutStepperButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void

    @GestureState private var isPressing = false
    @State private var repeatTimer: Timer?
    // Fixed: two steppers per column must fit side by side at every text size (never below 44 pt).
    private let diameter: CGFloat = 56

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .frame(width: max(diameter, DS.Cut.Metrics.minTouchTarget), height: max(diameter, DS.Cut.Metrics.minTouchTarget))
            .background(Circle().fill(DS.Cut.Colors.controlFill))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(isPressing && isEnabled ? 0.94 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
            )
            .onChange(of: isPressing) { _, pressing in
                if pressing {
                    guard isEnabled else { return }
                    action()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if isPressing && isEnabled { startRepeat() }
                    }
                } else {
                    stopRepeat()
                }
            }
            .onDisappear { stopRepeat() }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { action() } }
    }

    private func startRepeat() {
        guard repeatTimer == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if isEnabled { action() } else { stopRepeat() }
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// The running hold: only this leaf re-renders each second.
private struct CutHoldClock: View {
    let start: Date
    let base: Int

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = base + max(0, Int(context.date.timeIntervalSince(start)))
            Text(CutSetLoggingLogic.clock(seconds))
                .accessibilityLabel("Hold")
                .accessibilityValue(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds])))
        }
    }
}

// MARK: - Set segments

struct CutSetSegments: View {
    let sets: [SetInput]
    let activeSetIndex: Int
    let mode: CutSetMode
    let unit: WeightUnit
    let onActivate: (Int) -> Void

    /// Labels fit under up to six segments; beyond that the set rows carry them.
    private var showsLabels: Bool { sets.count <= 6 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                let isActive = index == activeSetIndex && !set.isCompleted
                Button { onActivate(index) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        SlantedSegmentShape()
                            .fill(set.isCompleted ? DS.Cut.Colors.lime : isActive ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.segmentTrack)
                            .frame(height: 10)
                        if showsLabels {
                            Text(CutSetLoggingLogic.segmentLabel(set, index: index, isActive: isActive, mode: mode, unit: unit))
                                .font(DS.Cut.Typography.font(.secondary).weight(isActive ? .bold : .medium))
                                .foregroundStyle(isActive ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sets")
        .accessibilityValue(CutSetLoggingLogic.segmentsAccessibilityValue(sets: sets, activeSetIndex: activeSetIndex))
    }
}

// MARK: - Rows

private struct CutSetRow: View {
    let index: Int
    let set: SetInput
    let isActive: Bool
    let mode: CutSetMode
    let unit: WeightUnit
    let onTap: () -> Void
    let onToggleComplete: () -> Void
    let onDelete: () -> Void

    private var title: String {
        self.set.tag == .working ? "Set \(index + 1)" : "Set \(index + 1), \(set.tag.label.lowercased())"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if set.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.Cut.Colors.lime)
                    } else {
                        SlantedSegmentShape()
                            .fill(isActive ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.segmentTrack)
                            .frame(width: 14, height: 10)
                    }
                }
                .frame(width: 18)
                .accessibilityHidden(true)
                Text(title)
                    .cutFont(.title)
                    .foregroundStyle(isActive ? DS.Cut.Colors.textPrimary : set.isCompleted ? DS.Cut.Colors.textSecondary : DS.Cut.Colors.textPrimary)
                Spacer(minLength: 8)
                Text(CutSetLoggingLogic.rowValue(set, mode: mode, unit: unit))
                    .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                if let rpe = set.rpe, set.isCompleted {
                    Text("RPE \(CutSetLoggingLogic.formatRPE(rpe))")
                        .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                        .foregroundStyle(DS.Cut.Colors.lime)
                        .lineLimit(1)
                }
                Menu {
                    Button(set.isCompleted ? "Mark incomplete" : "Mark complete",
                           systemImage: set.isCompleted ? "xmark.circle" : "checkmark.circle",
                           action: onToggleComplete)
                    Button("Delete set", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Set \(index + 1) options")
            }
            .frame(minHeight: 50)
            .padding(.vertical, 4)
            CutHairline()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: set.isCompleted ? "Mark incomplete" : "Mark complete", onToggleComplete)
        .accessibilityAction(named: "Delete set", onDelete)
    }
}

private struct CutSupersetRow: View {
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(get: { isOn }, set: { _ in onToggle() })) {
                Text("Superset with previous")
                    .cutFont(.title)
            }
            .tint(DS.Cut.Colors.lime)
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
    }
}

/// One line of advice with an optional action pill and a dismiss button.
struct CutAdviceRow: View {
    let text: String
    let actionTitle: String?
    let action: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(text)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
                }
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 8)
            CutHairline()
        }
    }
}

// MARK: - Next exercise

private struct CutOpenNextExerciseKey: EnvironmentKey {
    static let defaultValue: ((UUID) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by the Cut live overview: opens set logging for another entry of the workout.
    var cutOpenNextExercise: ((UUID) -> Void)? {
        get { self[CutOpenNextExerciseKey.self] }
        set { self[CutOpenNextExerciseKey.self] = newValue }
    }
}

// MARK: - Fixtures

#if DEBUG
enum CutSetLoggingFixtures {
    struct State {
        let name: String
        let model: CutSetLoggingModel
        let sets: [SetInput]
        let active: Int
        var rest: CutRestSource = .none
    }

    static func model(_ name: String = "Bench Press", mode: CutSetMode = .weighted, sets: [SetInput], active: Int,
                      support: String? = "Target 87.5\u{00A0}kg\u{00A0}x\u{00A0}6, PR 100\u{00A0}kg",
                      next: String? = nil, plateau: Int = 0) -> CutSetLoggingModel {
        CutSetLoggingModel(
            exerciseName: name, mode: mode, unit: .kg,
            metaLine: CutSetLoggingLogic.metaLine(setIndex: active, setCount: sets.count, exercise: (0, 6)),
            supportLine: support, exercisePosition: (0, 6), canSuperset: true, isInSuperset: false,
            restSeconds: 120, plateauSessions: plateau,
            nextExercise: next.map { (UUID(), $0) }, weightStep: 2.5, weightStepKg: 2.5,
            adviceRestSeconds: 120, defaultDurationSeconds: 45)
    }

    static func weighted(done: Int, count: Int = 4) -> [SetInput] {
        (0..<count).map { index in
            SetInput(reps: index < done ? [8, 6, 6, 6][index % 4] : 6, weight: index < done ? [80, 85, 85, 85][index % 4] : 85,
                     autoWeight: false, didSeedFromMemory: true, isCompleted: index < done, rpe: index == 1 ? 8 : nil)
        }
    }

    static var states: [State] {
        let first = weighted(done: 0)
        let mid = weighted(done: 2)
        let last = weighted(done: 3)
        let allDone = weighted(done: 4)
        let bodyweight = (0..<3).map { SetInput(reps: [12, 11, 10][$0], weight: 0, isCompleted: $0 < 2, trackingMode: .bodyweight) }
        let timed = (0..<2).map { SetInput(reps: 0, weight: 0, isCompleted: $0 < 1, durationSeconds: 45, trackingMode: .timed) }
        return [
            State(name: "first", model: model(sets: first, active: 0), sets: first, active: 0),
            State(name: "mid", model: model(sets: mid, active: 2, plateau: 3), sets: mid, active: 2),
            State(name: "last", model: model(sets: last, active: 3), sets: last, active: 3),
            State(name: "next-exercise", model: model(sets: allDone, active: 3, next: "Incline DB Press"), sets: allDone, active: 3),
            State(name: "bodyweight", model: model("Pull-ups", mode: .bodyweight, sets: bodyweight, active: 2,
                                                  support: "Record 15 reps, last 12 reps"), sets: bodyweight, active: 2),
            State(name: "timed", model: model("Plank", mode: .timed, sets: timed, active: 1, support: nil), sets: timed, active: 1),
            State(name: "resting", model: model(sets: mid, active: 2), sets: mid, active: 2, rest: .fixed(92)),
            State(name: "resting-after-last", model: model(sets: allDone, active: 3), sets: allDone, active: 3, rest: .fixed(118))
        ]
    }
}
#endif
