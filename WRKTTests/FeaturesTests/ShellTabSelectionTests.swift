import Foundation
import Testing
@testable import WRKT

@MainActor
struct ShellTabSelectionTests {
    private let all: [AppTab] = [.train, .plan, .social, .cardio, .profile]

    @Test func tappingAnotherTabSelectsIt() {
        for current in all {
            for tapped in all where tapped != current {
                #expect(ShellTabSelection.resolve(current: current, tapped: tapped) == .select(tapped))
            }
        }
    }

    @Test func tappingCurrentTabPostsMatchingReselect() {
        #expect(ShellTabSelection.resolve(current: .train, tapped: .train) == .reselect(.homeTabReselected))
        #expect(ShellTabSelection.resolve(current: .plan, tapped: .plan) == .reselect(.calendarTabReselected))
        #expect(ShellTabSelection.resolve(current: .social, tapped: .social) == .reselect(.socialTabReselected))
        #expect(ShellTabSelection.resolve(current: .cardio, tapped: .cardio) == .reselect(.cardioTabReselected))
    }

    @Test func reselectingProfilePostsNothing() {
        #expect(ShellTabSelection.resolve(current: .profile, tapped: .profile) == .reselect(nil))
    }
}
