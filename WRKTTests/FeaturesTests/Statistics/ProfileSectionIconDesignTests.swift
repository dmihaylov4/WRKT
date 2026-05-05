import Testing
@testable import WRKT

struct ProfileSectionIconDesignTests {
    @Test func meStatsSectionsUseCustomAccentIconKinds() {
        #expect(ProfileSectionIconKind.trainingTrends.accessibilityLabel == "Training trends")
        #expect(ProfileSectionIconKind.trainingBalance.accessibilityLabel == "Training balance")
        #expect(ProfileSectionIconKind.achievementCup.accessibilityLabel == "Achievement cup")
        #expect(ProfileSectionIconKind.allCases == [.trainingTrends, .trainingBalance, .achievementCup])
    }
}
