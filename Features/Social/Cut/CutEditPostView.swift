import SwiftUI

struct CutEditPostView: View {
    let model: CutEditPostModel
    @Binding var draft: CutEditPostDraft
    var save: () -> Void = {}
    var cancel: () -> Void = {}
    var rebuild: () -> Void = {}
    @State private var contentHeight: CGFloat = 600
    @State private var headerHeight: CGFloat = 68
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("EDIT POST").font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                    section("Caption") {
                        TextField("Caption (optional)", text: $draft.caption,
                                  prompt: Text("Caption (optional)").foregroundStyle(DS.Cut.Colors.textSecondary), axis: .vertical)
                            .lineLimit(5...10).cutFont(.body).tint(DS.Cut.Colors.lime).disabled(model.isSaving)
                        CutHairline()
                        Text(CutEditPostModel.footer).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    section("Visibility") {
                        ForEach([PostVisibility.publicPost, .friends, .privatePost], id: \.self) { value in
                            Button { draft.visibility = value } label: {
                                HStack(spacing: 12) {
                                    Label(value.displayName, systemImage: value.icon).cutFont(.body)
                                    Spacer(minLength: 8)
                                    if draft.visibility == value { Image(systemName: "checkmark").foregroundStyle(DS.Cut.Colors.lime) }
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.isSaving).accessibilityAddTraits(draft.visibility == value ? .isSelected : [])
                            CutHairline()
                        }
                    }
                    if model.showsRoute {
                        section("Route Map") {
                            Text(model.routeLine).cutFont(.body)
                            if model.isBackfilling { ProgressView().accessibilityLabel("Building route map") }
                            else if model.showsRebuild {
                                Button("Rebuild", action: rebuild).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false)).disabled(model.isSaving)
                            }
                            Text(CutEditPostModel.routeHelp).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                    }
                    if let error = model.error { Text(error).cutFont(.body).accessibilityLabel("Error: \(error)") }
                }.padding(DS.Cut.Metrics.gutter)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(DS.Cut.Colors.textPrimary).background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(min(720, max(320, contentHeight + headerHeight + 24))), .large])
        .presentationDragIndicator(.visible).shellPresentationBackground(DS.Cut.Colors.background)
    }
    private var header: some View {
        HStack {
            Button("Cancel", action: cancel).buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false)).disabled(model.isSaving)
            Spacer(minLength: 12)
            Button(action: save) { ZStack { Text("Save").opacity(model.isSaving ? 0 : 1); if model.isSaving { ProgressView().tint(DS.Cut.Colors.ink) } } }
                .buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false)).disabled(!model.canSave).accessibilityLabel("Save post")
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.vertical, 12)
        .background(DS.Cut.Colors.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { CutSectionTitle(title); content() }
    }
}
