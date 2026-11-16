import SwiftUI

struct CutLikesListView: View {
    let model: CutLikesListModel
    var retry: () -> Void = {}
    var done: () -> Void = {}

    var body: some View {
        CutSheet("Liked by", fitsContent: true, kind: .browser, close: done) {
            LazyVStack(alignment: .leading, spacing: 0) {
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
        }

    }

    private func message(_ value: String) -> some View {
        Text(value).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 24)
    }
    private var retryButton: some View {
        Button("Try again", action: retry).buttonStyle(CutPrimaryButtonStyle(size: .compact, fillsWidth: false))
    }
}
