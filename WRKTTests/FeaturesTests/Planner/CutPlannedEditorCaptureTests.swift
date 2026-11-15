import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// Opt-in captures of the Cut planned workout editor (see CutPlanDayCaptureTests for the switch).
@MainActor
struct CutPlannedEditorCaptureTests {
    private typealias F = CutPlannedEditorFixtures

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PLAN_PAGES"] == "1"))
    func captureEditorStates() async throws {
        let date = CutPlanFixtures.day(13)
        func editor(_ isNew: Bool, split: Bool = false, _ drafts: [CutPlannedExerciseDraft], name: String,
                    plateaus: [String: Int] = [:]) -> some View {
            SheetHost {
                NavigationStack {
                    CutPlannedEditorView(
                        model: CutPlannedEditorLogic.model(isNew: isNew, drafts: drafts, plateaus: plateaus, unit: .kg),
                        name: .constant(name), date: .constant(date))
                }
            }
        }
        try await planPageCapture(editor(true, [], name: ""), name: "editor-new-empty")
        try await planPageCapture(editor(true, F.drafts, name: "Upper Body"), name: "editor-new-filled")
        try await planPageCapture(editor(false, split: true, F.drafts, name: "Upper Body", plateaus: ["bench": 4]),
                                  name: "editor-edit-plan")
        try await planPageCapture(SheetHost(dynamicType: .accessibility5) {
            NavigationStack {
                CutPlannedEditorView(
                    model: CutPlannedEditorLogic.model(isNew: false, drafts: F.drafts, plateaus: ["bench": 4], unit: .kg),
                    name: .constant("Upper Body"), date: .constant(date))
            }
        }, name: "editor-edit-ax5")

        let sets: [(String, CutPlannedExerciseDraft, String)] = [
            ("editor-sets", F.drafts[0], ""),
            ("editor-sets-note", F.drafts[1], "Pause at the chest"),
            ("editor-sets-empty", F.drafts[2], "")
        ]
        for (name, draft, notes) in sets {
            try await planPageCapture(SheetHost {
                NavigationStack {
                    CutPlannedSetsView(model: CutPlannedEditorLogic.setsModel(draft, unit: .kg), notes: .constant(notes))
                }
            }, name: name)
        }
    }
}
