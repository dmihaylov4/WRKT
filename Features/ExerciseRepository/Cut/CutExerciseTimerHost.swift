import SwiftUI

struct CutExerciseTimerHost: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = RestTimerPreferences.shared
    @State private var model = CutExerciseTimerModel(minutes: 0, seconds: 0, hasOverride: false)

    var body: some View {
        CutExerciseTimerView(model: model, minutes: { model.minutes = $0 }, seconds: { model.seconds = $0 }, save: {
            guard model.canSave else { return }
            preferences.setRestDuration(model.totalSeconds, for: exercise.id)
            finish()
        }, reset: {
            preferences.removeOverride(for: exercise.id)
            finish()
        })
        .onAppear {
            model = CutExerciseTimerLogic.model(duration: preferences.restDuration(for: exercise),
                                               hasOverride: preferences.hasOverride(for: exercise.id))
        }
    }
    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
