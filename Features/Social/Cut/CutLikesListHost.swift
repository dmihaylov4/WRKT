import SwiftUI

struct CutLikesListHost: View {
    let postId: UUID
    let postRepository: PostRepository
    @Environment(\.dismiss) private var dismiss
    @State private var state = CutLikesListState()

    var body: some View {
        CutLikesListView(model: CutLikesListLogic.model(people: state.people, error: state.error),
                         retry: { Task { await load() } }, done: { dismiss() })
            .task { let task = Task { await load() }; await task.value }
    }
    private func load() async {
        await state.load {
            try await postRepository.fetchPostLikes(postId: postId).map {
                .init(id: $0.id, username: $0.username, displayName: $0.displayName, avatarURL: $0.avatarUrl)
            }
        }
    }
}

/// Request state belongs to the host; the display logic remains pure.
@MainActor @Observable
final class CutLikesListState {
    private(set) var people: [CutSocialPersonFacts]?
    private(set) var error: String?
    private var isLoading = false

    func load(fetch: () async throws -> [CutSocialPersonFacts]) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            people = result
        } catch is CancellationError {
            return
        } catch let cancellation as URLError where cancellation.code == .cancelled {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
