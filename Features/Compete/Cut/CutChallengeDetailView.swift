import SwiftUI

struct CutChallengeDetailView: View {
    let model: CutChallengeDetailModel
    var processing = false
    var join: () -> Void = {}
    var leave: () -> Void = {}
    @State private var confirmingLeave = false
    @State private var aboutExpanded: Bool
    @State private var rewardExpanded: Bool
    init(model: CutChallengeDetailModel, processing: Bool = false, join: @escaping () -> Void = {}, leave: @escaping () -> Void = {}, expanded: Bool = false) {
        self.model = model; self.processing = processing; self.join = join; self.leave = leave
        _aboutExpanded = State(initialValue: expanded); _rewardExpanded = State(initialValue: expanded)
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.time).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary)
                if let progress = model.progress {
                    Text(progress).font(DS.Cut.Typography.condensed(size: 34, relativeTo: .title)).fixedSize(horizontal: false, vertical: true)
                    CutSplitBar(fraction: model.fraction).accessibilityLabel("Progress: " + model.percentage)
                }
                if !model.leaves { joinButton }
                if !model.leaders.isEmpty {
                    CutCompeteSectionTitle("Leaderboard")
                    ForEach(model.leaders) { leader in
                        DisclosureGroup {
                            CutCompeteValueRow(label: "Progress", value: leader.progress)
                        } label: {
                            Group {
                                if dynamicTypeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(leader.rank + ". " + leader.name)
                                        Text(leader.percentage).monospacedDigit()
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(leader.rank).monospacedDigit().frame(width: 28, alignment: .trailing)
                                        Text(leader.name).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(leader.percentage).monospacedDigit().frame(minWidth: 52, alignment: .trailing)
                                    }
                                }
                            }.font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(leader.isViewer ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                                .padding(.vertical, 12).frame(minHeight: 50)
                        }.tint(DS.Cut.Colors.textSecondary)
                        CutHairline()
                    }
                }
                DisclosureGroup(isExpanded: $aboutExpanded) {
                    if let description = model.description { Text(description).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).padding(.vertical, 12) }
                    ForEach(model.about) { CutCompeteValueRow(label: $0.label, value: $0.value) }
                } label: { CutCompeteSectionTitle("About") }.tint(DS.Cut.Colors.textSecondary)
                if let reward = model.reward {
                    DisclosureGroup(isExpanded: $rewardExpanded) { CutChallengeRewardView(reward: reward) } label: { CutCompeteSectionTitle("Reward") }.tint(DS.Cut.Colors.textSecondary)
                }
                if model.leaves { leaveButton.padding(.top, 18) }
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12).padding(.bottom, 40)
        }.foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
    private var joinButton: some View { Button(model.action, action: join).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)).disabled(processing) }
    private var leaveButton: some View {
        Button(model.action, role: .destructive) { confirmingLeave = true }.buttonStyle(CutCompeteDestructiveStyle()).disabled(processing)
            .confirmationDialog("Leave Challenge?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave Challenge", role: .destructive, action: leave)
                Button("Keep Challenge", role: .cancel) {}
            } message: { Text("Your challenge progress will stop updating.") }
    }
}
struct CutChallengeRewardView: View {
    let reward: CutChallengeDetailModel.Reward
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch reward {
            case .skin(let id, let name):
                if let skin = BarSkin.all.first(where: { $0.id == id }) { BarSkinPreviewTile(skin: skin).frame(width: 120, height: 40).accessibilityHidden(true) }
                Text(name).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                Text("Exclusive bar skin · +200 XP").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            case .plate(let id, let name):
                PlateFaceView(tierID: id, progressionTier: .iron, liftTypeID: nil, weightKg: 20).frame(width: 100, height: 100).clipped().accessibilityHidden(true)
                Text(name).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                Text("20 kg · +200 XP").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
            }
        }.padding(.vertical, 12)
    }
}
