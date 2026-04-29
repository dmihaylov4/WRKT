import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class PlannerStoreActivationTests: WRKTTestCase {

    func testActivationAlignsSelectedStartDateToFirstWorkout() throws {
        let schema = Schema([
            PlannedWorkout.self,
            PlannedExercise.self,
            WorkoutSplit.self,
            PlanBlock.self,
            PlanBlockExercise.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let plannerStore = PlannerStore.shared
        plannerStore.configure(
            container: container,
            context: context,
            workoutStore: WorkoutStoreV2()
        )

        let rest = PlanBlock(dayName: "Rest", exercises: [], isRestDay: true)
        let push = PlanBlock(
            dayName: "Push",
            exercises: [
                PlanBlockExercise(
                    exerciseID: "bench-press",
                    exerciseName: "Bench Press",
                    sets: 3,
                    reps: 8,
                    startingWeight: 80,
                    progressionStrategy: .static,
                    order: 0
                )
            ],
            isRestDay: false
        )
        let split = WorkoutSplit(
            name: "Imported Plan",
            planBlocks: [rest, push],
            anchorDate: makeDate(year: 2026, month: 4, day: 1),
            reschedulePolicy: .strict
        )
        split.isActive = false
        context.insert(split)
        try context.save()

        let selectedStartDate = makeDate(year: 2026, month: 4, day: 21, hour: 0, minute: 0)
        try plannerStore.activate(
            split,
            customization: ActivationCustomization(
                startDate: selectedStartDate,
                restDayOverrides: [
                    rest.id: true,
                    push.id: false
                ],
                startingWeights: [:]
            )
        )

        let plannedWorkouts = try plannerStore.plannedWorkouts(
            from: selectedStartDate,
            to: makeDate(year: 2026, month: 4, day: 24, hour: 0, minute: 0)
        )

        XCTAssertEqual(plannedWorkouts.first?.scheduledDate, selectedStartDate)
        XCTAssertEqual(plannedWorkouts.first?.splitDayName, "Push")
        XCTAssertEqual(split.anchorDate, makeDate(year: 2026, month: 4, day: 20, hour: 0, minute: 0))
    }
}
