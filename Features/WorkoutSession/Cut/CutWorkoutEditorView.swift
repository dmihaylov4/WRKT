//
//  CutWorkoutEditorView.swift
//  WRKT
//
//  The Cut workout editors. Edit workout: the name as an underline field (its placeholder is
//  its label), date and watch as hairline rows, exercises as hairline rows with a one line
//  summary that open the set editor and swipe away, and one compact Add exercise pill. Log
//  workout: the day as a modest hero, the name, Started and Finished rows with the system date
//  capsules, then the same exercise rows. Cancel and Save sit in the bar; Save turns lime once
//  it can save. The planned workout editor shares the name field, section label and pill.
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
                CutEditorNameField(name: $name, placeholder: CutWorkoutEditorLogic.namePlaceholder).padding(.top, 8)
            }
            CutEditorRow {
                VStack(spacing: 0) {
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
                .padding(.top, 8)
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
                CutEditorNameField(name: $name, placeholder: CutWorkoutEditorLogic.namePlaceholder).padding(.top, 16)
            }
            CutEditorRow {
                VStack(alignment: .leading, spacing: 0) {
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
                .padding(.top, 8)
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

/// The name as an underline field whose placeholder is its label. An empty name still saves,
/// so nothing under it explains that.
struct CutEditorNameField: View {
    @Binding var name: String
    let placeholder: String
    var capitalizesWords = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Workout name", text: $name,
                      prompt: Text(placeholder).foregroundStyle(DS.Cut.Colors.textSecondary))
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .tint(DS.Cut.Colors.lime)
                .textInputAutocapitalization(capitalizesWords ? .words : .sentences)
                .focused($focused)
                .submitLabel(.done)
                .frame(minHeight: 50)
            Rectangle()
                .fill(focused ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong)
                .frame(height: focused ? 2 : 1)
                .accessibilityHidden(true)
        }
    }
}

/// "Exercises" as a section label (secondary text, as Settings labels its sections), so it
/// never reads as a row or a button.
struct CutEditorExercisesHeader: View {
    var body: some View {
        CutSettingsSectionHeader("Exercises")
    }
}

/// "Add exercise": the one compact outlined pill under the list, the same with or without
/// exercises. Save, in the bar, is the screen's lime action.
struct CutEditorAddExercise: View {
    let action: () -> Void

    var body: some View {
        Button("Add exercise", systemImage: "plus", action: action)
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
    }
}

/// The exercises section: the label, one row per exercise, then Add exercise.
private struct CutEditorExercises: View {
    let rows: [CutWorkoutEditorRow]
    let actions: CutWorkoutEditorActions

    var body: some View {
        CutEditorRow {
            CutEditorExercisesHeader()
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
            CutEditorAddExercise(action: actions.addExercise)
                .padding(.bottom, 40)
        }
    }
}

/// Cancel and Save in the bar, Save off until the rules allow it and lime once it is on.
struct CutEditorToolbar: ToolbarContent {
    let canSave: Bool
    let cancel: () -> Void
    let save: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: cancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            // Lime marks the one action that finishes the screen, once it can.
            Button("Save", action: save)
                .fontWeight(.semibold)
                .tint(canSave ? DS.Cut.Colors.lime : nil)
                .disabled(!canSave)
        }
    }
}
