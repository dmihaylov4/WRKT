//
//  CutWorkoutEditorView.swift
//  WRKT
//
//  The Cut workout editors. Edit workout: the name as an underline field, date and watch as
//  hairline rows, exercises as hairline rows that open the set editor and swipe away, and one
//  Add exercise pill. Log workout: the day as a modest hero, the name, Started and Finished rows
//  with the system date capsules, then the same exercise rows. Cancel and Save sit in the bar.
//  Takes plain values, bindings for what is typed or picked, and closures.
//

import SwiftUI

struct CutWorkoutEditorActions {
    var cancel: () -> Void = {}
    var save: () -> Void = {}
    var addExercise: () -> Void = {}
    var editExercise: (UUID) -> Void = { _ in }
    /// Nil where exercises cannot be removed (logging a past workout, as before).
    var deleteExercises: ((IndexSet) -> Void)?
}

// MARK: - Edit workout

struct CutWorkoutEditorView: View {
    let model: CutWorkoutEditorModel
    @Binding var name: String
    var actions = CutWorkoutEditorActions()

    var body: some View {
        CutEditorList {
            CutEditorRow {
                CutEditorNameField(name: $name).padding(.top, 8)
            }
            CutEditorRow {
                VStack(spacing: 0) {
                    CutHairline()
                    CutEditorValueRow(title: "Date", value: model.dateLine)
                    if model.isSyncedWithWatch {
                        HStack(spacing: 12) {
                            Text("Synced with Apple Watch")
                                .cutFont(.title)
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                            Spacer(minLength: 8)
                            Image(systemName: "applewatch")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 50)
                        .padding(.vertical, 10)
                        CutHairline()
                    }
                }
                .padding(.top, 24)
            }
            CutEditorExercises(rows: model.rows, actions: actions)
        }
        .navigationTitle("Edit workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CutEditorToolbar(canSave: model.canSave, cancel: actions.cancel, save: actions.save) }
    }
}

// MARK: - Log workout

struct CutWorkoutLogView: View {
    let model: CutWorkoutLogModel
    @Binding var name: String
    @Binding var start: Date
    @Binding var end: Date
    var actions = CutWorkoutEditorActions()

    var body: some View {
        CutEditorList {
            CutEditorRow {
                Text(model.dayTitle)
                    .cutHero(.xs, minimumScaleFactor: 0.6)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
            }
            CutEditorRow {
                CutEditorNameField(name: $name).padding(.top, 20)
            }
            CutEditorRow {
                VStack(alignment: .leading, spacing: 0) {
                    CutHairline()
                    timeRow("Started", selection: $start)
                    timeRow("Finished", selection: $end)
                    if let issue = model.timeIssue {
                        Text(issue)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 24)
            }
            CutEditorExercises(rows: model.rows, actions: actions)
        }
        .navigationTitle("Log workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CutEditorToolbar(canSave: model.canSave, cancel: actions.cancel, save: actions.save) }
    }

    private func timeRow(_ title: String, selection: Binding<Date>) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    label(title)
                    Spacer(minLength: 8)
                    picker(title, selection: selection)
                }
                VStack(alignment: .leading, spacing: 8) {
                    label(title)
                    picker(title, selection: selection)
                }
            }
            .frame(minHeight: 50)
            .padding(.vertical, 8)
            CutHairline()
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .cutFont(.title)
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .fixedSize()
    }

    private func picker(_ title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(DS.Cut.Colors.lime)
            .fixedSize()
    }
}

// MARK: - Shared editor pieces

/// A plain list on the black ground: rows carry their own hairlines, swipe actions still work.
private struct CutEditorList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        List {
            content()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}

/// One full-width list row with the Cut gutter and no system separator.
private struct CutEditorRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Cut.Metrics.gutter, bottom: 0, trailing: DS.Cut.Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Cut.Colors.background)
    }
}

/// A title with a value on the right, or under it when both no longer fit on one line.
private struct CutEditorValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    titleText
                    Spacer(minLength: 8)
                    valueText.lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title).cutFont(.title).foregroundStyle(DS.Cut.Colors.textPrimary).fixedSize()
    }

    private var valueText: some View {
        Text(value)
            .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Workout name" over an underline field, with the auto-name hint under it.
private struct CutEditorNameField: View {
    @Binding var name: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout name")
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
            TextField("Workout name", text: $name,
                      prompt: Text(CutWorkoutEditorLogic.namePlaceholder).foregroundStyle(DS.Cut.Colors.textSecondary))
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .tint(DS.Cut.Colors.lime)
                .focused($focused)
                .submitLabel(.done)
                .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
            Rectangle()
                .fill(focused ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong)
                .frame(height: focused ? 2 : 1)
                .accessibilityHidden(true)
            Text(CutWorkoutEditorLogic.nameHint)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The exercises section: a title with the count, one row per exercise, then the add pill.
private struct CutEditorExercises: View {
    let rows: [CutWorkoutEditorRow]
    let actions: CutWorkoutEditorActions

    var body: some View {
        CutEditorRow {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    CutSectionTitle("Exercises")
                    Text("\(rows.count)")
                        .cutFont(.secondary, monospacedDigits: true)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityLabel(Text(rows.count == 1 ? "1 exercise" : "\(rows.count) exercises"))
                }
                CutHairline()
            }
            .padding(.top, 36)
        }
        ForEach(rows) { row in
            CutEditorRow {
                Button { actions.editExercise(row.id) } label: {
                    CutHairlineRow(row.name, subtitle: row.preview, showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Edits the sets"))
            }
        }
        .onDelete(perform: actions.deleteExercises)
        CutEditorRow {
            Group {
                if rows.isEmpty {
                    Button("Add first exercise", systemImage: "plus", action: actions.addExercise)
                        .buttonStyle(CutPrimaryButtonStyle())
                } else {
                    Button("Add exercise", systemImage: "plus", action: actions.addExercise)
                        .buttonStyle(CutSecondaryButtonStyle())
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }
}

/// Cancel and Save in the bar, Save off until the rules allow it.
struct CutEditorToolbar: ToolbarContent {
    let canSave: Bool
    let cancel: () -> Void
    let save: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: cancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }
}
