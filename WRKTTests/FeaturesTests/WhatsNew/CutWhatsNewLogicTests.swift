import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutWhatsNewLogicTests {
    @Test func buttonOpensTheDestinationOrSaysGotIt() {
        #expect(CutWhatsNewLogic.buttonTitle(for: .rack) == "See your rack")
        #expect(CutWhatsNewLogic.buttonTitle(for: nil) == "Got it")
        let plain = WhatsNewRelease(version: "9.0", title: "Fixture release", bullets: ["One"])
        #expect(plain.destination == nil)
        #expect(CutWhatsNewLogic.model(release: plain, currentVersion: "9.0").buttonTitle == "Got it")
        let rack = WhatsNewRelease(version: "9.0", title: "Fixture release", bullets: ["One"], destination: .rack)
        let model = CutWhatsNewLogic.model(release: rack, currentVersion: "9.0")
        #expect(model.buttonTitle == "See your rack")
        #expect(model.destination == .rack)
    }

    @Test func modelCarriesTheVersionTitleAndEveryPoint() {
        let release = WhatsNewRelease(version: "9.0", title: "Fixture release", bullets: ["One", "Two", "Three"])
        let model = CutWhatsNewLogic.model(release: release, currentVersion: "9.0")
        #expect(model.eyebrow == "New in 9.0")
        #expect(model.title == "Fixture release")
        #expect(model.points == ["One", "Two", "Three"])
        #expect(CutWhatsNewLogic.model(release: release, currentVersion: "").eyebrow == "New in VOLIA")
    }

    @Test func theShippedBarbellReleaseOpensTheRack() throws {
        let release = try #require(WhatsNewManager.releases.first { $0.version == "5.1.1" })
        #expect(release.destination == .rack)
        #expect(CutWhatsNewLogic.model(release: release, currentVersion: "5.1.1").buttonTitle == "See your rack")
    }
}
