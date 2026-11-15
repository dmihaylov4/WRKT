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

/// One pill in the filter row. The pill reads the group name until a choice is made,
/// then reads the choice and fills lime. Its menu lists "Any ..." first, then `options`.
struct CutExerciseFilterMenu: Equatable, Identifiable {
    enum Kind: CaseIterable { case muscle, equipment, movement }
    let kind: Kind
    let groupName: String
    let anyTitle: String
    let options: [String]
    let selection: String?
    var id: Kind { kind }
    var label: String { selection ?? groupName }
    var isActive: Bool { selection != nil }
}

struct CutExerciseBrowserModel: Equatable {
    enum EmptyState: Equatable { case library, filtered, search }
    let title: String
    let menus: [CutExerciseFilterMenu]
    let filters: CutExerciseBrowserFilters
    let rows: [CutExerciseRowModel]
    let suggestions: [CutExerciseSuggestionModel]
    let emptyState: EmptyState?
    let emptyMessage: String
    var countText: String { rows.count == 1 ? "1 exercise" : "\(rows.count) exercises" }
    var showsClearFilters: Bool { menus.contains(where: \.isActive) }
    /// The pills and count line hide while searching, and while the library has not loaded.
    var showsFilters: Bool { !filters.isSearching }
    var showsCount: Bool { emptyState != .library }
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

    /// Muscle menu options: the region's muscles, or every muscle (upper body first) on All Exercises.
    static func muscles(for filter: MuscleFilter?) -> [String] {
        switch filter {
        case .upperBody: return MuscleTaxonomy.subregions(for: .upper)
        case .lowerBody: return MuscleTaxonomy.subregions(for: .lower)
        case .fullBody, .none: return MuscleTaxonomy.subregions(for: .upper) + MuscleTaxonomy.subregions(for: .lower)
        }
    }

    /// The pills in display order. A subregion list is already one muscle, so it has no muscle pill.
    static func menus(subregion: String?, muscleFilter: MuscleFilter?,
                      filters: CutExerciseBrowserFilters) -> [CutExerciseFilterMenu] {
        var menus: [CutExerciseFilterMenu] = []
        if subregion == nil {
            menus.append(.init(kind: .muscle, groupName: "Muscle", anyTitle: "Any muscle",
                               options: muscles(for: muscleFilter), selection: filters.muscle))
        }
        menus.append(.init(kind: .equipment, groupName: "Equipment", anyTitle: "Any equipment",
                           options: EquipBucket.allCases.filter { $0 != .all }.map(\.rawValue),
                           selection: filters.equipment == .all ? nil : filters.equipment.rawValue))
        menus.append(.init(kind: .movement, groupName: "Movement", anyTitle: "Any movement",
                           options: MoveBucket.allCases.filter { $0 != .all }.map(\.rawValue),
                           selection: filters.movement == .all ? nil : filters.movement.rawValue))
        return menus
    }

    /// Sets one group's choice (nil is "Any ...") and leaves the other groups as they are.
    static func selecting(_ option: String?, for kind: CutExerciseFilterMenu.Kind,
                          in filters: CutExerciseBrowserFilters) -> CutExerciseBrowserFilters {
        var next = filters
        switch kind {
        case .muscle: next.muscle = option
        case .equipment: next.equipment = option.flatMap(EquipBucket.init(rawValue:)) ?? .all
        case .movement: next.movement = option.flatMap(MoveBucket.init(rawValue:)) ?? .all
        }
        return next
    }

    /// "Clear filters": every group back to "Any ...", and the query when searching. Search mode stays.
    static func cleared(_ filters: CutExerciseBrowserFilters) -> CutExerciseBrowserFilters {
        .init(isSearching: filters.isSearching)
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
            message = "Try loosening the filters."
        }
        let suggestions = result.isEmpty && filters.isSearching && !filters.query.isEmpty
            ? Self.suggestions(exercises: exercises, query: filters.query, excluding: subregion ?? filters.muscle, favorites: favorites)
            : []
        return .init(title: title(subregion: subregion, muscleFilter: muscleFilter),
                     menus: menus(subregion: subregion, muscleFilter: muscleFilter, filters: filters), filters: filters,
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
    /// Every captured target exists in the current layout: the pill row, the list and the toolbar plus.
    enum Target: Hashable, CaseIterable { case filters, list, create }
    var filters = CGRect.zero
    var list = CGRect.zero
    var create = CGRect.zero
    var isReady: Bool { Target.allCases.allSatisfy { frame(for: $0).width > 0 && frame(for: $0).height > 0 } }

    func frame(for target: Target) -> CGRect {
        switch target {
        case .filters: filters
        case .list: list
        case .create: create
        }
    }

    mutating func set(_ frame: CGRect, for target: Target) {
        switch target {
        case .filters: filters = frame
        case .list: list = frame
        case .create: create = frame
        }
    }
}

struct CutExerciseTutorialModel: Equatable {
    let index: Int
    let count: Int
    let title: String
    let message: String
    /// The spotlit target. The toolbar step has none: toolbar frames are only used for readiness.
    let target: CutExerciseTutorialFrames.Target?
    let frame: CGRect?
    var isLast: Bool { index == count - 1 }
}

enum CutExerciseTutorialLogic {
    static let stepCount = 3

    static func step(_ index: Int, frames: CutExerciseTutorialFrames) -> CutExerciseTutorialModel {
        func make(_ index: Int, _ title: String, _ message: String, _ target: CutExerciseTutorialFrames.Target?) -> CutExerciseTutorialModel {
            .init(index: index, count: stepCount, title: title, message: message, target: target,
                  frame: target.map(frames.frame(for:)))
        }
        switch index {
        case 0: return make(0, "Filters", "Tap Muscle, Equipment or Movement and pick one. A lime pill is a filter in use. Clear filters shows everything again.", .filters)
        case 1: return make(1, "Exercise list", "The type appears below each name. Tap a heart to favorite an exercise and move it to the top.", .list)
        default: return make(2, "Search and create", "Tap the magnifying glass to search by name. Tap the lime plus to create a custom exercise: custom exercises appear before the catalog.", nil)
        }
    }
}
