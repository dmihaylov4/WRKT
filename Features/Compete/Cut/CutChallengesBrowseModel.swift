import Foundation

struct CutChallengesBrowseModel: Equatable {
    enum Tab: String, CaseIterable { case active = "Active", browse = "Browse", completed = "Completed" }
    struct Preset: Equatable, Identifiable {
        var title: String
        var description: String
        var duration: String
        var difficulty: String
        var id: String { title }
    }
    var tab: Tab
    var rows: [CutCompeteItem]
    var presets: [Preset]
    var loading: Bool
    var error: String?
    var empty: String?
    var showsAll: Bool
}
enum CutChallengesBrowseLogic {
    static func model(tab: CutChallengesBrowseModel.Tab, active: [CutCompeteItem], available: [CutCompeteItem], completed: [CutCompeteItem],
                      presets: [CutChallengesBrowseModel.Preset], loading: Bool, error: String?) -> CutChallengesBrowseModel {
        let rows: [CutCompeteItem]
        switch tab { case .active: rows = active; case .browse: rows = available; case .completed: rows = completed }
        let recommended = tab == .browse || rows.isEmpty ? (tab == .browse ? presets : Array(presets.prefix(3))) : []
        let empty = !loading && error == nil && rows.isEmpty && (tab != .browse || presets.isEmpty)
            ? (tab == .browse ? "No challenges available" : "No \(tab.rawValue.lowercased()) challenges") : nil
        return .init(tab: tab, rows: rows, presets: recommended, loading: loading, error: error, empty: empty,
                     showsAll: tab != .browse && rows.isEmpty && !presets.isEmpty)
    }
}
