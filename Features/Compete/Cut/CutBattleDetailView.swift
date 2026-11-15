import SwiftUI

struct CutBattleDetailActions {
    var accept: () -> Void = {}
    var exit: () -> Void = {}
    var close: () -> Void = {}
}

/// Battle detail: a sheet sized to its content with the two scores, one result line, an inner
/// panel of dates and rewards, and the quiet exit action at the bottom.
struct CutBattleDetailView: View {
    let model: CutBattleDetailModel
    var operation: CutBattleDetailModel.Operation?
    var actions = CutBattleDetailActions()
    /// False when pushed on a navigation stack (a feed link): no sheet surface or close button.
    var inSheet = true
    @State private var confirmingExit: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var processing: Bool { operation != nil }

    init(model: CutBattleDetailModel, operation: CutBattleDetailModel.Operation? = nil, actions: CutBattleDetailActions = .init(),
         inSheet: Bool = true, confirmingExit: Bool = false) {
        self.model = model; self.operation = operation; self.actions = actions; self.inSheet = inSheet
        _confirmingExit = State(initialValue: confirmingExit)
    }

    var body: some View {
        Group {
            if inSheet {
                CutSheet(model.title, subtitle: model.subtitle, close: actions.close) { content }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.title).font(DS.Cut.Typography.condensed(size: 32, relativeTo: .title)).textCase(.uppercase)
                                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                            Text(model.subtitle).font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                        .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12)
                        content
                    }
                }
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .background(DS.Cut.Colors.background.ignoresSafeArea())
            }
        }
        .confirmationDialog((model.exit ?? "Leave battle") + "?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button(model.exit ?? "Leave battle", role: .destructive, action: actions.exit)
            Button("Keep battle", role: .cancel) {}
        } message: { Text(model.confirmation) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showsScores {
                scores.padding(.top, 14)
                CutSplitBar(fraction: model.split).padding(.top, 14)
            }
            Text(model.headline)
                .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                .foregroundStyle(model.headlineIsLime ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, model.showsScores ? 12 : 10)
            if model.accepts {
                CutCompeteInvitationButtons(processing: processing, declineOperation: operation == .exit,
                                            accept: actions.accept, decline: { confirmingExit = true }, inset: 0)
                    .padding(.top, 18)
            }
            CutSheetInset {
                ForEach(Array(model.details.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { CutHairline() }
                    CutSheetInsetRow(row.label, value: row.value)
                }
            }
            .padding(.top, 22)
            if let exit = model.exit, !model.accepts {
                Button(role: .destructive) { confirmingExit = true } label: {
                    ZStack {
                        Text(exit).opacity(operation == .exit ? 0 : 1)
                        if operation == .exit { ProgressView().tint(DS.Cut.Colors.destructive) }
                    }
                }
                .buttonStyle(CutQuietButtonStyle())
                .disabled(processing)
                .accessibilityLabel(Text(exit))
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.bottom, model.exit != nil && !model.accepts ? 8 : 24)
    }

    @ViewBuilder
    private var scores: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                side(model.own, isViewer: true, alignment: .leading)
                side(model.other, isViewer: false, alignment: .leading)
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                side(model.own, isViewer: true, alignment: .leading)
                Text(model.unit).font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(DS.Cut.Colors.textSecondary).padding(.bottom, 10).fixedSize()
                    .accessibilityHidden(true)
                side(model.other, isViewer: false, alignment: .trailing)
            }
        }
    }

    private func side(_ side: CutBattleDetailModel.Side, isViewer: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            CutCompeteAvatar(initials: side.initials, url: side.avatarURL, size: 44, isViewer: isViewer)
            Text(side.score)
                .font(DS.Cut.Typography.condensed(size: 64, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(isViewer ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(isViewer ? "You" : side.name): \(side.score) \(model.unit)"))
    }
}

/// A battle's two plate rewards with their thumbnails.
struct CutBattleRewardRows: View {
    let rewards: [CutBattleDetailModel.Reward]
    var body: some View {
        ForEach(Array(rewards.enumerated()), id: \.element.id) { index, reward in
            if index > 0 { CutHairline() }
            HStack(alignment: .center, spacing: 14) {
                CachedPlateThumbnail(tierID: reward.id, progressionTier: .iron, liftTypeID: reward.liftID,
                                     weightKg: reward.weight, engravingText: reward.engraving)
                    .frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text((reward.title == "Win" ? "Winner earns " : "Finishing earns ") + reward.name)
                        .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                    Text(reward.weightText + ", " + reward.xp.replacingOccurrences(of: "+", with: ""))
                        .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }
}
