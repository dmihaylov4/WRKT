import Foundation

struct CutEditProfileDraft: Equatable {
    var displayName: String
    var bio: String
    var isPrivate: Bool
}
struct CutEditProfileModel: Equatable {
    var isSaving: Bool
    var canSave: Bool
    var error: String?
    static let privacyHelp = "Hide from search. People can only find you if they already know your username."
}
enum CutEditProfileLogic {
    static func model(isSaving: Bool, error: String?) -> CutEditProfileModel {
        // The legacy editor has no local length or required-field restrictions.
        .init(isSaving: isSaving, canSave: !isSaving, error: error)
    }
    static func update(_ draft: CutEditProfileDraft) -> CutEditProfileDraft {
        .init(displayName: editProfileDisplayNameUpdateValue(draft.displayName),
              bio: editProfileBioUpdateValue(draft.bio), isPrivate: draft.isPrivate)
    }
    static func errorLine(_ description: String) -> String { "Failed to save profile: \(description)" }
}
