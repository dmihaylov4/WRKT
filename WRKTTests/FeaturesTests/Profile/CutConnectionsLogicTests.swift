import Foundation
import Testing
@testable import WRKT

@Suite("Cut Connections logic")
struct CutConnectionsLogicTests {
    private let now = Date(timeIntervalSince1970: 1_794_571_200)
    private let locale = Locale(identifier: "en_GB")

    @Test func notConnectedOffersConnect() {
        let model = CutConnectionsLogic.model(.notConnected, now: now, locale: locale)
        #expect(model.statusLine == "Not connected")
        #expect(model.primary == .connect)
        #expect(model.primary.title == "Connect")
        #expect(!model.showsDisconnect)
        #expect(model.title == "Apple Health")
    }

    @Test func connectedOffersSyncAndDisconnect() {
        let model = CutConnectionsLogic.model(.connected(lastSync: nil), now: now, locale: locale)
        #expect(model.statusLine == "Connected")
        #expect(model.primary == .sync)
        #expect(model.primary.title == "Sync now")
        #expect(model.showsDisconnect)
    }

    @Test func connectedNamesTheLastSync() {
        let line = CutConnectionsLogic.statusLine(.connected(lastSync: now.addingTimeInterval(-300)), now: now, locale: locale)
        #expect(line.hasPrefix("Connected, last sync "))
        #expect(line.contains("5"))
    }

    @Test func syncingDisablesThePill() {
        let model = CutConnectionsLogic.model(.syncing, now: now, locale: locale)
        #expect(model.statusLine == "Syncing")
        #expect(model.primary == .syncing)
        #expect(!model.primary.isEnabled)
        #expect(!model.showsDisconnect)
    }

    @Test func errorOffersRetry() {
        let model = CutConnectionsLogic.model(.error("Authorization failed"), now: now, locale: locale)
        #expect(model.statusLine == "Error: Authorization failed")
        #expect(model.primary == .retry)
        #expect(model.primary.isEnabled)
        #expect(!model.showsDisconnect)
    }
}
