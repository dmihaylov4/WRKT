import SwiftUI

/// Challenge detail: the same sheet as battle detail, with progress, one bold line, the
/// leaderboard and the about panel visible, and the quiet leave action at the bottom.
struct CutChallengeDetailView: View {
    let model: CutChallengeDetailModel
    var processing = false
    var join: () -> Void = {}
    var leave: () -> Void = {}
    var close: () -> Void = {}
    @State private var confirmingLeave: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    init(model: CutChallengeDetailModel, processing: Bool = false, join: @escaping () -> Void = {}, leave: @escaping () -> Void = {},
         close: @escaping () -> Void = {}, confirmingLeave: Bool = false) {
        self.model = model; self.processing = processing; self.join = join; self.leave = leave; self.close = close
        _confirmingLeave = State(initialValue: confirmingLeave)
    }
    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, close: close) {
            VStack(alignment: .leading, spacing: 0) {
                if let amount = model.amount {
                    let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    layout {
                        CutCompeteScoreText(score: amount, rest: model.amountRest, size: 34)
                        Text(model.unit).font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    .padding(.top, 14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(model.progress ?? ""))
                    CutSplitBar(fraction: model.fraction).padding(.top, 12)
                }
                Text(model.headline)
                    .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                    .foregroundStyle(model.headlineIsLime ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, model.amount == nil ? 10 : 12)
                if !model.leaves {
                    Button(action: join) {
                        ZStack {
                            Text(model.action).opacity(processing ? 0 : 1)
                            if processing { ProgressView().tint(DS.Cut.Colors.lime) }
                        }
                    }
                    .buttonStyle(CutPillButtonStyle(.outlineLime, size: .regular, fillsWidth: true))
                    .allowsHitTesting(!processing)
                    .accessibilityLabel(Text(model.action))
                    .padding(.top, 18)
                }
                if !model.leaders.isEmpty {
                    Text("Leaderboard").font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .headline))
                        .accessibilityAddTraits(.isHeader).padding(.top, 24)
                    CutSheetInset {
                        ForEach(Array(model.leaders.enumerated()), id: \.element.id) { index, leader in
                            if index > 0 { CutHairline() }
                            leaderRow(leader)
                        }
                    }
                    .padding(.top, 10)
                }
                CutSheetInset {
                    if let description = model.description, !description.isEmpty {
                        Text(description).font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 14)
                        CutHairline()
                    }
                    ForEach(Array(model.about.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CutHairline() }
                        CutSheetInsetRow(row.label, value: row.value)
                    }
                }
                .padding(.top, 22)
                if model.leaves {
                    Button(role: .destructive) { confirmingLeave = true } label: {
                        ZStack {
                            Text(model.action).opacity(processing ? 0 : 1)
                            if processing { ProgressView().tint(DS.Cut.Colors.destructive) }
                        }
                    }
                    .buttonStyle(CutQuietButtonStyle())
                    .disabled(processing)
                    .accessibilityLabel(Text(model.action))
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.bottom, model.leaves ? 8 : 24)
        }
        .confirmationDialog("Leave challenge?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave challenge", role: .destructive, action: leave)
            Button("Keep challenge", role: .cancel) {}
        } message: { Text("Your challenge progress will stop updating.") }
    }
    private func leaderRow(_ leader: CutChallengeDetailModel.Leader) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(leader.rank + ". " + leader.name)
                    Text(leader.progress).foregroundStyle(leader.isViewer ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(leader.rank).monospacedDigit().foregroundStyle(DS.Cut.Colors.textSecondary).frame(minWidth: 20, alignment: .leading)
                    Text(leader.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(leader.progress).monospacedDigit().foregroundStyle(leader.isViewer ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                }
                .padding(.vertical, 14)
                .frame(minHeight: 50)
            }
        }
        .font(DS.Typography.custom(size: 17, weight: leader.isViewer ? .bold : .medium, relativeTo: .body))
        .foregroundStyle(leader.isViewer ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(leader.rank). \(leader.name)\(leader.isViewer ? ", you" : ""), \(leader.progress), \(leader.percentage)"))
    }
}
