//
//  CutSetEditorView.swift
//  WRKT
//
//  The Cut set editor: the exercise as a modest hero, then one hairline row per set with the
//  set number in grey and weight and reps as text in two equal columns. Only the set being
//  edited shows its grey minus and plus pills (hold to repeat, tap the number to type); tap
//  another set to move them there. Swipe a row to delete it; Add set is one compact outlined
//  pill. The sheet is as tall as its rows. The planned workout's sets sheet uses the same rows.
//

import SwiftUI

struct CutSetEditorView: View {
    let model: CutSetEditorModel
    var apply: (CutSetEditorEdit) -> Void = { _ in }
    var done: () -> Void = {}

    @State private var contentHeight: CGFloat = 0
    @State private var selected = 0
    @State private var typing: CutSetTyping?
    @State private var typedText = ""
    @FocusState private var focused: Bool

    /// Estimated before the list has laid out, then measured.
    private var sheetHeight: CGFloat {
        let content = contentHeight > 0 ? contentHeight : CGFloat(150 + model.rows.count * 70 + 60 + 90)
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
                Button("Done") { focused = false }
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

// MARK: - Shared set editing pieces

/// The field being typed into, by set position.
struct CutSetTyping: Equatable {
    enum Field { case weight, reps }
    var row: Int
    var field: Field
}

extension View {
    /// Gutter insets, no system separator, black row background.
    func cutSetEditorRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: DS.Cut.Metrics.gutter, bottom: 0, trailing: DS.Cut.Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Cut.Colors.background)
    }
}

/// The exercise name as a modest hero over its set count.
struct CutSetEditorHeader: View {
    let name: String
    let countLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CutHeroText(CutHeroText.balancedLines(name), hero: .xs, minimumScaleFactor: 0.5)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text(countLine)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

/// "Add set": the compact outlined pill, at the start of the line under the sets.
struct CutSetEditorAddSet: View {
    let action: () -> Void

    var body: some View {
        Button("Add set", systemImage: "plus") {
            action()
            Haptics.light()
        }
        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }
}

/// One set: its number, then weight and reps as text in two equal columns, over a hairline.
/// The selected set also shows the minus and plus pills under each value and takes typing;
/// any other set is one tap target that selects it. VoiceOver can step any set in place.
struct CutSetEditorSetRow: View {
    let set: CutSetEditorRow
    let unitLabel: String
    let isSelected: Bool
    let typingField: CutSetTyping.Field?
    @Binding var typedText: String
    var focused: FocusState<Bool>.Binding
    let select: () -> Void
    let beginTyping: (CutSetTyping.Field, String) -> Void
    let apply: (CutSetEditorEdit) -> Void

    @ScaledMetric(relativeTo: .title3) private var numberWidth: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            if isSelected {
                content
            } else {
                Button(action: select) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Set \(set.number), \(set.weight) \(unitLabel), \(set.reps) reps"))
                    .accessibilityHint(Text("Edits this set"))
                    .accessibilityAction(named: Text("Increase weight")) { apply(.weightUp(set.id)) }
                    .accessibilityAction(named: Text("Decrease weight")) {
                        if set.canDecreaseWeight { apply(.weightDown(set.id)) }
                    }
                    .accessibilityAction(named: Text("Increase reps")) { apply(.repsUp(set.id)) }
                    .accessibilityAction(named: Text("Decrease reps")) {
                        if set.canDecreaseReps { apply(.repsDown(set.id)) }
                    }
            }
            CutHairline()
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(set.number)
                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                .foregroundStyle(isSelected ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                .frame(width: numberWidth, alignment: .leading)
                .padding(.top, 3)
                .accessibilityHidden(true)
            column(.weight, value: set.weight, unit: unitLabel, canDecrease: set.canDecreaseWeight,
                   down: .weightDown(set.id), up: .weightUp(set.id))
            Rectangle().fill(DS.Cut.Colors.hairline).frame(width: DS.Cut.Metrics.hairline)
            column(.reps, value: set.reps, unit: "reps", canDecrease: set.canDecreaseReps,
                   down: .repsDown(set.id), up: .repsUp(set.id))
                .padding(.leading, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
        .padding(.vertical, 12)
    }

    private func column(_ field: CutSetTyping.Field, value: String, unit: String, canDecrease: Bool,
                        down: CutSetEditorEdit, up: CutSetEditorEdit) -> some View {
        let name = field == .weight ? "weight" : "reps"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if isSelected && typingField == field {
                    TextField(name, text: $typedText)
                        .keyboardType(field == .weight ? .decimalPad : .numberPad)
                        .focused(focused)
                        .font(Self.valueFont)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .tint(DS.Cut.Colors.lime)
                        .fixedSize()
                        .accessibilityLabel(Text("Set \(set.number) \(name)"))
                } else if isSelected {
                    Button { beginTyping(field, value) } label: {
                        Text(value)
                            .font(Self.valueFont)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Set \(set.number), \(value) \(unit)"))
                    .accessibilityHint(Text("Type a new value"))
                } else {
                    Text(value)
                        .font(Self.valueFont)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .lineLimit(1)
                }
                Text(unit)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            if isSelected {
                HStack(spacing: 8) {
                    CutRepeatStepButton(systemImage: "minus", label: "Decrease \(name)", isEnabled: canDecrease) {
                        apply(down)
                    }
                    CutRepeatStepButton(systemImage: "plus", label: "Increase \(name)", isEnabled: true) {
                        apply(up)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }

    /// 28 pt condensed: readable at a glance, a step under the stat numerals.
    private static let valueFont = DS.Cut.Typography.condensed(size: 28, relativeTo: .title2, monospacedDigits: true)
}

/// A grey pill step button: one step on tap, repeating every tenth of a second while held.
struct CutRepeatStepButton: View {
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
