//
//  CutSettingsModel.swift
//  WRKT
//
//  What the Cut Settings hub shows, as plain values. The rules are SettingsView's: the Social
//  group only when signed in outside local mode, badge counts only when above zero, Log in in
//  local mode, Log out when signed in, and the Debug group only in DEBUG builds.
//

import Foundation

/// The facts the Settings hub depends on, read by CutSettingsHost.
struct CutSettingsFacts: Equatable {
    var isLocalMode = false
    var isLoggedIn = false
    var activityCount = 0
    var friendRequestCount = 0
}

struct CutSettingsModel: Equatable {
    enum Account: Equatable {
        /// Local mode: the row that opens the login sheet.
        case logIn
        /// Signed in: the red Log out row.
        case logOut
        /// Neither: no account row at all.
        case none
    }

    /// The Debug group's rows, in the legacy order.
    enum DebugRow: String, CaseIterable, Identifiable, Equatable {
        case roundedShapes
        case cutDesign
        case replayLaunch
        case barbellPlayground
        case yearReviewMine
        case yearReviewSample
        case yearReviewNextLaunch
        case yearAward3D
        case cutGallery
        case runHistoryMigration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .roundedShapes: "Rounded shapes"
            case .cutDesign: "Cut design"
            case .replayLaunch: "Replay launch animation"
            case .barbellPlayground: "Barbell playground"
            case .yearReviewMine: "Year in review: my data"
            case .yearReviewSample: "Year in review: sample data"
            case .yearReviewNextLaunch: "Year in review: pop up on next launch"
            case .yearAward3D: "Year in review: 3D award"
            case .cutGallery: "Cut gallery"
            case .runHistoryMigration: "Per-workout history migration"
            }
        }

        var subtitle: String? {
            switch self {
            case .roundedShapes, .cutDesign: "Applies after restarting the app"
            case .yearReviewNextLaunch: "Needs the Cut design and five workouts this year"
            case .yearAward3D: "Off shows the SwiftUI plaque"
            case .runHistoryMigration:
                "Simulator and scratch testing only until the v2 merge lands (batch 3b). Starts after launch only when the app is also launched with the migration opt-in argument."
            default: nil
            }
        }

        /// A switch rather than a button.
        var isToggle: Bool { self == .roundedShapes || self == .cutDesign || self == .yearAward3D || self == .runHistoryMigration }

        /// Pushes a page (chevron) rather than acting in place.
        var pushes: Bool { self == .barbellPlayground || self == .cutGallery }
    }

    var title = "Settings"
    var showsSocial: Bool
    /// "3" when there are unread activity items, nil otherwise.
    var activityBadge: String?
    var friendRequestBadge: String?
    var account: Account
    /// Empty outside DEBUG builds.
    var debugRows: [DebugRow]
}

enum CutSettingsLogic {
    static func model(_ facts: CutSettingsFacts) -> CutSettingsModel {
        CutSettingsModel(
            showsSocial: !facts.isLocalMode && facts.isLoggedIn,
            activityBadge: badge(facts.activityCount),
            friendRequestBadge: badge(facts.friendRequestCount),
            account: account(facts),
            debugRows: debugRows
        )
    }

    /// The legacy pill showed the plain count, and nothing at zero.
    static func badge(_ count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }

    static func account(_ facts: CutSettingsFacts) -> CutSettingsModel.Account {
        if facts.isLocalMode { return .logIn }
        if facts.isLoggedIn { return .logOut }
        return .none
    }

    static var debugRows: [CutSettingsModel.DebugRow] {
        #if DEBUG
        CutSettingsModel.DebugRow.allCases
        #else
        []
        #endif
    }

    /// The legacy onChange rule: signing in while in local mode leaves local mode.
    static func leavesLocalMode(loggedIn: Bool, isLocalMode: Bool) -> Bool {
        loggedIn && isLocalMode
    }

    /// The legacy task rule: badges refresh only outside local mode.
    static func refreshesBadges(isLocalMode: Bool) -> Bool {
        !isLocalMode
    }
}
