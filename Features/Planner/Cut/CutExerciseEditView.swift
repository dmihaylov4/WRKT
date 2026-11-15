//
//  CutExerciseEditView.swift
//  WRKT
//
//  The exercise edit sheet: sets, reps and starting weight, then Save.
//

import SwiftUI

struct CutExerciseEditView: View {
    @State private var model: CutExerciseEditModel
    var level: DS.Cut.SheetLevel = .base
    let save: (_ sets: Int, _ reps: Int, _ weight: Double?) -> Void
    let close: () -> Void
    @FocusState private var weightFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: CutExerciseEditModel, level: DS.Cut.SheetLevel = .base,
         save: @escaping (_ sets: Int, _ reps: Int, _ weight: Double?) -> Void, close: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.level = level
        self.save = save
        self.close = close
    }

    var body: some View {
        CutSheet(model.name, subtitle: model.subtitle, level: level, close: close) {
            VStack(spacing: 10) {
                stepper("Sets", value: model.setsLine, lower: model.canLowerSets, raise: model.canRaiseSets,
                        minus: { CutExerciseEditLogic.stepSets(&model, by: -1) }, plus: { CutExerciseEditLogic.stepSets(&model, by: 1) })
                stepper("Reps", value: model.repsLine, lower: model.canLowerReps, raise: model.canRaiseReps,
                        minus: { CutExerciseEditLogic.stepReps(&model, by: -1) }, plus: { CutExerciseEditLogic.stepReps(&model, by: 1) })
                weightRow
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 24)
        } footer: {
            Button("Save") {
                weightFocused = false
                save(model.sets, model.reps, CutExerciseEditLogic.savedWeight(model))
            }
            .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
    }

    private func stepper(_ label: String, value: String, lower: Bool, raise: Bool, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        rowLayout {
            Text(label)
                .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                roundButton("minus", label: "Fewer " + label.lowercased(), enabled: lower, action: minus)
                Text(value)
                    .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body, monospacedDigits: true))
                    .frame(minWidth: 72)
                    .accessibilityLabel(Text(value))
                roundButton("plus", label: "More " + label.lowercased(), enabled: raise, action: plus)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(level.inset))
    }

    private var weightRow: some View {
        rowLayout {
            Text("Starting weight")
                .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                roundButton("minus", label: "Less weight", enabled: model.canLowerWeight) { CutExerciseEditLogic.stepWeight(&model, up: false) }
                HStack(spacing: 4) {
                    TextField("0", value: $model.weight, format: .number.precision(.fractionLength(0...1)),
                              prompt: Text("0").foregroundStyle(DS.Cut.Colors.textSecondary))
                        .keyboardType(.decimalPad)
                        .focused($weightFocused)
                        .multilineTextAlignment(.trailing)
                        .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body, monospacedDigits: true))
                        .fixedSize()
                    Text(model.unitLabel)
                        .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .frame(minWidth: 72)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Starting weight in \(model.unitLabel)"))
                roundButton("plus", label: "More weight", enabled: true) { CutExerciseEditLogic.stepWeight(&model, up: true) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(level.inset))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    private func roundButton(_ glyph: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                .background(Circle().fill(level.control))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
    }
}
