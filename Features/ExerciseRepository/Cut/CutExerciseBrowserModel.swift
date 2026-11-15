import Foundation
import CoreGraphics

struct CutExerciseRowModel: Equatable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let isFavorite: Bool
}

struct CutExerciseBrowserFilters: Equatable {
    var muscle: String?
    var equipment: EquipBucket = .all
    var movement: MoveBucket = .all
    var isSearching = false
    var query = ""
}

struct CutExerciseSuggestionModel: Equatable, Identifiable {
    let muscle: String
    let region: String
    let rows: [CutExerciseRowModel]
    let totalCount: Int
    var id: String { muscle }
}

struct CutExerciseBrowserModel: Equatable {
    enum EmptyState: Equatable { case library, filtered, search }
    let title: String
    let muscles: [String]
    let filters: CutExerciseBrowserFilters
    let rows: [CutExerciseRowModel]
    let suggestions: [CutExerciseSuggestionModel]
    let emptyState: EmptyState?
    let emptyMessage: String
    var activeFilterCount: Int { (filters.equipment == .all ? 0 : 1) + (filters.movement == .all ? 0 : 1) }
}

enum CutExerciseBrowserLogic {
    /// Membership comes from the repository's existing index/deep-muscle rules. Everything
    /// after membership resolution is pure, including region, search, buckets and ordering.
    static func filtered(_ exercises: [Exercise], filters: CutExerciseBrowserFilters,
                         muscleFilter: MuscleFilter?, scopedIDs: Set<String>? = nil,
                         selectedMuscleIDs: Set<String>? = nil, favorites: Set<String>) -> [Exercise] {
        let matches = exercises.filter { exercise in
            if let scopedIDs, !scopedIDs.contains(exercise.id) { return false }
            if let muscleFilter, !muscleFilter.matches(exercise) { return false }
            if let selectedMuscleIDs, !selectedMuscleIDs.contains(exercise.id) { return false }
            if filters.isSearching {
                return filters.query.isEmpty || SmartSearch.matches(query: filters.query, in: exercise.name)
            }
            return (filters.equipment == .all || exercise.equipBucket == filters.equipment)
                && (filters.movement == .all || exercise.moveBucket == filters.movement)
        }
        // Legacy search ultimately applies this ordering too: favorites, custom, name.
        return favoritesFirst(matches, favIDs: favorites)
    }

