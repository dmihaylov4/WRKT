import SwiftUI

struct CutBattleDetailActions {
    var accept: () -> Void = {}
    var exit: () -> Void = {}
}

struct CutBattleDetailView: View {
    let model: CutBattleDetailModel
    var operation: CutBattleDetailModel.Operation?
    private var processing: Bool { operation != nil }
    var actions = CutBattleDetailActions()
    @State private var confirmingExit: Bool
    @State private var detailsExpanded: Bool
    @State private var rewardsExpanded: Bool
    init(model: CutBattleDetailModel, operation: CutBattleDetailModel.Operation? = nil, actions: CutBattleDetailActions = .init(), expanded: Bool = false, confirmingExit: Bool = false) {
        self.model = model; self.operation = operation; self.actions = actions
        _confirmingExit = State(initialValue: confirmingExit)
        _detailsExpanded = State(initialValue: expanded); _rewardsExpanded = State(initialValue: expanded)
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { typeText.fixedSize(); Spacer(minLength: 12); statusText.fixedSize() }
                    VStack(alignment: .leading, spacing: 8) { typeText; statusText }
                }
                scores
                if model.state == .active || model.state == .expired {
                    Text(model.lead).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(model.isLeading ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                    CutSplitBar(fraction: model.split).accessibilityLabel(model.lead)
                }
                if model.accepts {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { accept; exit }
                        VStack(alignment: .leading, spacing: 12) { accept; exit }
                    }
                } else if model.exit != nil { exit }
                VStack(alignment: .leading, spacing: 0) {
                    CutCompeteSectionTitle("Details")
                    DisclosureGroup(isExpanded: $detailsExpanded) {
                        ForEach(model.details) { row in CutCompeteValueRow(label: row.label, value: row.value) }
                    } label: { CutCompeteDisclosureLabel("Dates") }
                    CutHairline()
                    DisclosureGroup(isExpanded: $rewardsExpanded) {
                        CutBattleRewardRows(rewards: model.rewards)
                    } label: { CutCompeteDisclosureLabel("Rewards") }
                    CutHairline()
                }.tint(DS.Cut.Colors.textSecondary)
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12).padding(.bottom, 40)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
    private var typeText: some View {
        Text(model.type).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary)
    }
    private var statusText: some View {
        Text(model.state == .active || model.state == .expired ? model.time : model.status)
            .font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
            .foregroundStyle(model.state == .won ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
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
            Text(name).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).fixedSize(horizontal: false, vertical: true)
            Text(value).font(DS.Cut.Typography.condensed(size: 44, relativeTo: .largeTitle)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(model.unit).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var accept: some View {
        Button(action: actions.accept) { ZStack { Text("Accept").opacity(operation == .accept ? 0 : 1); if operation == .accept { ProgressView().tint(DS.Cut.Colors.ink) } } }
            .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false)).disabled(processing).accessibilityLabel("Accept")
    }
    private var exit: some View {
        Button(role: .destructive) { confirmingExit = true } label: {
            ZStack {
                Text(model.exitLabel ?? "Leave Battle").opacity(operation == .exit ? 0 : 1)
                if operation == .exit { ProgressView().tint(DS.Status.error) }
            }
        }
            .accessibilityLabel(model.exitLabel ?? "Leave Battle")
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
                    Text(reward.title + ": " + reward.name).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                    Text(reward.weightText + " · " + reward.xp).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 10)
            CutHairline()
        }
    }
}
