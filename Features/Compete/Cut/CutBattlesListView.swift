import SwiftUI

struct CutBattlesListView: View {
    let model: CutBattlesListModel
    var processing: Set<UUID> = []
    var select: (CutBattlesListModel.Tab) -> Void = { _ in }
    var actions = CutCompeteActions()
    var refresh: () async -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            CutCompeteFilterRow(options: CutBattlesListModel.Tab.allCases.map { $0 == .pending && model.pendingCount > 0 ? "Pending (\(model.pendingCount))" : $0.rawValue }, selected: CutBattlesListModel.Tab.allCases.firstIndex(of: model.tab) ?? 0) {
                select(CutBattlesListModel.Tab.allCases[$0])
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.loading { ProgressView().accessibilityLabel("Loading battles") }
                    if let error = model.error {
                        Text(error).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                        Button("Try Again", action: actions.retry).buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                    }
                    if let empty = model.empty { Text(empty).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.vertical, 20) }
                    if model.canCreate { Button("Create Battle", action: actions.startBattle).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false)) }
                    ForEach(model.rows) { item in
                        CutCompeteItemRow(item: item, processing: item.battleID.map { processing.contains($0) } ?? false,
                            open: { actions.open(item.id) }, accept: { if let id = item.battleID { actions.accept(id) } },
                            decline: { if let id = item.battleID { actions.decline(id) } })
                    }
                }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 12).padding(.bottom, 80)
            }.refreshable { let work = Task { @MainActor in await refresh() }; await work.value }
        }.foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}
struct CutCompeteFilterRow: View {
    let options: [String]
    let selected: Int
    var select: (Int) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    Button(options[index]) { select(index) }
                        .buttonStyle(CutCompeteFilterStyle(selected: index == selected))
                        .accessibilityAddTraits(index == selected ? .isSelected : [])
                }
            }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 10)
        }.scrollIndicators(.hidden)
    }
}
private struct CutCompeteFilterStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).fixedSize().padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(selected ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
            .background(selected ? DS.Cut.Colors.lime : .clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? .clear : DS.Cut.Colors.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
