import SwiftUI

struct CutCreateBattleHost: View {
    let viewModel: BattleViewModel
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CutCreateBattleDraft()
    @State private var selectedFriend: UserProfile?
    @State private var picking = false
    @State private var creating = false
    /// One friends request feeds both the row under "Against" and the all-friends sheet.
    @State private var friends = CutFriendsLoader()
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    var body: some View {
        CutCreateBattleView(model: CutCreateBattleLogic.model(draft, opponent: selectedFriend.map { CutBattleOpponent($0) },
                friends: friends.friends.map { .init($0.profile) }, friendsLoading: friends.loading, friendsError: friends.error,
                creating: creating, unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg),
            draft: $draft, choose: choose, openAll: { picking = true }, send: { Task { await create() } }, close: { dismiss() })
        .sheet(isPresented: $picking) { CutCreateBattleOpponentHost(selectedFriend: $selectedFriend, loader: friends) }
        .onChange(of: selectedFriend?.id) { _, id in draft.opponentID = id }
        .task { if !friends.started { await friends.load(deps) } }
        .alert(item: Binding(get: { viewModel.error }, set: { _ in viewModel.error = nil })) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
    private func choose(_ id: UUID) {
        guard let friend = friends.friends.first(where: { $0.profile.id == id }) else { return }
        Haptics.light()
        selectedFriend = friend.profile
    }
    private func create() async {
        guard let selectedFriend, !creating else { return }
        creating = true
        await viewModel.createBattle(opponentId: selectedFriend.id.uuidString, battleType: draft.type, durationDays: draft.duration)
        creating = false
    }
}

/// The signed-in user's friends, loaded once per new battle sheet.
@MainActor @Observable
final class CutFriendsLoader {
    var friends: [Friend] = []
    var loading = true
    var error: String?
    private(set) var started = false
    func load(_ deps: AppDependencies) async {
        started = true
        guard let userID = deps.authService.currentUser?.id else { error = "Not authenticated"; loading = false; return }
        loading = true; error = nil
        do { friends = try await deps.friendshipRepository.fetchFriends(userId: userID) }
        catch { self.error = "Failed to load friends: \(error.localizedDescription)" }
        loading = false
    }
}

/// The all-friends sheet, stacked on the new battle sheet. Uses the new battle sheet's friends when given.
struct CutCreateBattleOpponentHost: View {
    @Binding var selectedFriend: UserProfile?
    var loader: CutFriendsLoader? = nil
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var ownLoader = CutFriendsLoader()
    @State private var query = ""
    @State private var searching = false
    private var source: CutFriendsLoader { loader ?? ownLoader }
    var body: some View {
        NavigationStack {
            CutBattleOpponentView(model: CutCreateBattleLogic.opponents(source.friends.map { .init($0.profile) }, query: query,
                selected: selectedFriend?.id, loading: source.loading, error: source.error), query: $query, select: { id in
                    guard let friend = source.friends.first(where: { $0.profile.id == id }) else { return }
                    Haptics.light(); selectedFriend = friend.profile; dismiss()
                }, retry: { Task { await source.load(deps) } }, findFriends: { searching = true }, close: { dismiss() })
            .navigationDestination(isPresented: $searching) { UserSearchView() }
            .task { if !source.started { await source.load(deps) } }
        }
    }
}
extension CutBattleOpponent {
    init(_ profile: UserProfile) {
        self.init(id: profile.id, name: CutCompeteFormat.personName(displayName: profile.displayName, username: profile.username),
                  username: profile.username, avatarURL: profile.avatarUrl)
    }
}
