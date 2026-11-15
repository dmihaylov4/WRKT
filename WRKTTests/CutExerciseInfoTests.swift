import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutExerciseInfoTests {
    @Test func plainMetadataMuscleLayersAndRestSource() {
        var exercise = CutExerciseFixtures.exercises[0]
        exercise.secondaryMuscles = ["Triceps"]
        exercise.tertiaryMuscles = ["Shoulders"]
        let model = CutExerciseInfoFixtures.model(exercise: exercise)
        #expect(model.metadata == "Barbell · Intermediate")
        #expect(model.muscles.map(\.title) == ["Primary", "Secondary", "Tertiary"])
        #expect(model.muscles.map(\.value) == ["Chest", "Triceps", "Shoulders"])
        #expect(model.restTime == "2:00")
        #expect(model.restSource == "Compound Default")
        #expect(!model.canEdit)
        #expect(model.videoURL == nil)
    }

    @Test func customExerciseAndOverrideAndIsolationStates() {
        var exercise = CutExerciseFixtures.exercises[1]
        exercise.isCustom = true
        let model = CutExerciseInfoLogic.model(exercise: exercise, meta: CutExerciseInfoFixtures.meta, videoURL: nil,
            progression: nil, unit: .kg, restSeconds: 75, hasOverride: true)
        #expect(model.canEdit)
        #expect(model.restSource == "Custom")
        #expect(model.restTime == "1:15")
        #expect(CutExerciseInfoFixtures.model(exercise: CutExerciseFixtures.exercises[1]).restSource == "Isolation Default")
        #expect(model.progression.isEmpty)
    }

    @Test func progressionConvertsWeightUnitsAndKeepsReason() {
        let suggestion = ProgressionSuggestion(suggestedWeight: 22.5, suggestedReps: 8, previousWeight: 20,
            reason: "Ready to increase", type: .increaseWeight)
        let kg = CutExerciseInfoFixtures.model(progression: suggestion)
        #expect(kg.progression.map(\.value) == ["20.0kg", "22.5kg"])
        #expect(kg.progressionReason == "Ready to increase")
        let lb = CutExerciseInfoFixtures.model(progression: suggestion, unit: .lb)
        #expect(lb.progression.map(\.value) == ["44.1lb", "49.6lb"])
    }

    @Test func bodyweightRepetitionProgressionAndCuesMatchLegacy() {
        let suggestion = ProgressionSuggestion(suggestedWeight: 0, suggestedReps: 12, previousWeight: 0,
            reason: "Add one rep", type: .increaseReps)
        #expect(CutExerciseInfoFixtures.model(progression: suggestion).progression.map(\.value) == ["11 reps", "12 reps"])
        let cues = ["One", "Two", "Three", "Four"]
        #expect(CutExerciseInfoLogic.visibleCues(cues, expanded: false) == Array(cues.prefix(3)))
        #expect(CutExerciseInfoLogic.visibleCues(cues, expanded: true) == cues)
        #expect(CutExerciseInfoLogic.visibleCues([], expanded: false).isEmpty)
    }
}

@MainActor
enum CutExerciseInfoFixtures {
    static let meta = ExerciseGuideMeta(difficulty: "Intermediate", equipment: "Barbell", classification: "Strength",
        mechanics: "Compound", forceType: "Push", pattern: "Horizontal Push", plane: "Transverse", posture: "Lying",
        grip: "Pronated", laterality: "Bilateral", cues: ["Keep your feet planted.", "Lower the bar with control.",
            "Press evenly through both arms.", "Keep your shoulder blades set."])

    static func model(exercise: Exercise = CutExerciseFixtures.exercises[0], progression: ProgressionSuggestion? = nil,
                      unit: WeightUnit = .kg) -> CutExerciseInfoModel {
        CutExerciseInfoLogic.model(exercise: exercise, meta: meta, videoURL: nil, progression: progression,
            unit: unit, restSeconds: 120, hasOverride: false)
    }
}
