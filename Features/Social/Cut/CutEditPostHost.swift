import SwiftUI

struct CutEditPostHost: View {
    let post: PostWithAuthor
    let currentUserId: UUID?
    let onSave: @MainActor @Sendable (String?, PostVisibility) async -> Void
    let onBackfillRoute: @MainActor @Sendable () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CutEditPostDraft
    @State private var isSaving = false
    @State private var isBackfilling = false
    @State private var routeStatus: CutEditPostModel.RouteStatus = .unknown

    init(post: PostWithAuthor, currentUserId: UUID?, onSave: @escaping @MainActor @Sendable (String?, PostVisibility) async -> Void,
         onBackfillRoute: @escaping @MainActor @Sendable () async -> Bool) {
        self.post = post
        self.currentUserId = currentUserId
        self.onSave = onSave
        self.onBackfillRoute = onBackfillRoute
        _draft = State(initialValue: .init(caption: post.post.caption ?? "", visibility: post.post.visibility))
    }
    var body: some View {
        CutEditPostView(model: CutEditPostLogic.model(draft: draft, originalCaption: post.post.caption, originalVisibility: post.post.visibility,
            isOwn: currentUserId == post.post.userId, isCardio: post.post.workoutData.isCardioWorkout,
            healthKitLinked: post.post.workoutData.matchedHealthKitUUID != nil, hasImages: post.post.images?.isEmpty == false,
            route: routeStatus, saving: isSaving, backfilling: isBackfilling), draft: $draft,
            save: { Task { await saveChanges() } }, cancel: { dismiss() }, rebuild: { Task { await backfillRoute() } })
    }
    private func backfillRoute() async {
        guard !isBackfilling, currentUserId != nil, post.post.workoutData.matchedHealthKitUUID != nil else { return }
        isBackfilling = true
        routeStatus = .building
        routeStatus = await onBackfillRoute() ? .success : .failed
        isBackfilling = false
    }
    private func saveChanges() async {
        isSaving = true
        let caption = CutEditPostLogic.savedCaption(draft.caption)
        let visibility = draft.visibility
        await onSave(caption, visibility)
        Haptics.success()
        dismiss()
    }
}
