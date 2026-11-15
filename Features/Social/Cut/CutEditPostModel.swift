import Foundation

struct CutEditPostDraft: Equatable {
    var caption: String
    var visibility: PostVisibility
}
struct CutEditPostModel: Equatable {
    enum RouteStatus: Equatable { case unknown, hasMap, noMap, building, success, failed }
    var canSave: Bool
    var isSaving: Bool
    var showsRoute: Bool
    var routeLine: String
    var isBackfilling: Bool
    var showsRebuild: Bool
    var error: String?
    static let footer = "You can only edit the caption and visibility. The workout details and photos cannot be changed."
    static let routeHelp = "Fetches the GPS route from HealthKit and attaches it as a map image."
}
enum CutEditPostLogic {
    static func model(draft: CutEditPostDraft, originalCaption: String?, originalVisibility: PostVisibility,
                      isOwn: Bool, isCardio: Bool, healthKitLinked: Bool, hasImages: Bool,
                      route: CutEditPostModel.RouteStatus = .unknown, saving: Bool = false, backfilling: Bool = false,
                      error: String? = nil) -> CutEditPostModel {
        let changed = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines) != (originalCaption ?? "")
            || draft.visibility != originalVisibility || route == .success
        let line: String = switch route {
        // Keep the legacy any-image check. Identifying actual map images is a separate behavior change.
        case .unknown: hasImages ? "Map attached" : "No map yet"
        case .hasMap: "Map attached"
        case .noMap: "No route data in HealthKit yet"
        case .building: "Building..."
        case .success: "Route map added"
        case .failed: "Could not build route: try again later"
        }
        return .init(canSave: changed && !saving, isSaving: saving, showsRoute: isOwn && isCardio && healthKitLinked,
                     routeLine: line, isBackfilling: backfilling, showsRebuild: route != .success, error: error)
    }
    static func savedCaption(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
