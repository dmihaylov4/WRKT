//
//  CutStartSheetView.swift
//  WRKT
//
//  The start workout sheet in the Cut language: one sheet surface, a 17 pt title and Cancel,
//  today's planned session first as a lime condensed name with a cut-corner arrow tile,
//  then the other choices as condensed rows between hairlines. Plain values and closures only.
//

import SwiftUI

struct CutStartSheetView: View {
    let model: CutStartSheetModel
    var onStartPlan: () -> Void = {}
    var onSelect: (QuickWorkoutTypeSelector.WorkoutType) -> Void = { _ in }
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CutHairline()
                    if let plan = model.plan {
                        planRow(plan)
                    }
                    ForEach(model.choices, id: \.self) { type in
                        choiceRow(type)
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(model.title)
                .cutFont(.title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Button("Cancel", action: onCancel)
                .font(DS.Cut.Typography.font(.title))
                .foregroundStyle(DS.Cut.Colors.lime)
                .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func planRow(_ plan: CutStartSheetPlan) -> some View {
        let line = CutStartSheetLogic.planLine(plan)
        return Button {
            onStartPlan()
            Haptics.light()
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        CutHeroText(CutHeroText.balancedLines(plan.name), hero: .m, minimumScaleFactor: 0.25)
                            .foregroundStyle(DS.Cut.Colors.lime)
                        if let line {
                            Text(line)
                                .cutFont(.secondary)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CutTile(systemImage: "arrow.right", side: 60)
                }
                .padding(.vertical, 22)
                CutHairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // On the button itself, so VoiceOver keeps its action.
        .accessibilityLabel(Text(line.map { "Start \(plan.name). \($0)" } ?? "Start \(plan.name)"))
    }

    private func choiceRow(_ type: QuickWorkoutTypeSelector.WorkoutType) -> some View {
        Button {
            onSelect(type)
            Haptics.light()
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text(CutStartSheetLogic.choiceTitle(type))
                        .cutHero(.s, minimumScaleFactor: 0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 72)
                CutHairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CutStartSheetLogic.choiceTitle(type)))
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
