//
//  ConnectionsView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


import SwiftUI
import Combine
struct ConnectionsView: View {
    @StateObject private var vm = ConnectionsViewModel()
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        // The one Cut branch point: same view model, authorization, sync and disconnect.
        if DS.Redesign.cutEnabled {
            CutConnectionsHost()
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        List {
            Section {
                ConnectionRow(
                    provider: vm.health,
                    onConnect:   { Task { await vm.connect(.health)   } },
                    onDisconnect:{ Task { await vm.disconnect(.health)} },
                    onSync:      { Task { await vm.sync(.health)      } }
                )
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Sync workouts, active energy, exercise minutes, runs and more from Apple Health.")
                    .dsFont(.caption)
            }
            .onAppear {
                vm.setHealthKitManager(healthKit)
            }
        }
        .navigationTitle("Apple Health")
    }
}
// MARK: - View model & provider types

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var health = ConnectionProvider.health()
    @Published private(set) var strava = ConnectionProvider.strava()
    @Published private(set) var icloud = ConnectionProvider.icloud()

    private weak var healthKitManager: HealthKitManager?
    private var healthSubscription: AnyCancellable?
    /// The manager's state as last published; the Apple Health status is derived from it.
    private var managerFacts: ConnectionProvider.HealthFacts?
    /// Only the page knows these two: its own authorization attempt failed, or its own
    /// "Sync now" is still running (the exercise time half does not publish isSyncing).
    private var authorizationFailed = false
    private var pageSyncRunning = false

    enum Kind { case health, strava, icloud }

    /// Follows the manager: a sync started, finished or failed anywhere in the app updates
    /// the status, not only this page's own actions.
    func setHealthKitManager(_ manager: HealthKitManager) {
        guard healthKitManager !== manager || healthSubscription == nil else { return }
        healthKitManager = manager
        healthSubscription = Publishers.CombineLatest4(
            manager.$connectionState, manager.$isSyncing, manager.$lastSyncDate, manager.$syncError.map { $0 != nil }
        )
        .sink { [weak self] state, isSyncing, lastSync, syncFailed in
            self?.managerFacts = .init(state: state, isSyncing: isSyncing, lastSync: lastSync, syncFailed: syncFailed)
            self?.updateHealthProviderState()
        }
    }

    private func updateHealthProviderState() {
        guard let managerFacts else { return }
        health = ConnectionProvider(
            name: "Apple Health",
            icon: "heart.fill",
            status: .health(managerFacts, pageSyncRunning: pageSyncRunning, authorizationFailed: authorizationFailed),
            storageKey: "conn_health"
        )
    }

    func connect(_ kind: Kind) async {
        switch kind {
        case .health:
            guard let hkm = healthKitManager else { return }
            do {
                try await hkm.requestAuthorization()
                await hkm.setupBackgroundObservers()
                authorizationFailed = false
            } catch {
                authorizationFailed = true
            }
            updateHealthProviderState()
        default:
            await mutate(kind) { await $0.connect() }
        }
    }

    func disconnect(_ kind: Kind) async {
        switch kind {
        case .health:
            guard let hkm = healthKitManager else { return }
            authorizationFailed = false
            hkm.connectionState = .disconnected
            hkm.stopBackgroundObservers()
            updateHealthProviderState()
        default:
            await mutate(kind) { await $0.disconnect() }
        }
    }

    func sync(_ kind: Kind) async {
        switch kind {
        case .health:
            guard let hkm = healthKitManager else { return }
            pageSyncRunning = true
            updateHealthProviderState()
            await hkm.syncWorkoutsIncremental()
            await hkm.syncExerciseTimeIncremental()
            pageSyncRunning = false
            updateHealthProviderState()
        default:
            await mutate(kind) { await $0.sync() }
        }
    }

    // Reassign after mutation so @Published emits
    private func mutate(_ kind: Kind, _ op: (inout ConnectionProvider) async -> Void) async {
        switch kind {
        case .health:
            var x = health;   await op(&x);   health = x
        case .strava:
            var x = strava;   await op(&x);   strava = x
        case .icloud:
            var x = icloud;   await op(&x);   icloud = x
        }
    }
}

