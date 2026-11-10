import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class PlannerOrderingTests: XCTestCase {
    func testWorkoutDayOrderSurvivesDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([WorkoutSplit.self, PlanBlock.self, PlanBlockExercise.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("plans.store"))
        let anchor = Calendar.current.startOfDay(for: Date())
        let names = ["Rest", "Push", "Pull", "Legs"]

        func writePlans() throws {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            for _ in 0..<10 {
                let blocks = names.map { PlanBlock(dayName: $0, isRestDay: $0 == "Rest") }
                context.insert(WorkoutSplit(name: "PPL", planBlocks: blocks, anchorDate: anchor))
            }
            try context.save()
        }
        try writePlans()

        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let plans = try context.fetch(FetchDescriptor<WorkoutSplit>())
        XCTAssertEqual(plans.count, 10)
        for plan in plans {
            XCTAssertEqual(plan.orderedPlanBlocks.map(\.dayName), names)
            for (offset, name) in names.enumerated() {
                let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: offset, to: anchor))
                XCTAssertEqual(plan.planBlock(for: date, cursor: 0)?.dayName, name)
            }
        }
    }
}
