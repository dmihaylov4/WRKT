import SwiftUI

struct CutChallengesBrowseView: View {
    let model: CutChallengesBrowseModel
    var select: (CutChallengesBrowseModel.Tab) -> Void = { _ in }
    var open: (UUID) -> Void = { _ in }
    var openPreset: (String) -> Void = { _ in }
    var retry: () -> Void = {}
    var refresh: () async -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            CutCompeteFilterRow(options: CutChallengesBrowseModel.Tab.allCases.map(\.rawValue), selected: CutChallengesBrowseModel.Tab.allCases.firstIndex(of: model.tab) ?? 0) {
                select(CutChallengesBrowseModel.Tab.allCases[$0])
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.loading { ProgressView().accessibilityLabel("Loading challenges").padding(.vertical, 20) }
                    if let error = model.error {
                        Text(error).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).padding(.vertical, 12)
                        Button("Try Again", action: retry).buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
                    }
                    if let empty = model.empty { Text(empty).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.vertical, 20) }
                    if !model.presets.isEmpty {
                        CutCompeteSectionTitle(model.tab == .browse ? "Featured" : "Recommended")
                        ForEach(model.presets) { preset in
                            VStack(alignment: .leading, spacing: 0) {
                                Button { openPreset(preset.title) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(preset.title).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body))
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right").font(.system(size: 15)).accessibilityHidden(true)
                                        }
                                        Text(preset.duration + " · " + preset.difficulty).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                    }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                DisclosureGroup { Text(preset.description).font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).padding(.vertical, 12) } label: {
                                    Text("Details").cutFont(.secondary)
                                }.tint(DS.Cut.Colors.textSecondary).padding(.bottom, 12)
                                CutHairline()
                            }
                        }
                        if model.showsAll {
                            Button("All challenges") { select(.browse) }.font(DS.Typography.custom(size: 18, weight: .regular, relativeTo: .body)).frame(minHeight: 50).buttonStyle(.plain)
                        }
                    }
                    if !model.rows.isEmpty {
                        if model.tab == .browse { CutCompeteSectionTitle("Community") }
                        ForEach(model.rows) { item in
                            CutCompeteItemRow(item: item, open: { if case .challenge(let id) = item.id { open(id) } })
                        }
                    }
                }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.bottom, 96)
            }.refreshable { let work = Task { @MainActor in await refresh() }; await work.value }
        }.foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}
