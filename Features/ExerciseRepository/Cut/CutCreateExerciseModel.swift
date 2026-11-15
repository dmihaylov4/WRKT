import Foundation

struct CutCreateExerciseModel: Equatable {
    var name = ""
    var muscle = "Chest"
    var equipment = EquipBucket.bodyweight
    var movement = MoveBucket.other
    var mechanic = "compound"
    var difficulty: DifficultyLevel?
    var isEditing = false
    var title: String { isEditing ? "Edit Exercise" : "New Exercise" }
    var actionTitle: String { isEditing ? "Save" : "Create" }
    var canSave: Bool { CutCreateExerciseLogic.validationMessage(name: name) == nil }
}

enum CutCreateExerciseLogic {
    static let muscles = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms", "Abs", "Obliques",
                          "Glutes", "Quads", "Hamstrings", "Calves", "Adductors", "Abductors"]

    static func model(preselectedMuscle: String, editing: Exercise?) -> CutCreateExerciseModel {
        if let editing {
            return .init(name: editing.name, muscle: editing.primaryMuscles.first ?? preselectedMuscle,
                         equipment: editing.equipBucket, movement: editing.moveBucket,
                         mechanic: editing.mechanic ?? "compound", difficulty: editing.difficultyLevel, isEditing: true)
        }
        return .init(muscle: preselectedMuscle.isEmpty ? "Chest" : preselectedMuscle)
    }

    static func validationMessage(name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Please enter an exercise name" : nil
    }

    static func exercise(form: CutCreateExerciseModel, id: String) -> Exercise? {
        guard form.canSave else { return nil }
        return Exercise(id: id, name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            force: force(form.movement), level: form.difficulty?.rawValue, mechanic: form.mechanic,
            equipment: equipment(form.equipment), secondaryEquipment: nil, grip: nil,
            primaryMuscles: [form.muscle], secondaryMuscles: [], tertiaryMuscles: [], instructions: [],
            images: nil, category: form.muscle.lowercased(), subregionTags: [form.muscle], isCustom: true)
    }

    static func force(_ bucket: MoveBucket) -> String? {
        switch bucket {
        case .push, .squat: return "push"
        case .pull, .hinge: return "pull"
        case .core, .other, .all: return nil
        }
    }

    static func equipment(_ bucket: EquipBucket) -> String? {
        switch bucket {
        case .all, .bodyweight: return nil
        case .barbell: return "Barbell"
        case .cable: return "Cable"
        case .dumbbell: return "Dumbbell"
        case .ezBar: return "EZ Bar"
        case .kettlebell: return "Kettlebell"
        case .pullupbar: return "Pullup Bar"
        case .other: return "Other"
        }
    }
}
