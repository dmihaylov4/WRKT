import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutBattlesListLogicTests {
    let row = CutCompeteItem(id: .battle(UUID()), kind: .battle, title: "Fixture Opponent", line: "Volume")
    @Test func filtersSelectTheirOwnData() {
        for tab in CutBattlesListModel.Tab.allCases {
            let m = CutBattlesListLogic.model(tab: tab, active: tab == .active ? [row] : [], pending: tab == .pending ? [row] : [], completed: tab == .completed ? [row] : [], loading: false, error: nil)
            #expect(m.rows == [row]); #expect(m.empty == nil); #expect(!m.canCreate)
        }
    }
    @Test func activeEmptyHasCreateAction() {
        let m = model(.active)
        #expect(m.empty == "No active battles"); #expect(m.canCreate)
    }
    @Test func otherEmptiesHaveNoCreateAction() {
        #expect(model(.pending).empty == "No pending battles"); #expect(!model(.pending).canCreate)
        #expect(model(.completed).empty == "No completed battles"); #expect(!model(.completed).canCreate)
    }
    @Test func loadingAndFailureDoNotBecomeEmptySuccess() {
        #expect(model(.active, loading: true).empty == nil); #expect(!model(.active, loading: true).canCreate)
        #expect(model(.active, error: "Fixture failure").empty == nil); #expect(!model(.active, error: "Fixture failure").canCreate)
    }
    @Test func pendingCountIncludesOutgoing() {
        let m = CutBattlesListLogic.model(tab: .active, active: [], pending: [row, row], completed: [], loading: false, error: nil)
        #expect(m.pendingCount == 2)
    }
    private func model(_ tab: CutBattlesListModel.Tab, loading: Bool = false, error: String? = nil) -> CutBattlesListModel {
        CutBattlesListLogic.model(tab: tab, active: [], pending: [], completed: [], loading: loading, error: error)
    }
}
