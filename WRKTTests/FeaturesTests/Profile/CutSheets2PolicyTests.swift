import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
@Suite(.serialized)
struct CutSheets2PolicyTests {
    @Test func ageCloseRetainsDoneAndSwipeContracts() {
        var draft = AgeDraft(saved: nil)
        #expect(draft.ageToCommit(confirmed: true) == 30)
        #expect(draft.ageToCommit(confirmed: false) == nil)
        draft.age = 42
        #expect(draft.ageToCommit(confirmed: false) == 42)
        #expect(AgeDraft(saved: 42).ageToCommit(confirmed: true) == nil)
    }

    @Test func bodyweightCommitsOnlyChangedDraftInItsUnit() {
        var draft = BodyweightDraft(kg: 82.5, unit: .kg)
        #expect(draft.kgToCommit == nil)
        draft.tenth = 6
        #expect(draft.kgToCommit == 82.6)
        var pounds = BodyweightDraft(kg: 82.5, unit: .lb)
        #expect(pounds.kgToCommit == nil)
        pounds.whole += 1
        #expect(pounds.kgToCommit != nil)
    }

    @Test func destructiveImportAndRestoreKeepTheirWarnings() {
        #expect(CutDataPortabilityLogic.confirmIsDestructive(.replace))
        #expect(!CutDataPortabilityLogic.confirmIsDestructive(.merge))
        #expect(CutDataPortabilityLogic.confirmTitle(.replace) == "Replace all existing data with this backup?")
        let records = CutDataPortabilityFixtures.records
        let title = CutDataPortabilityLogic.restoreTitle(records: records, restoring: records.first?.id)
        #expect(title.contains("later import(s) will also be removed"))
    }

    @Test func restoreQuestionSeparatesWarningWithoutLosingCopy() {
        let records = CutDataPortabilityFixtures.records
        let first = CutDataPortabilityLogic.restoreConfirmation(records: records, restoring: records.first?.id)
        #expect(first.title == "Restore to this point?")
        #expect(first.message == "2 later import(s) will also be removed.")
        let last = CutDataPortabilityLogic.restoreConfirmation(records: records, restoring: records.last?.id)
        #expect(last.title == "Restore state to before this import?")
        #expect(last.message.isEmpty)
        let missing = CutDataPortabilityLogic.restoreConfirmation(records: [], restoring: nil)
        #expect(missing.title == "Restore to this point?")
        #expect(missing.message.isEmpty)
    }

    @Test func modalWithoutNavigationStackIsRecognized() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        var reading = false
        window.rootViewController = UIHostingController(rootView: Text("Fixture Plan").sheet(isPresented: .constant(true)) {
            Text("Fixture record").background(CutPresentationReader { reading = $0 })
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .seconds(1))
        #expect(reading)
    }
}
