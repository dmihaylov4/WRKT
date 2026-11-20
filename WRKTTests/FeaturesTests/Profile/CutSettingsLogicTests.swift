import Foundation
import Testing
@testable import WRKT

@Suite("Cut Settings logic")
struct CutSettingsLogicTests {
    private func model(local: Bool = false, loggedIn: Bool = true, activity: Int = 0, requests: Int = 0) -> CutSettingsModel {
        CutSettingsLogic.model(CutSettingsFacts(isLocalMode: local, isLoggedIn: loggedIn,
                                                activityCount: activity, friendRequestCount: requests))
    }

    @Test func signedInShowsSocialAndLogOut() {
        let model = model()
        #expect(model.showsSocial)
        #expect(model.account == .logOut)
        #expect(model.title == "Settings")
    }

    @Test func localModeHidesSocialAndOffersLogIn() {
        let model = model(local: true, loggedIn: false)
        #expect(!model.showsSocial)
        #expect(model.account == .logIn)
    }

    @Test func localModeWinsEvenWhenAUserIsPresent() {
        // The legacy order: local mode is checked before the signed-in state.
        let model = model(local: true, loggedIn: true)
        #expect(!model.showsSocial)
        #expect(model.account == .logIn)
    }

    @Test func signedOutOutsideLocalModeHasNoAccountRow() {
        let model = model(local: false, loggedIn: false)
        #expect(!model.showsSocial)
        #expect(model.account == .none)
    }

    @Test func badgesShowOnlyAboveZero() {
        #expect(model().activityBadge == nil)
        #expect(model().friendRequestBadge == nil)
        let busy = model(activity: 3, requests: 12)
        #expect(busy.activityBadge == "3")
        #expect(busy.friendRequestBadge == "12")
        #expect(CutSettingsLogic.badge(-1) == nil)
    }

    @Test func localModeHandOffAndBadgeRefreshRules() {
        #expect(CutSettingsLogic.leavesLocalMode(loggedIn: true, isLocalMode: true))
        #expect(!CutSettingsLogic.leavesLocalMode(loggedIn: true, isLocalMode: false))
        #expect(!CutSettingsLogic.leavesLocalMode(loggedIn: false, isLocalMode: true))
        #expect(CutSettingsLogic.refreshesBadges(isLocalMode: false))
        #expect(!CutSettingsLogic.refreshesBadges(isLocalMode: true))
    }

    @Test func debugRowsArePresentOnlyInDebugBuilds() {
        #if DEBUG
        #expect(model().debugRows == CutSettingsModel.DebugRow.allCases)
        #expect(model(local: true, loggedIn: false).debugRows.count == 10)
        #else
        #expect(model().debugRows.isEmpty)
        #endif
    }

    @Test func debugRowsKeepTheLegacyOrderAndKinds() {
        let rows = CutSettingsModel.DebugRow.allCases
        #expect(rows.map(\.title) == [
            "Rounded shapes", "Cut design", "Replay launch animation", "Barbell playground",
            "Year in review: my data", "Year in review: sample data",
            "Year in review: pop up on next launch", "Year in review: 3D award", "Cut gallery",
            "Per-workout history migration"
        ])
        #expect(rows.filter(\.isToggle) == [.roundedShapes, .cutDesign, .yearAward3D, .runHistoryMigration])
        #expect(rows.filter(\.pushes) == [.barbellPlayground, .cutGallery])
        #expect(CutSettingsModel.DebugRow.cutDesign.subtitle == "Applies after restarting the app")
        #expect(CutSettingsModel.DebugRow.roundedShapes.subtitle == "Applies after restarting the app")
        #expect(CutSettingsModel.DebugRow.yearReviewNextLaunch.subtitle == "Needs the Cut design and five workouts this year")
        #expect(CutSettingsModel.DebugRow.yearAward3D.subtitle == "Off shows the SwiftUI plaque")
        #expect(CutSettingsModel.DebugRow.cutGallery.subtitle == nil)
        #expect(CutSettingsModel.DebugRow.runHistoryMigration.subtitle?.contains("The merge with an older build's writes is in place") == true)
    }

    @Test func hairlinesRunBetweenRowsButNotUnderASectionsLastRow() {
        let roles: [CutSettingsItemRole] = [.header, .row, .row, .row, .header, .row, .row, .footer, .header, .row]
        let shown = roles.indices.map { CutSettingsLayout.showsHairline(at: $0, roles: roles) }
        #expect(shown == [false, true, true, false, false, true, false, false, false, false])
        #expect(!CutSettingsLayout.showsHairline(at: 5, roles: []))
    }
}
