import SwiftUI

struct CutChallengesBrowseView: View {
    let model: CutChallengesBrowseModel
    var processing: Set<UUID> = []
    var select: (CutChallengesBrowseModel.Tab) -> Void = { _ in }
    var open: (UUID) -> Void = { _ in }
    var join: (UUID) -> Void = { _ in }
    var openPreset: (String) -> Void = { _ in }
    var retry: () -> Void = {}
    var refresh: () async -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            CutCompeteFilterRow(options: CutChallengesBrowseModel.Tab.allCases.map(\.rawValue), selected: CutChallengesBrowseModel.Tab.allCases.firstIndex(of: model.tab) ?? 0) {
                select(CutChallengesBrowseModel.Tab.allCases[$0])
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = model.error {
                        CutCompeteErrorPanel(message: error, retry: retry).padding(.bottom, 16)
                    } else if model.loading && model.rows.isEmpty {
                        CutPanel { CutCompeteLoadingRow(label: "Loading challenges") }.padding(.bottom, 16)
                    }
                    if let empty = model.empty {
                        CutPanel { CutCompeteMessageRow(title: empty, line: model.tab == .browse ? "New challenges show here." : "Join one from Browse.") }
                            .padding(.bottom, 16)
                    }
                    if !model.presets.isEmpty {
                        CutPanelHeader(model.tab == .browse ? "Featured" : "Recommended")
                        CutPanel {
                            ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                                if index > 0 { CutHairline() }
                                Button { openPreset(preset.title) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.title).font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                                            Text(preset.duration + ", " + preset.difficulty.lowercased())
                                                .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(DS.Cut.Colors.textSecondary).accessibilityHidden(true)
                                    }
                                    .padding(.horizontal, DS.Cut.Metrics.panelRowPadding).padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text(preset.description))
                            }
                        }
                        .padding(.top, 10)
                        if model.showsAll {
                            Button("All challenges") { select(.browse) }.buttonStyle(CutPillButtonStyle(.outline))
                                .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 16)
                        }
                    }
                    if !model.rows.isEmpty {
                        if model.tab == .browse { CutPanelHeader("Community").padding(.top, 26) }
                        CutPanel {
                            CutCompetePanelRows(model.rows, processing: processing,
                                                actions: .init(open: { if case .challenge(let id) = $0 { open(id) } }, join: join))
                        }
                        .padding(.top, model.tab == .browse ? 10 : 0)
                    }
                }
                .padding(.top, 12).padding(.bottom, 96)
            }.refreshable { let work = Task { @MainActor in await refresh() }; await work.value }
        }.foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}
