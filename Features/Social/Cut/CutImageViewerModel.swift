import Foundation

struct CutImageViewerModel: Equatable {
    struct Photo: Equatable, Identifiable { var id: Int; var url: String }
    var photos: [Photo]
}
enum CutImageViewerLogic {
    static func model(_ urls: [String]) -> CutImageViewerModel {
        // Preserve positions, duplicates and unresolved URLs: selectedIndex belongs to the caller.
        .init(photos: urls.enumerated().map { .init(id: $0.offset, url: $0.element) })
    }
}
