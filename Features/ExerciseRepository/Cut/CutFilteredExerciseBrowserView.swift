import SwiftUI

struct CutFilteredExerciseBrowserView: View {
    let model: CutFilteredExerciseBrowserModel
    let select: (String) -> Void
    let done: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CutHairline()
                ForEach(model.subregions, id: \.self) { subregion in
                    Button { select(subregion) } label: {
                        CutHairlineRow(subregion, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 12)
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.title.uppercased()).font(DS.Cut.Typography.condensed(size: 22, relativeTo: .headline))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: done).cutFont(.title).tint(DS.Cut.Colors.textPrimary)
            }
        }
        .shellNavigationBarBackground(DS.Cut.Colors.background)
    }
}
