import Foundation

struct CutExercisePickerModel: Equatable {
    enum Region: String, CaseIterable { case all = "All", upper = "Upper Body", lower = "Lower Body" }
    let rows: [CutExerciseRowModel]
    let totalCount: Int
    let hasMore: Bool
    let query: String
    let region: Region
    let isLibraryEmpty: Bool
}

enum CutExercisePickerLogic {
    static let pageSize = 50

    static func filtered(_ exercises: [Exercise], region: CutExercisePickerModel.Region,
                         query: String, favorites: Set<String>) -> [Exercise] {
        let keywords: Set<String>
        switch region {
        case .upper: keywords = ["chest", "back", "shoulder", "bicep", "tricep", "forearm", "trap", "lat", "pec", "delt"]
        case .lower: keywords = ["quad", "hamstring", "glute", "calf", "adductor", "abductor", "hip", "leg"]
        case .all: keywords = []
        }
        let matches = exercises.filter { exercise in
            let inRegion = region == .all || exercise.primaryMuscles.contains { muscle in
                keywords.contains { muscle.lowercased().contains($0) }
            }
            return inRegion && (query.isEmpty || exercise.name.localizedCaseInsensitiveContains(query))
        }
        // The picker differs from browsing: custom exercises have no special sort priority.
        let preferred = matches.filter { favorites.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let others = matches.filter { !favorites.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return preferred + others
    }

    static func model(exercises: [Exercise], region: CutExercisePickerModel.Region, query: String,
                      favorites: Set<String>, displayedCount: Int) -> CutExercisePickerModel {
        let result = filtered(exercises, region: region, query: query, favorites: favorites)
        let count = max(0, displayedCount)
        return .init(rows: result.prefix(count).map {
            .init(id: $0.id, name: $0.name, detail: $0.primaryMuscles.joined(separator: ", "), isFavorite: favorites.contains($0.id))
        }, totalCount: result.count, hasMore: result.count > count, query: query, region: region,
                     isLibraryEmpty: exercises.isEmpty)
    }

    static func nextPage(displayedCount: Int, totalCount: Int) -> Int {
        min(max(0, displayedCount) + pageSize, totalCount)
    }

    static func selection(_ id: String, model: CutExercisePickerModel, exercises: [Exercise]) -> Exercise? {
        guard model.rows.contains(where: { $0.id == id }) else { return nil }
        return exercises.first { $0.id == id }
    }
}
