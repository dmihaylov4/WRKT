//
//  CutConnectionsModel.swift
//  WRKT
//
//  What the Cut Apple Health page shows for a ConnectionProvider status, as plain values: the
//  status line under the title, the one action pill (Connect, Sync now, Syncing, Retry), and
//  whether Disconnect is offered. The states and actions are ConnectionsView's.
//

import Foundation

struct CutConnectionsModel: Equatable {
    /// The pill under the title; the same place in every state.
    enum Primary: Equatable {
        /// Not connected: asks for Health access.
        case connect
        /// Connected: an incremental sync.
        case sync
        /// A sync is running: the pill is disabled.
        case syncing
        /// Authorization failed: asks again.
        case retry

        var title: String {
            switch self {
            case .connect: "Connect"
            case .sync: "Sync now"
            case .syncing: "Syncing"
            case .retry: "Retry"
            }
        }

        var isEnabled: Bool { self != .syncing }
    }

    var title = "Apple Health"
    var statusLine: String
    var primary: Primary
    /// Only a connected provider can be disconnected (the legacy Manage menu).
    var showsDisconnect: Bool
    var footer = CutConnectionsLogic.footer
}

enum CutConnectionsLogic {
    static let footer = "Sync workouts, active energy, exercise minutes, runs and more from Apple Health."

    static func model(_ status: ConnectionProvider.Status, now: Date = .now, locale: Locale = .current) -> CutConnectionsModel {
        CutConnectionsModel(statusLine: statusLine(status, now: now, locale: locale),
                            primary: primary(status),
                            showsDisconnect: showsDisconnect(status))
    }

    static func statusLine(_ status: ConnectionProvider.Status, now: Date, locale: Locale = .current) -> String {
        switch status {
        case .notConnected:
            return "Not connected"
        case .connected(let last):
            guard let last else { return "Connected" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            formatter.locale = locale
            return "Connected, last sync \(formatter.localizedString(for: last, relativeTo: now))"
        case .syncing:
            return "Syncing"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    static func primary(_ status: ConnectionProvider.Status) -> CutConnectionsModel.Primary {
        switch status {
        case .notConnected: .connect
        case .connected: .sync
        case .syncing: .syncing
        case .error: .retry
        }
    }

    static func showsDisconnect(_ status: ConnectionProvider.Status) -> Bool {
        if case .connected = status { return true }
        return false
    }
}
