import Testing
@testable import WRKT

struct ProfileCollectionDestinationTests {

    @Test func bottomDestinationsExposePRCollectionAndMilestonesInOrder() {
        #expect(ProfileCollectionDestination.allCases == [.prCollection, .milestones])
    }

    @Test func bottomDestinationsUseLocalizedLabelsAndStableIcons() {
        #expect(ProfileCollectionDestination.prCollection.titleLocalizationKey == "PR Collection")
        #expect(ProfileCollectionDestination.prCollection.subtitleLocalizationKey == "View personal records")
        #expect(ProfileCollectionDestination.prCollection.iconName == "crown.fill")

        #expect(ProfileCollectionDestination.milestones.titleLocalizationKey == "Milestones")
        #expect(ProfileCollectionDestination.milestones.subtitleLocalizationKey == "View achievements")
        #expect(ProfileCollectionDestination.milestones.iconName == "trophy.fill")
    }
}
