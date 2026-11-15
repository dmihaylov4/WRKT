//
//  CutSetEditorView.swift
//  WRKT
//
//  The Cut set editor: the exercise as a modest hero, then one hairline row per set with the
//  set number in grey, weight and reps as condensed numerals in two equal columns, each with
//  grey minus and plus pills under it (hold to repeat, tap the number to type). Swipe a row to
//  delete it; Add set is one outlined pill. The sheet is as tall as its rows.
//

import SwiftUI

struct CutSetEditorView: View {
    let model: CutSetEditorModel
    var apply: (CutSetEditorEdit) -> Void = { _ in }
    var done: () -> Void = {}

    @State private var contentHeight: CGFloat = 0
    @State private var typing: Typing?
    @State private var typedText = ""
    @FocusState private var focused: Bool

    struct Typing: Equatable {
        enum Field { case weight, reps }
        var row: Int
        var field: Field
    }

    /// Estimated before the list has laid out, then measured.
    private var sheetHeight: CGFloat {
        let content = contentHeight > 0 ? contentHeight : CGFloat(150 + model.rows.count * 128 + 100)
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
                CutRepeatStepButton(systemImage: "minus", label: "Decrease \(name)", isEnabled: canDecrease) {
                    apply(down)
                }
                CutRepeatStepButton(systemImage: "plus", label: "Increase \(name)", isEnabled: true) {
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

/// A grey pill step button: one step on tap, repeating every tenth of a second while held.
private struct CutRepeatStepButton: View {
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
