import Testing
@testable import WRKT

struct PlanHeaderActionTests {

    @Test func emptyPlanLibraryStartsPlanCreation() {
        #expect(PlanHeaderAction.primaryAction(hasExistingPlans: false) == .createPlan)
    }

    @Test func existingPlanLibraryOpensProgramLibrary() {
        #expect(PlanHeaderAction.primaryAction(hasExistingPlans: true) == .openProgramLibrary)
    }
}
