import SwiftUI
import Kingfisher

struct CutImageViewerHost: View {
    let imageUrls: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        CutImageViewerView(model: CutImageViewerLogic.model(imageUrls), selectedIndex: $selectedIndex, close: { dismiss() }) { item in
            KFImage(URL(string: item.url))
                .placeholder { ProgressView().tint(.white) }
                .fade(duration: 0.25).resizable().scaledToFit()
        }
    }
}