    static func row(_ exercise: Exercise, favorites: Set<String>) -> CutExerciseRowModel {
        let detail = [exercise.mechanic?.capitalized, exercise.isCustom ? "Custom" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return .init(id: exercise.id, name: exercise.name, detail: detail, isFavorite: favorites.contains(exercise.id))
    }

    static func title(subregion: String?, muscleFilter: MuscleFilter?) -> String {
        if let subregion { return subregion }
        switch muscleFilter {
        case .upperBody: return "Upper Body Exercises"
        case .lowerBody: return "Lower Body Exercises"
        case .fullBody, .none: return "All Exercises"
        }
    }

    static func muscles(for filter: MuscleFilter?) -> [String] {
        switch filter {
        case .upperBody: return MuscleTaxonomy.subregions(for: .upper)
        case .lowerBody: return MuscleTaxonomy.subregions(for: .lower)
        case .fullBody, .none: return []
        }
    }

    static func model(exercises: [Exercise], subregion: String?, muscleFilter: MuscleFilter?,
                      filters: CutExerciseBrowserFilters, scopedIDs: Set<String>? = nil,
                      selectedMuscleIDs: Set<String>? = nil, favorites: Set<String>) -> CutExerciseBrowserModel {
        let result = filtered(exercises, filters: filters, muscleFilter: muscleFilter, scopedIDs: scopedIDs,
                              selectedMuscleIDs: selectedMuscleIDs, favorites: favorites)
        let empty: CutExerciseBrowserModel.EmptyState? = !result.isEmpty ? nil
            : exercises.isEmpty ? .library : filters.isSearching ? .search : .filtered
        let message: String
        if filters.isSearching {
            message = subregion.map { "No exercises match '\(filters.query)' in \($0)." }
                ?? "No exercises match '\(filters.query)'."
        } else {
            message = "Try loosening the equipment/movement filters."
        }
        let suggestions = result.isEmpty && filters.isSearching && !filters.query.isEmpty
            ? Self.suggestions(exercises: exercises, query: filters.query, excluding: subregion ?? filters.muscle, favorites: favorites)
            : []
        return .init(title: title(subregion: subregion, muscleFilter: muscleFilter),
                     muscles: subregion == nil ? muscles(for: muscleFilter) : [], filters: filters,
                     rows: result.map { row($0, favorites: favorites) }, suggestions: suggestions,
                     emptyState: empty, emptyMessage: message)
    }

    static func suggestions(exercises: [Exercise], query: String, excluding muscle: String?,
                            favorites: Set<String>) -> [CutExerciseSuggestionModel] {
        guard let muscle, !query.isEmpty else { return [] }
        let upper = MuscleTaxonomy.subregions(for: .upper)
        let lower = MuscleTaxonomy.subregions(for: .lower)
        let ordered = upper.contains(muscle) ? upper + lower : lower + upper
        let suggestions = ordered.filter { $0 != muscle }.compactMap { group -> CutExerciseSuggestionModel? in
            let keys = MuscleMapper.synonyms(for: group)
            let matches = exercises.filter { exercise in
                exercise.primaryMuscles.contains { primary in keys.contains { primary.lowercased().contains($0) } }
                    && SmartSearch.matches(query: query, in: exercise.name)
            }.sorted { SmartSearch.score(query: query, in: $0.name) > SmartSearch.score(query: query, in: $1.name) }
            guard !matches.isEmpty else { return nil }
            let rows = matches.prefix(5).map { exercise in
                CutExerciseRowModel(id: exercise.id, name: exercise.name, detail: exercise.equipment ?? "",
                                    isFavorite: favorites.contains(exercise.id))
            }
            return .init(muscle: group, region: upper.contains(group) ? "Upper Body" : "Lower Body",
                         rows: rows, totalCount: matches.count)
        }
        return Array(suggestions.enumerated().sorted {
            $0.element.totalCount == $1.element.totalCount ? $0.offset < $1.offset : $0.element.totalCount > $1.element.totalCount
        }.prefix(5).map(\.element))
    }
}

struct CutExerciseTutorialFrames: Equatable {
    enum Target: Hashable { case equipment, movement, list, create }
    var equipment = CGRect.zero
    var movement = CGRect.zero
    var list = CGRect.zero
    var create = CGRect.zero
    var isReady: Bool { [equipment, movement, list, create].allSatisfy { $0.width > 0 && $0.height > 0 } }

    mutating func set(_ frame: CGRect, for target: Target) {
        switch target {
        case .equipment: equipment = frame
        case .movement: movement = frame
        case .list: list = frame
        case .create: create = frame
        }
    }
}

struct CutExerciseTutorialModel: Equatable {
    let index: Int
    let title: String
    let message: String
    let frame: CGRect?
}

enum CutExerciseTutorialLogic {
    static func step(_ index: Int, frames: CutExerciseTutorialFrames) -> CutExerciseTutorialModel {
        switch index {
        case 0: return .init(index: 0, title: "Equipment filters", message: "Tap an equipment type to filter exercises. Double-tap a chip to reset the filter.", frame: frames.equipment)
        case 1: return .init(index: 1, title: "Movement filters", message: "Filter by movement pattern. Combine with equipment filters for precise results.", frame: frames.movement)
        case 2: return .init(index: 2, title: "Exercise list", message: "The type appears below each name. Tap a heart to favorite an exercise and move it to the top.", frame: frames.list)
        default: return .init(index: 3, title: "Create custom exercise", message: "Tap the lime plus in the top-right corner to create an exercise. Custom exercises appear before the catalog.", frame: nil)
        }
    }
}
