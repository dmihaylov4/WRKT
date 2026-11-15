//
//  CutStartSheetView.swift
//  WRKT
//
//  The start choices use the shared raised sheet and inset rows.
//  Each selection keeps the parent's existing navigation callback.
//

import SwiftUI

struct CutStartSheetView: View {
    let model: CutStartSheetModel
    var onStartPlan: () -> Void = {}
    var onSelect: (QuickWorkoutTypeSelector.WorkoutType) -> Void = { _ in }
    var onCancel: () -> Void = {}

    var body: some View {
        CutSheet(model.title, kind: .choice, close: onCancel) {
            CutSheetInset {
                if let plan = model.plan {
                    Button { onStartPlan(); Haptics.light() } label: {
                        CutSheetInsetRow(plan.name, value: CutStartSheetLogic.planLine(plan))
                    }.buttonStyle(.plain)
                    CutHairline()
                }
                ForEach(Array(model.choices.enumerated()), id: \.element) { index, type in
                    if index > 0 { CutHairline() }
                    Button { onSelect(type); Haptics.light() } label: {
                        HStack(spacing: 12) {
                            Text(CutStartSheetLogic.choiceTitle(type))
                                .font(DS.Typography.custom(size: 19, weight: .semibold, relativeTo: .body))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary).accessibilityHidden(true)
                        }
                        .frame(minHeight: 68).padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 12).padding(.bottom, 24)
        }
    }

}

#if DEBUG
enum CutStartSheetFixtures {
    static let plan = CutStartSheetPlan(name: "Upper Body", exerciseCount: 6)
    static let withPlan = CutStartSheetLogic.model(legacyTitle: "Start Workout", plan: plan)
    static let withoutPlan = CutStartSheetLogic.model(legacyTitle: "Start Workout", plan: nil)
    static let addExercise = CutStartSheetLogic.model(legacyTitle: "Add Exercise", plan: nil)
}

#Preview("Cut start sheet") {
    Color.black.sheet(isPresented: .constant(true)) {
        CutStartSheetView(model: CutStartSheetFixtures.withPlan)
    }
}
#endif
