//
//  CutConnectionsHost.swift
//  WRKT
//
//  ConnectionsView's state behind the Cut page: the same ConnectionsViewModel, which follows the
//  shared HealthKitManager's published state from appear on, and the same connect
//  (authorization, then background observers), incremental sync and disconnect calls. What is
//  requested from HealthKit, and when, is unchanged.
//

import SwiftUI

struct CutConnectionsHost: View {
    @StateObject private var vm = ConnectionsViewModel()
    @EnvironmentObject private var healthKit: HealthKitManager

    var body: some View {
        CutConnectionsView(
            model: CutConnectionsLogic.model(vm.health.status),
            actions: CutConnectionsActions(
                connect: { Task { await vm.connect(.health) } },
                sync: { Task { await vm.sync(.health) } },
                disconnect: { Task { await vm.disconnect(.health) } }
            )
        )
        .onAppear {
            vm.setHealthKitManager(healthKit)
        }
    }
}
