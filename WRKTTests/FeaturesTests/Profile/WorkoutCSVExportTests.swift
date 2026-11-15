import Foundation
import Testing
@testable import WRKT

@Suite("Workout CSV export")
struct WorkoutCSVExportTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// Locks the file byte for byte: one row per set, oldest workout first, and a Completed
    /// column (the old file wrote a check mark under "Notes").
    @Test func fileLayout() {
        let early = CompletedWorkout(date: Date(timeIntervalSince1970: 1_794_571_200), entries: [
            WorkoutEntry(exerciseID: "bench", exerciseName: "Bench Press", muscleGroups: ["Chest"], sets: [
                SetInput(reps: 5, weight: 100, tag: .working, autoWeight: false, isCompleted: true),
                SetInput(reps: 8, weight: 80.5, tag: .backoff, autoWeight: false, isCompleted: false)
            ])
        ])
        let late = CompletedWorkout(date: Date(timeIntervalSince1970: 1_794_657_600), entries: [
            WorkoutEntry(exerciseID: "squat", exerciseName: "Squat", muscleGroups: ["Legs"], sets: [
                SetInput(reps: 10, weight: 60, tag: .warmup, autoWeight: false, isCompleted: true)
            ])
        ])
        #expect(WorkoutCSVExport.csv([late, early], timeZone: utc) == """
        Date,Exercise,Set Number,Tag,Reps,Weight (kg),Completed
        "2026-11-13 12:00:00","Bench Press",1,"Working",5,100.0,Yes
        "2026-11-13 12:00:00","Bench Press",2,"Back-off",8,80.5,No
        "2026-11-14 12:00:00","Squat",1,"Warm-up",10,60.0,Yes

        """)
        #expect(WorkoutCSVExport.csv([]) == "Date,Exercise,Set Number,Tag,Reps,Weight (kg),Completed\n")
    }

    @Test func noColumnIsMislabelledNotes() {
        let columns = WorkoutCSVExport.header.split(separator: ",")
        #expect(!columns.contains("Notes"))
        #expect(columns.last == "Completed")
    }

    /// A quote in an exercise name used to end the field early and shift every later column.
    @Test func quotesInsideAFieldAreDoubled() {
        let workout = CompletedWorkout(date: Date(timeIntervalSince1970: 1_794_571_200), entries: [
            WorkoutEntry(exerciseID: "c", exerciseName: "Press \"close\", grip", muscleGroups: [], sets: [
                SetInput(reps: 3, weight: 40, tag: .working, autoWeight: false, isCompleted: true)
            ])
        ])
        let row = WorkoutCSVExport.csv([workout], timeZone: utc).split(separator: "\n")[1]
        #expect(row == #""2026-11-13 12:00:00","Press ""close"", grip",1,"Working",3,40.0,Yes"#)
    }
}
