import SwiftUI

struct CutEditProfileHost: View {
    let profile: UserProfile
    let onProfileUpdated: (UserProfile) -> Void
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CutEditProfileDraft
    @State private var isSaving = false
    @State private var error: String?

    init(profile: UserProfile, onProfileUpdated: @escaping (UserProfile) -> Void) {
        self.profile = profile
        self.onProfileUpdated = onProfileUpdated
        _draft = State(initialValue: .init(displayName: profile.displayName ?? "", bio: profile.bio ?? "", isPrivate: profile.isPrivate))
    }
    var body: some View {
        CutEditProfileView(model: CutEditProfileLogic.model(isSaving: isSaving, error: error), draft: $draft,
                           save: { Task { await saveProfile() } }, cancel: { dismiss() })
    }
    private func saveProfile() async {
        isSaving = true
        error = nil
        let update = CutEditProfileLogic.update(draft)
        do {
            try await deps.authService.updateProfile(displayName: update.displayName, bio: update.bio, isPrivate: update.isPrivate)
            if let updatedProfile = deps.authService.currentUser?.profile { onProfileUpdated(updatedProfile) }
            Haptics.success()
            dismiss()
        } catch {
            self.error = CutEditProfileLogic.errorLine(error.localizedDescription)
            isSaving = false
            Haptics.error()
        }
    }
}
