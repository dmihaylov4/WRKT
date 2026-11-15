import SwiftUI

struct CutBattleDetailActions {
    var accept: () -> Void = {}
    var exit: () -> Void = {}
}

struct CutBattleDetailView: View {
    let model: CutBattleDetailModel
    var processing = false
    var actions = CutBattleDetailActions()
    @State private var confirmingExit = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.type).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                Text(model.state == .active || model.state == .expired ? model.time : model.status).cutFont(.body)
                scores
                if model.state == .active || model.state == .expired {
                    Text(model.lead).cutFont(.body).foregroundStyle(model.isLeading ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                    CutSplitBar(fraction: model.split).accessibilityLabel(model.lead)
                }
                if model.accepts {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { accept; exit }
                        VStack(alignment: .leading, spacing: 12) { accept; exit }
                    }
                } else if model.exit != nil { exit }
                DisclosureGroup {
                    ForEach(model.details) { row in CutCompeteValueRow(label: row.label, value: row.value) }
                } label: { CutCompeteSectionTitle("Details") }.tint(DS.Cut.Colors.textSecondary).padding(.top, 14)
                DisclosureGroup {
                    CutBattleRewardRows(rewards: model.rewards)
                } label: { CutCompeteSectionTitle("Rewards") }.tint(DS.Cut.Colors.textSecondary).padding(.top, 14)
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12).padding(.bottom, 40)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
    private var scores: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) { score("You", value: model.ownScore); score(model.opponent, value: model.otherScore) }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    score("You", value: model.ownScore)
                    Rectangle().fill(DS.Cut.Colors.hairline).frame(width: 1)
                    score(model.opponent, value: model.otherScore)
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 8)
    }
    private func score(_ name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).cutFont(.body).fixedSize(horizontal: false, vertical: true)
            Text(value).font(DS.Cut.Typography.condensed(size: 44, relativeTo: .largeTitle)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(model.unit).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var accept: some View {
        Button("Accept", action: actions.accept).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)).disabled(processing)
    }
    private var exit: some View {
        Button(model.exit ?? "Leave Battle", role: .destructive) { confirmingExit = true }
            .buttonStyle(CutCompeteDestructiveStyle()).disabled(processing)
            .confirmationDialog((model.exit ?? "Leave Battle") + "?", isPresented: $confirmingExit, titleVisibility: .visible) {
                Button(model.exit ?? "Leave Battle", role: .destructive, action: actions.exit)
                Button("Keep Battle", role: .cancel) {}
            } message: { Text(model.confirmation) }
    }
}

struct CutBattleRewardRows: View {
    let rewards: [CutBattleDetailModel.Reward]
    var body: some View {
        ForEach(rewards) { reward in
            HStack(alignment: .top, spacing: 16) {
                CachedPlateThumbnail(tierID: reward.id, progressionTier: .iron, liftTypeID: reward.liftID,
                                     weightKg: reward.weight, engravingText: reward.engraving)
                    .frame(width: 64, height: 64).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.title + ": " + reward.name).cutFont(.body)
                    Text(reward.weightText + " · " + reward.xp).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 10)
            CutHairline()
        }
    }
}
