import SwiftUI

struct CutImageViewerView<Photo: View>: View {
    let model: CutImageViewerModel
    @Binding var selectedIndex: Int
    var close: () -> Void = {}
    @ViewBuilder var photo: (CutImageViewerModel.Photo) -> Photo
    var body: some View {
        ZStack(alignment: .topTrailing) {
            DS.Cut.Colors.background.ignoresSafeArea()
            TabView(selection: $selectedIndex) {
                ForEach(model.photos) { item in photo(item).tag(item.id) }
            }.tabViewStyle(.page)
            Button("Close images", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: DS.Cut.Metrics.minTouchTarget))
                .padding(.top, 24).padding(.trailing, 20)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
    }
}
