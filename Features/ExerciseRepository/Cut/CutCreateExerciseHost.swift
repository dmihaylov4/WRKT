import SwiftUI

struct CutCreateExerciseHost: View {
    let editingExercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var customStore: CustomExerciseStore
    @EnvironmentObject private var repo: ExerciseRepository
    @State private var form: CutCreateExerciseModel
    @State private var validationMessage: String?

    init(preselectedMuscle: String, editingExercise: Exercise?) {
        self.editingExercise = editingExercise
        _form = State(initialValue: CutCreateExerciseLogic.model(preselectedMuscle: preselectedMuscle, editing: editingExercise))
    }

    var body: some View {
        NavigationStack {
            CutCreateExerciseView(model: form, change: { form = $0 }, save: save, cancel: { dismiss() })
                .alert("Validation Error", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
                    Button("OK", role: .cancel) { validationMessage = nil }
                } message: { Text(validationMessage ?? "") }
        }
    }

    private func save() {
        let id = editingExercise?.id ?? "custom_\(UUID().uuidString)"
        guard let exercise = CutCreateExerciseLogic.exercise(form: form, id: id) else {
            validationMessage = CutCreateExerciseLogic.validationMessage(name: form.name)
            return
        }
        if editingExercise == nil { customStore.add(exercise) } else { customStore.update(exercise) }
        Task { await repo.reloadWithCustomExercises() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
