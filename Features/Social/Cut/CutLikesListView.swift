import SwiftUI

struct CutLikesListView: View {
    let model: CutLikesListModel
    var retry: () -> Void = {}
    var done: () -> Void = {}
    @State private var contentHeight: CGFloat = 180

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("LIKED BY").font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Button("Done", action: done).cutFont(.title).foregroundStyle(DS.Cut.Colors.textPrimary)
                        .frame(minHeight: 44)
                }
                .padding(.bottom, 12)
                CutHairline()
                switch model.content {
                case .loading:
                    HStack(spacing: 12) {
                        ProgressView().tint(DS.Cut.Colors.textSecondary)
                        Text("Loading likes").cutFont(.body)
                    }.padding(.vertical, 28)
                case .empty: message("No likes yet")
                case .failed(let error):
                    message(error)
                    retryButton
                case .people(let people):
                    if let error = model.inlineError { message(error); retryButton }
                    ForEach(people) { person in
                        HStack(spacing: 12) {
                            CutSocialAvatar(initials: person.initials, url: person.avatarURL, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name).cutFont(.title).fixedSize(horizontal: false, vertical: true)
                                if let handle = person.handle {
                                    Text(handle).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        CutHairline()
                    }
                }
            }
            .padding(DS.Cut.Metrics.gutter)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(min(460, max(180, contentHeight + 32))), .large])
        .presentationDragIndicator(.visible)
        .shellPresentationBackground(DS.Cut.Colors.background)
    }

    private func message(_ value: String) -> some View {
        Text(value).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 24)
    }
    private var retryButton: some View {
        Button("Try again", action: retry).buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
    }
}
