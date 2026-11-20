//
//  CutStartSheetView.swift
//  WRKT
//
//  The start workout sheet in the Cut language: one sheet surface, a 17 pt title and Cancel,
//  today's planned session first as a lime condensed name with a cut-corner arrow tile,
//  then the other choices as condensed rows between hairlines. Plain values and closures only.
//  Kept apart from the shared sheet family on purpose: the owner prefers these large rows
//  to the family's inset card for this sheet.
//

import SwiftUI

struct CutStartSheetView: View {
    let model: CutStartSheetModel
    var onStartPlan: () -> Void = {}
    var onSelect: (QuickWorkoutTypeSelector.WorkoutType) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

    /// The sheet is as tall as its rows: measured once laid out, estimated for the first frame.
    private var sheetHeight: CGFloat {
        headerHeight > 0 && listHeight > 0
            ? headerHeight + listHeight
            : CutStartSheetLogic.estimatedHeight(model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
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
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.hidden)
            // Only scrolls when the rows outgrow the screen (large text sizes).
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(sheetHeight)])
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        CutStartSheetHeader(title: model.title, onCancel: onCancel)
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
                        Text(line)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
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
        .accessibilityLabel(Text("Start \(plan.name). \(line)"))
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

/// The start sheet's small title row: a 17 pt title and a lime Cancel. Shared with the
/// past workouts sheet, which is presented the same way.
struct CutStartSheetHeader: View {
    let title: String
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
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
