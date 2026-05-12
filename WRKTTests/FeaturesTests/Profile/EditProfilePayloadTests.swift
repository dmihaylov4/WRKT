import Testing
@testable import WRKT

struct EditProfilePayloadTests {

    @Test func emptyBioIsSentAsClearValueInsteadOfOmittedUpdate() {
        #expect(editProfileBioUpdateValue("") == "")
        #expect(editProfileBioUpdateValue("   \n  ") == "")
    }

    @Test func bioTextIsTrimmedBeforeSave() {
        #expect(editProfileBioUpdateValue("  Training for strength. \n") == "Training for strength.")
    }
}
