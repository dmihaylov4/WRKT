//
//  CutPlannedEditorView.swift
//  WRKT
//
//  The planned workout editor in the Cut language, matching batch 1's Edit workout: the name as
//  an underline field, the date as a hairline row with the system date capsule, exercises as
//  hairline rows that open the exercise sheet and swipe away, one Add exercise pill, and Delete
//  workout as an outlined red pill. Cancel and Save sit in the bar. The exercise sheet matches
//  batch 1's set editor (weight and reps columns with grey step pills) and adds the note.
//  Takes plain values, bindings for what is typed or picked, and closures.
//

import SwiftUI

struct CutPlannedEditorActions {
    var cancel: () -> Void = {}
    var save: () -> Void = {}
    var addExercise: () -> Void = {}
    var editExercise: (UUID) -> Void = { _ in }
    var deleteExercises: (IndexSet) -> Void = { _ in }
    var deleteWorkout: () -> Void = {}
}

struct CutPlannedEditorView: View {
    let model: CutPlannedEditorModel
    @Binding var name: String
    @Binding var date: Date
    var actions = CutPlannedEditorActions()

    var body: some View {
        List {
            editorRow {
                CutPlannedNameField(name: $name).padding(.top, 8)
            }
            editorRow {
                VStack(alignment: .leading, spacing: 0) {
                    CutHairline()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            dateLabel
                            Spacer(minLength: 8)
                            datePicker
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            dateLabel
                            datePicker
                        }
                    }
                    .frame(minHeight: 50)
                    .padding(.vertical, 8)
                    CutHairline()
                    if model.showsMoveHint {
                        Text(CutPlannedEditorLogic.moveHint)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 24)
            }
            editorRow {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        CutSectionTitle("Exercises")
                        Text("\(model.rows.count)")
                            .cutFont(.secondary, monospacedDigits: true)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .accessibilityLabel(Text(CutPlanLogic.exercises(model.rows.count)))
                    }
                    if !model.rows.isEmpty {
                        Text("Tap an exercise to edit its sets and note.")
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    CutHairline()
                }
                .padding(.top, 36)
            }
            ForEach(model.rows) { row in
                editorRow {
                    Button { actions.editExercise(row.id) } label: { CutPlannedExerciseRow(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Edits the sets and note"))
                }
                .accessibilityAction(named: Text("Delete exercise")) {
                    if let index = model.rows.firstIndex(of: row) { actions.deleteExercises(IndexSet(integer: index)) }
                }
            }
            .onDelete(perform: actions.deleteExercises)
            editorRow {
                VStack(spacing: 14) {
                    if model.rows.isEmpty {
                        Text("Build the workout, then tap each exercise to edit its sets and add a note.")
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Add first exercise", systemImage: "plus", action: actions.addExercise)
                            .buttonStyle(CutPrimaryButtonStyle())
                    } else {
                        Button("Add exercise", systemImage: "plus", action: actions.addExercise)
                            .buttonStyle(CutSecondaryButtonStyle())
                    }
                    if model.canDelete {
                        Button(role: .destructive, action: actions.deleteWorkout) {
                            Label("Delete workout", systemImage: "trash")
                        }
                        .buttonStyle(CutPlannedDestructiveButtonStyle())
                        .padding(.top, 22)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CutEditorToolbar(canSave: model.canSave, cancel: actions.cancel, save: actions.save) }
    }

    private var dateLabel: some View {
        Text("Date")
            .cutFont(.title)
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .fixedSize()
    }

    private var datePicker: some View {
        DatePicker("Date", selection: $date, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(DS.Cut.Colors.lime)
            .fixedSize()
    }

    private func editorRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Cut.Metrics.gutter, bottom: 0, trailing: DS.Cut.Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Cut.Colors.background)
    }
}

/// One planned exercise: name, the first sets in short, the plateau note and the exercise note.
private struct CutPlannedExerciseRow: View {
    let row: CutPlannedEditorModel.Row

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.preview)
                        .cutFont(.secondary, monospacedDigits: true)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let plateau = row.plateau {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "chart.line.flattrend.xyaxis")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                            Text(plateau)
                        }
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    if let note = row.note {
                        Text(note)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "Workout name" over an underline field, with what an empty name saves as under it.
private struct CutPlannedNameField: View {
    @Binding var name: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout name")
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
            TextField("Workout name", text: $name,
                      prompt: Text(CutPlannedEditorLogic.namePlaceholder).foregroundStyle(DS.Cut.Colors.textSecondary))
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .tint(DS.Cut.Colors.lime)
                .textInputAutocapitalization(.words)
                .focused($focused)
                .submitLabel(.done)
                .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
            Rectangle()
                .fill(focused ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong)
                .frame(height: focused ? 2 : 1)
                .accessibilityHidden(true)
            Text(CutPlannedEditorLogic.nameHint)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An outlined pill in the system red: the one destructive action at the end of an editor.
private struct CutPlannedDestructiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Cut.Typography.font(.button).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color.red)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Exercise sheet

/// The exercise's sets as batch 1's set editor draws them, then its note. Sized to its content.
struct CutPlannedSetsView: View {
    let model: CutPlannedSetsModel
    @Binding var notes: String
    var apply: (CutSetEditorEdit) -> Void = { _ in }
    var done: () -> Void = {}

    @State private var contentHeight: CGFloat = 0
    @State private var typing: Typing?
    @State private var typedText = ""
    @FocusState private var focused: Bool
    @FocusState private var notesFocused: Bool

    struct Typing: Equatable {
        enum Field { case weight, reps }
        var row: Int
        var field: Field
    }

    /// Estimated before the list has laid out, then measured.
    private var sheetHeight: CGFloat {
        let content = contentHeight > 0 ? contentHeight : CGFloat(150 + model.rows.count * 128 + 240)
        return content + 64
    }

    var body: some View {
        List {
            row {
                VStack(alignment: .leading, spacing: 6) {
                    CutHeroText(CutHeroText.balancedLines(model.exerciseName), hero: .xs, minimumScaleFactor: 0.5)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.countLine)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            row { CutHairline() }
            ForEach(model.rows) { set in
                row {
                    VStack(spacing: 0) {
                        setRow(set)
                        CutHairline()
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) { commitThen { apply(.delete(set.id)) } }
                }
                .accessibilityAction(named: Text("Delete set")) { apply(.delete(set.id)) }
            }
            row {
                Button("Add set", systemImage: "plus") {
                    commitThen { apply(.add) }
                    Haptics.light()
                }
                .buttonStyle(CutSecondaryButtonStyle())
                .padding(.top, 20)
            }
            row {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note")
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                    TextField("Note", text: $notes,
                              prompt: Text("Optional").foregroundStyle(DS.Cut.Colors.textSecondary), axis: .vertical)
                        .lineLimit(3...6)
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .tint(DS.Cut.Colors.lime)
                        .focused($notesFocused)
                        .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                    Rectangle()
                        .fill(notesFocused ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong)
                        .frame(height: notesFocused ? 2 : 1)
                        .accessibilityHidden(true)
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
            contentHeight = height
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .navigationTitle("Edit sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commitThen(done) }
                    .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focused = false
                    notesFocused = false
                }
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commitTyping() }
        }
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.visible)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Cut.Metrics.gutter, bottom: 0, trailing: DS.Cut.Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Cut.Colors.background)
    }

    // MARK: Set row

    @ScaledMetric(relativeTo: .title3) private var numberWidth: CGFloat = 28

    private func setRow(_ set: CutSetEditorRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(set.number)
                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .frame(width: numberWidth, alignment: .leading)
                .padding(.top, 8)
                .accessibilityHidden(true)
            column(set: set, field: .weight, value: set.weight, unit: model.unitLabel,
                   canDecrease: set.canDecreaseWeight, down: .weightDown(set.id), up: .weightUp(set.id))
            Rectangle().fill(DS.Cut.Colors.hairline).frame(width: DS.Cut.Metrics.hairline)
            column(set: set, field: .reps, value: set.reps, unit: "reps",
                   canDecrease: set.canDecreaseReps, down: .repsDown(set.id), up: .repsUp(set.id))
                .padding(.leading, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 14)
    }

    private func column(set: CutSetEditorRow, field: Typing.Field, value: String, unit: String,
                        canDecrease: Bool, down: CutSetEditorEdit, up: CutSetEditorEdit) -> some View {
        let isTyping = typing == Typing(row: set.id, field: field)
        let name = field == .weight ? "weight" : "reps"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if isTyping {
                    TextField(name, text: $typedText)
                        .keyboardType(field == .weight ? .decimalPad : .numberPad)
                        .focused($focused)
                        .font(DS.Cut.Typography.numeral(.medium))
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .tint(DS.Cut.Colors.lime)
                        .fixedSize()
                        .accessibilityLabel(Text("Set \(set.number) \(name)"))
                } else {
                    Button {
                        commitThen {
                            typedText = value
                            typing = Typing(row: set.id, field: field)
                            focused = true
                        }
                    } label: {
                        Text(value)
                            .cutNumeral(.medium)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Set \(set.number), \(value) \(unit)"))
                    .accessibilityHint(Text("Type a new value"))
                }
                Text(unit)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                CutPlannedStepButton(systemImage: "minus", label: "Decrease \(name)", isEnabled: canDecrease) {
                    apply(down)
                }
                CutPlannedStepButton(systemImage: "plus", label: "Increase \(name)", isEnabled: true) {
                    apply(up)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }

    /// Applies any typed value before another change, so nothing typed is lost.
    private func commitThen(_ action: () -> Void) {
        commitTyping()
        action()
    }

    private func commitTyping() {
        guard let typing else { return }
        apply(typing.field == .weight ? .typedWeight(typing.row, typedText) : .typedReps(typing.row, typedText))
        self.typing = nil
        focused = false
    }
}

/// A grey pill step button (batch 1's pattern): one step on tap, repeating every tenth of a
/// second while held.
private struct CutPlannedStepButton: View {
    let systemImage: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var timer: Timer?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(isEnabled ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary.opacity(0.5))
            .frame(width: 56, height: DS.Cut.Metrics.minTouchTarget)
            .background(Capsule().fill(DS.Cut.Colors.controlFill))
            .contentShape(Capsule())
            .onTapGesture {
                guard isEnabled else { return }
                action()
                Haptics.light()
            }
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 30) {
                start()
            } onPressingChanged: { pressing in
                if !pressing { stop() }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { stop() }
            }
            .onDisappear { stop() }
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
            .accessibilityRemoveTraits(isEnabled ? [] : .isButton)
            .accessibilityAction {
                guard isEnabled else { return }
                action()
            }
    }

    private func start() {
        guard isEnabled, timer == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        action()
        let repeating = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if isEnabled { action() } else { stop() }
            }
        }
        RunLoop.main.add(repeating, forMode: .common)
        timer = repeating
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}
