import Foundation
import Testing
@testable import WRKT

struct CutEditProfileLogicTests {
    @Test func trimsDisplayNameAndBioWithoutChangingPrivacy() {
        let update = CutEditProfileLogic.update(.init(displayName: "  Alex Sample\n", bio: "\n Training note  ", isPrivate: true))
        #expect(update.displayName == "Alex Sample")
        #expect(update.bio == "Training note")
        #expect(update.isPrivate)
    }
    @Test func clearingFieldsSendsEmptyStringsInsteadOfOmittingUpdates() {
        let update = CutEditProfileLogic.update(.init(displayName: " \n", bio: "\t", isPrivate: false))
        #expect(update.displayName == "" && update.bio == "")
        #expect(!update.isPrivate)
    }
    @Test func noNewLocalNameOrBioValidationIsIntroduced() {
        let longBio = String(repeating: "Training. ", count: 100)
        let update = CutEditProfileLogic.update(.init(displayName: "Alex / Sample", bio: longBio, isPrivate: false))
        #expect(update.displayName == "Alex / Sample")
        #expect(update.bio == longBio.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(CutEditProfileLogic.model(isSaving: false, error: nil).canSave)
    }
    @Test func savingDisablesSaveAndKeepsTheSpinnerState() {
        let model = CutEditProfileLogic.model(isSaving: true, error: nil)
        #expect(model.isSaving && !model.canSave)
    }
    @Test func serverValidationErrorUsesTheExactLegacyPrefix() {
        let error = CutEditProfileLogic.errorLine("Not authenticated")
        let model = CutEditProfileLogic.model(isSaving: false, error: error)
        #expect(model.error == "Failed to save profile: Not authenticated")
        #expect(model.canSave)
    }
    @Test func interiorWhitespaceAndMultilineBioArePreserved() {
        let update = CutEditProfileLogic.update(.init(displayName: "Alex  Sample", bio: "Strength\n\nTrail running", isPrivate: false))
        #expect(update.displayName == "Alex  Sample")
        #expect(update.bio == "Strength\n\nTrail running")
    }
}
