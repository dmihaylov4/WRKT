import Foundation

struct CutBattlesListModel: Equatable {
    enum Tab: String, CaseIterable { case active = "Active", pending = "Pending", completed = "Completed" }
    var tab: Tab
    var rows: [CutCompeteItem]
    var pendingCount: Int
    var loading: Bool
    var error: String?
    var empty: String?
    var canCreate: Bool
}
enum CutBattlesListLogic {
    static func model(tab: CutBattlesListModel.Tab, active: [CutCompeteItem], pending: [CutCompeteItem], completed: [CutCompeteItem],
                      loading: Bool, error: String?) -> CutBattlesListModel {
        let rows: [CutCompeteItem]
        switch tab { case .active: rows = active; case .pending: rows = pending; case .completed: rows = completed }
        return .init(tab: tab, rows: rows, pendingCount: pending.count, loading: loading, error: error,
                     empty: !loading && error == nil && rows.isEmpty ? "No \(tab.rawValue.lowercased()) battles" : nil,
                     canCreate: !loading && error == nil && rows.isEmpty && tab == .active)
    }
}
