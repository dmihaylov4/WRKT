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
                VStack(alignment: .leading, spacing: 0) {
                    if let error = model.error {
                        CutCompeteErrorPanel(message: error, retry: actions.retry)
                    } else if model.loading && model.rows.isEmpty {
                        CutPanel { CutCompeteLoadingRow(label: "Loading battles") }
                    } else if let empty = model.empty {
                        CutPanel {
                            CutCompeteMessageRow(title: empty, line: model.canCreate ? "Challenge a friend to start one." : "Battles show here when there are some.")
                        }
                    }
                    if model.canCreate {
                        Button("New battle", action: actions.startBattle).buttonStyle(CutPillButtonStyle(.lime))
                            .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 16)
                    }
                    if !model.rows.isEmpty {
                        CutPanel { CutCompetePanelRows(model.rows, processing: processing, actions: actions) }
                            .padding(.top, model.error == nil ? 0 : 16)
                    }
                }
                .padding(.top, 12).padding(.bottom, 80)
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
