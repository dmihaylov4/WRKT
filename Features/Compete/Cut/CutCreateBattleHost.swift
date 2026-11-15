import SwiftUI

struct CutCreateBattleHost: View {
    let viewModel: BattleViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CutCreateBattleDraft()
    @State private var selectedFriend: UserProfile?
    @State private var picking = false
    @State private var creating = false
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    var body: some View {
        NavigationStack {
            CutCreateBattleView(model: CutCreateBattleLogic.model(draft, opponent: selectedFriend.map(CutBattleOpponent.init), creating: creating,
                unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg), draft: $draft, chooseOpponent: { picking = true }, send: { Task { await create() } })
            .navigationTitle("Create Battle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(DS.Cut.Colors.textPrimary) } }
            .sheet(isPresented: $picking) { CutCreateBattleOpponentHost(selectedFriend: $selectedFriend) }
            .onChange(of: selectedFriend?.id) { _, id in draft.opponentID = id }
        }
        .alert(item: Binding(get: { viewModel.error }, set: { _ in viewModel.error = nil })) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
    private func create() async {
        guard let selectedFriend, !creating else { return }
        creating = true
        await viewModel.createBattle(opponentId: selectedFriend.id.uuidString, battleType: draft.type, durationDays: draft.duration)
        creating = false
    }
}
struct CutCreateBattleOpponentHost: View {
    @Binding var selectedFriend: UserProfile?
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var searching = false
    var body: some View {
        NavigationStack {
            CutBattleOpponentView(model: CutCreateBattleLogic.opponents(friends.map { .init($0.profile) }, query: query,
                selected: selectedFriend?.id, loading: loading, error: error), query: $query, select: { id in
                    guard let friend = friends.first(where: { $0.profile.id == id }) else { return }
                    Haptics.light(); selectedFriend = friend.profile; dismiss()
                }, retry: { Task { await load() } }, findFriends: { searching = true })
            .navigationTitle("Choose Opponent").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(isPresented: $searching) { UserSearchView() }
            .task { await load() }
        }
    }
    private func load() async {
        guard let userID = deps.authService.currentUser?.id else { error = "Not authenticated"; loading = false; return }
        loading = true; error = nil
        do { friends = try await deps.friendshipRepository.fetchFriends(userId: userID) }
        catch { self.error = "Failed to load friends: \(error.localizedDescription)" }
        loading = false
    }
}
extension CutBattleOpponent {
    init(_ profile: UserProfile) {
        self.init(id: profile.id, name: profile.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? profile.username,
                  username: profile.username, avatarURL: profile.avatarUrl)
    }
}
