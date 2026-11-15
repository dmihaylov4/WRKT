import SwiftUI

struct CutChallengeDetailHost: View {
    let challenge: ChallengeWithProgress
    let viewModel: ChallengesViewModel
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    @State private var processing = false
    private var displayed: ChallengeWithProgress {
        guard challenge.shouldCompleteFirstRep(from: deps.workoutStore.completedWorkouts) else { return challenge }
        return challenge.completedFirstRepFromWorkoutHistory()
    }
    private var model: CutChallengeDetailModel {
        CutChallengeDetailLogic.model(.init(displayed, userID: deps.authService.currentUser?.id), unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg)
    }
    var body: some View {
        CutChallengeDetailView(model: model, processing: processing, join: { Task { await join() } }, leave: { Task { await leave() } },
                               close: { dismiss() })
        .alert(item: Binding(get: { viewModel.error }, set: { _ in viewModel.error = nil })) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
    private func join() async {
        guard !processing else { return }
        processing = true
        await viewModel.joinChallenge(challenge.challenge)
        dismiss()
    }
    private func leave() async {
        guard !processing else { return }
        processing = true
        let success = await viewModel.leaveChallenge(challenge.challenge)
        processing = false
        if success { dismiss() }
    }
}
extension CutChallengeFacts {
    init(_ value: ChallengeWithProgress, userID: UUID?) {
        let c = value.challenge
        let reward: CutChallengeDetailModel.Reward?
        switch ChallengeRewardPreviewKind(challenge: c) {
        case .firstRepBarSkin: reward = BarSkin.all.first { $0.id == 4 }.map { .skin(id: 4, name: $0.name) }
        case .conditioningPlate: reward = .plate(id: 24, name: PlateTier.all.first { $0.id == 24 }?.name ?? "Heat Forge")
        case .none: reward = nil
        }
        self.init(id: c.id, title: c.title, description: c.description, type: c.challengeType, metric: c.goalMetric,
            goal: NSDecimalNumber(decimal: c.goalValue).doubleValue, start: c.startDate, end: c.endDate, evergreen: c.isEvergreen,
            difficulty: c.difficulty?.displayName, participantCount: c.participantCount,
            current: value.participation.map { NSDecimalNumber(decimal: $0.currentProgress).doubleValue }, percentage: value.userProgressPercentage,
            completed: value.isCompleted, participants: value.topParticipants.map {
                .init(id: $0.id, name: $0.profile.username, progress: NSDecimalNumber(decimal: $0.participant.currentProgress).doubleValue, isViewer: $0.profile.id == userID)
            }, reward: reward)
    }
}