struct ConnectionProvider: Identifiable {
    enum Status: Equatable {
        case notConnected
        case connected(lastSync: Date?)
        case syncing
        /// Connected, but the last sync anywhere in the app failed.
        case syncFailed
        case error(String)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.notConnected, .notConnected): return true
            case (.connected(let a), .connected(let b)): return a == b
            case (.syncFailed, .syncFailed): return true
            case (.syncing, .syncing): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }

        /// The Apple Health status from the manager's state. An authorization failure on the
        /// page wins; otherwise not connected, syncing, a failed last sync, or connected.
        static func health(_ facts: HealthFacts, pageSyncRunning: Bool = false, authorizationFailed: Bool = false) -> Status {
            if authorizationFailed { return .error("Authorization failed") }
            guard facts.state == .connected else { return .notConnected }
            if facts.isSyncing || pageSyncRunning { return .syncing }
            if facts.syncFailed { return .syncFailed }
            return .connected(lastSync: facts.lastSync)
        }
    }

    /// What HealthKitManager publishes that the Apple Health status depends on.
    struct HealthFacts: Equatable {
        var state: HealthConnectionState
        var isSyncing: Bool
        var lastSync: Date?
        var syncFailed: Bool
    }

    let id = UUID()
    let name: String
    let icon: String
    var status: Status
    let storageKey: String  // persisted flag

    // Make initializer public so we can create instances from ViewModel
    init(name: String, icon: String, status: Status, storageKey: String) {
        self.name = name
        self.icon = icon
        self.status = status
        self.storageKey = storageKey
    }

    // MARK: lifecycle hooks (swap with real SDKs later)
    mutating func connect() {
        UserDefaults.standard.set(true, forKey: storageKey)
        status = .connected(lastSync: nil)
    }

    mutating func disconnect() {
        UserDefaults.standard.set(false, forKey: storageKey)
        status = .notConnected
    }

    @MainActor
    mutating func sync() async {
        guard case .connected = status else { return }
        status = .syncing

        // iOS 17+: nicer API
        // try? await Task.sleep(for: .seconds(1))
        // iOS 15+:
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        status = .connected(lastSync: Date())
    }

    static func health() -> ConnectionProvider {
        let isOn = UserDefaults.standard.bool(forKey: "conn_health")
        return .init(name: "Apple Health", icon: "heart.fill", status: isOn ? .connected(lastSync: nil) : .notConnected, storageKey: "conn_health")
    }
    static func strava() -> ConnectionProvider {
        let isOn = UserDefaults.standard.bool(forKey: "conn_strava")
        return .init(name: "Strava", icon: "figure.run", status: isOn ? .connected(lastSync: nil) : .notConnected, storageKey: "conn_strava")
    }
    static func icloud() -> ConnectionProvider {
        let isOn = UserDefaults.standard.bool(forKey: "conn_icloud")
        return .init(name: "iCloud", icon: "icloud", status: isOn ? .connected(lastSync: nil) : .notConnected, storageKey: "conn_icloud")
    }
}

// MARK: - Reusable row
private struct ConnectionRow: View {
    let provider: ConnectionProvider
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onSync: () -> Void

    private static let relFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var statusText: String {
        switch provider.status {
        case .notConnected:
            return "Not connected"
        case .connected(let last):
            if let last {
                let rel = Self.relFmt.localizedString(for: last, relativeTo: Date())
                return "Connected • Last sync \(rel)"
            } else {
                return "Connected"
            }
        case .syncing:
            return "Syncing…"
        case .syncFailed:
            return "Connected • Last sync failed"
        case .error(let msg):
            return "Error • \(msg)"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)          // use environment tint
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name).dsFont(.subheadline, weight: .semibold)
                Text(statusText).dsFont(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            switch provider.status {
            case .notConnected:
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)

            case .connected, .syncFailed:
                Menu {
                    Button("Sync now", action: onSync)
                    Button("Disconnect", role: .destructive, action: onDisconnect)
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .dsFont(.title3)
                }

            case .syncing:
                ProgressView().controlSize(.small)

            case .error:
                Button("Retry", action: onConnect)
            }
        }
        .contentShape(Rectangle())
    }
}
