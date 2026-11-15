import Foundation
import Testing
@testable import WRKT

@Suite("Apple Health status follows HealthKitManager", .serialized)
@MainActor
struct ConnectionsHealthStatusTests {
    private typealias Status = ConnectionProvider.Status
    private struct SyncFailed: Error {}
    private let last = Date(timeIntervalSince1970: 1_794_571_200)

    // MARK: Derivation

    @Test func statusFromTheManagersState() {
        let connected = ConnectionProvider.HealthFacts(state: .connected, isSyncing: false, lastSync: last, syncFailed: false)
        #expect(Status.health(connected) == .connected(lastSync: last))
        var facts = connected
        facts.isSyncing = true
        #expect(Status.health(facts) == .syncing)
        facts.isSyncing = false
        facts.syncFailed = true
        #expect(Status.health(facts) == .syncFailed)
        #expect(Status.health(connected, pageSyncRunning: true) == .syncing)
        #expect(Status.health(connected, authorizationFailed: true) == .error("Authorization failed"))
        for state in [HealthConnectionState.disconnected, .limited] {
            facts.state = state
            #expect(Status.health(facts) == .notConnected)
        }
    }

    @Test func aFailedSyncStillOffersSyncAndDisconnect() {
        let model = CutConnectionsLogic.model(.syncFailed)
        #expect(model.statusLine == "Connected, last sync failed")
        #expect(model.primary == .sync)
        #expect(model.showsDisconnect)
    }

    // MARK: The view model observes the manager

    @Test func aSyncElsewhereUpdatesThePage() {
        let key = "healthkit.connectionState"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let manager = HealthKitManager()
        manager.connectionState = .connected
        let vm = ConnectionsViewModel()
        vm.setHealthKitManager(manager)
        #expect(vm.health.status == .connected(lastSync: nil))

        // A sync started and finished by something else, not by the page.
        manager.isSyncing = true
        #expect(vm.health.status == .syncing)
        manager.lastSyncDate = last
        manager.isSyncing = false
        #expect(vm.health.status == .connected(lastSync: last))

        // A failure elsewhere, then a later success.
        manager.syncError = SyncFailed()
        #expect(vm.health.status == .syncFailed)
        manager.syncError = nil
        #expect(vm.health.status == .connected(lastSync: last))

        // Disconnected from elsewhere.
        manager.connectionState = .disconnected
        #expect(vm.health.status == .notConnected)
    }
}
