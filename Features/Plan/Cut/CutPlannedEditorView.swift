//
//  CutPlannedEditorView.swift
//  WRKT
//
//  The planned workout editor in the Cut language, matching Edit workout: the name as an
//  underline field (its placeholder is its label), the date as a hairline row with the system
//  date capsule, exercises as hairline rows with a one line summary that open the exercise
//  sheet and swipe away, one compact Add exercise pill, and Delete workout as an outlined red
//  pill. Cancel and Save sit in the bar. The exercise sheet uses the set editor's rows and adds
//  the note.
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
                CutEditorNameField(name: $name, placeholder: CutPlannedEditorLogic.namePlaceholder, capitalizesWords: true)
                    .padding(.top, 8)
            }
            editorRow {
                VStack(alignment: .leading, spacing: 0) {
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
                }
                .padding(.top, 8)
            }
            editorRow { CutEditorExercisesHeader() }
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
                VStack(spacing: 0) {
                    CutEditorAddExercise(action: actions.addExercise)
                    if model.canDelete {
                        Button(role: .destructive, action: actions.deleteWorkout) {
                            Label("Delete workout", systemImage: "trash")
                        }
                        .buttonStyle(CutPlannedDestructiveButtonStyle())
                        .padding(.top, 56)
                    }
                }
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

/// The exercise's sets as the set editor draws them (steppers only on the set being edited),
/// then its note. Sized to its content.
struct CutPlannedSetsView: View {
    let model: CutPlannedSetsModel
    @Binding var notes: String
    var apply: (CutSetEditorEdit) -> Void = { _ in }
    var done: () -> Void = {}

    @State private var contentHeight: CGFloat = 0
    @State private var selected = 0
    @State private var typing: CutSetTyping?
    @State private var typedText = ""
    @FocusState private var focused: Bool
    @FocusState private var notesFocused: Bool

    /// Estimated before the list has laid out, then measured.
    private var sheetHeight: CGFloat {
        let content = contentHeight > 0 ? contentHeight : CGFloat(150 + model.rows.count * 70 + 60 + 90 + 110)
        return content + 64
    }

    var body: some View {
        List {
            row { CutSetEditorHeader(name: model.exerciseName, countLine: model.countLine) }
            row { CutHairline() }
            ForEach(model.rows) { set in
                row {
                    CutSetEditorSetRow(
                        set: set, unitLabel: model.unitLabel, isSelected: set.id == selected,
                        typingField: typing?.row == set.id ? typing?.field : nil,
                        typedText: $typedText, focused: $focused,
                        select: { commitThen { selected = set.id } },
                        beginTyping: { field, value in
                            commitThen {
                                typedText = value
                                typing = CutSetTyping(row: set.id, field: field)
                                focused = true
                            }
                        },
                        apply: apply
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(set.id) }
                }
                .accessibilityAction(named: Text("Delete set")) { delete(set.id) }
            }
            row {
                CutSetEditorAddSet {
                    commitThen {
                        apply(.add)
                        selected = model.rows.count
                    }
                }
            }
            row {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Note", text: $notes,
                              prompt: Text("Note").foregroundStyle(DS.Cut.Colors.textSecondary), axis: .vertical)
                        .lineLimit(1...6)
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .tint(DS.Cut.Colors.lime)
                        .focused($notesFocused)
                        .frame(minHeight: 50)
                    Rectangle()
                        .fill(notesFocused ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong)
                        .frame(height: notesFocused ? 2 : 1)
                        .accessibilityHidden(true)
                }
                .padding(.top, 24)
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
        content().cutSetEditorRow()
    }

    private func delete(_ id: Int) {
        commitThen {
            apply(.delete(id))
            selected = CutSetEditorLogic.selection(afterDeleting: id, selected: selected, count: model.rows.count)
        }
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
