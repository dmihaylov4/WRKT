import SwiftUI

struct CutExerciseTimerView: View {
    let model: CutExerciseTimerModel
    let minutes: (Int) -> Void
    let seconds: (Int) -> Void
    let save: () -> Void
    let reset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Rest Timer").cutFont(.title)
                Text(model.time)
                    .font(DS.Cut.Typography.condensed(size: 40, relativeTo: .title, monospacedDigits: true))
                    .accessibilityLabel("\(model.minutes) minutes, \(model.seconds) seconds")
                CutHairline()
                HStack(spacing: 16) {
                    wheel("Minutes", values: CutExerciseTimerLogic.minuteChoices(current: model.minutes),
                          selection: model.minutes, change: minutes)
                    wheel("Seconds", values: CutExerciseTimerLogic.secondChoices(current: model.seconds),
                          selection: model.seconds, change: seconds)
                }
                CutHairline()
                if model.hasOverride {
                    Button("Reset to Default", action: reset)
                        .buttonStyle(CutSecondaryButtonStyle(size: .compact))
                }
            }
            .padding(DS.Cut.Metrics.gutter)
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .navigationTitle("Custom Rest Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CUSTOM REST TIMER").font(DS.Cut.Typography.condensed(size: 22, relativeTo: .headline))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).cutFont(.title)
                    .tint(DS.Cut.Colors.lime)
                    .disabled(!model.canSave)
            }
        }
        .shellNavigationBarBackground(DS.Cut.Colors.background)
    }

    private func wheel(_ title: String, values: [Int], selection: Int, change: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            Picker(title, selection: Binding(get: { selection }, set: change)) {
                ForEach(values, id: \.self) { value in Text("\(value)").cutFont(.title).tag(value) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }
}
