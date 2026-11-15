import Foundation
import Testing
@testable import WRKT

@Suite("Cut Diagnostics logic")
struct CutDiagnosticsLogicTests {
    @Test func defaultsHaveNoStatus() {
        let model = CutDiagnosticsModel()
        #expect(model.statusMessage == nil)
        #expect(model.title == "Diagnostics")
        #expect(model.footer.contains("not passwords or tokens"))
    }

    @Test func statusMessagesKeepTheLegacyCopy() {
        #expect(CutDiagnosticsLogic.clearedMessage == "Diagnostics cleared.")
        #expect(CutDiagnosticsLogic.exportFailedMessage("disk full") == "Could not prepare diagnostics: disk full")
        #expect(CutDiagnosticsLogic.clearFailedMessage("locked") == "Could not clear diagnostics: locked")
    }
}

@Suite("Cut Streak recovery logic")
struct CutStreakRecoveryLogicTests {
    @Test func titleNamesTheEndedStreak() {
        #expect(CutStreakRecoveryLogic.model(brokenStreak: 6).title == "6-week streak ended")
        #expect(CutStreakRecoveryLogic.model(brokenStreak: 1).title == "1-week streak ended")
        #expect(CutStreakRecoveryLogic.model(brokenStreak: 6).line
                == "The fastest way to rebuild: make the next streak public from the start.")
    }
}
