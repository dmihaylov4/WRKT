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
        List {
            Section("Apple Health") {
                ConnectionRow(
                    provider: vm.health,
                    onConnect:   { Task { await vm.connect(.health)   } },
                    onDisconnect:{ Task { await vm.disconnect(.health)} },
                    onSync:      { Task { await vm.sync(.health)      } }
                )
                Text("Sync workouts, active energy, runs and more.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onAppear {
                vm.setHealthKitManager(healthKit)
            }

            Section("Strava") {
                ConnectionRow(
                    provider: vm.strava,
                    onConnect:   { Task { await vm.connect(.strava)   } },
                    onDisconnect:{ Task { await vm.disconnect(.strava)} },
                    onSync:      { Task { await vm.sync(.strava)      } }
                )
                Text("Share runs to Strava and import activities.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cloud") {
                ConnectionRow(
                    provider: vm.icloud,
                    onConnect:   { Task { await vm.connect(.icloud)   } },
                    onDisconnect:{ Task { await vm.disconnect(.icloud)} },
                    onSync:      { Task { await vm.sync(.icloud)      } }
                )
                Text("Back up your data and sync across devices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connections")
    }
}
// MARK: - View model & provider types

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var health = ConnectionProvider.health()
    @Published private(set) var strava = ConnectionProvider.strava()
    @Published private(set) var icloud = ConnectionProvider.icloud()

    private weak var healthKitManager: HealthKitManager?

    enum Kind { case health, strava, icloud }

    func setHealthKitManager(_ manager: HealthKitManager) {
        self.healthKitManager = manager
        // Sync initial state
        updateHealthProviderState()
    }

    private func updateHealthProviderState() {
        guard let hkm = healthKitManager else { return }

        let status: ConnectionProvider.Status
        switch hkm.connectionState {
        case .connected:
            status = .connected(lastSync: hkm.lastSyncDate)
        case .disconnected, .limited:
            status = .notConnected
        }

        health = ConnectionProvider(
            name: "Apple Health",
            icon: "heart.fill",
            status: status,
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
                updateHealthProviderState()
            } catch {
                health.status = .error("Authorization failed")
            }
        default:
            await mutate(kind) { await $0.connect() }
        }
    }

    func disconnect(_ kind: Kind) async {
        switch kind {
        case .health:
            guard let hkm = healthKitManager else { return }
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
            health.status = .syncing
            await hkm.syncWorkoutsIncremental()
            await hkm.syncExerciseTimeIncremental()
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
        case error(String)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.notConnected, .notConnected): return true
            case (.connected(let a), .connected(let b)): return a == b
            case (.syncing, .syncing): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
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
                Text(provider.name).font(.subheadline.weight(.semibold))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            switch provider.status {
            case .notConnected:
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)

            case .connected:
                Menu {
                    Button("Sync now", action: onSync)
                    Button("Disconnect", role: .destructive, action: onDisconnect)
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
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
