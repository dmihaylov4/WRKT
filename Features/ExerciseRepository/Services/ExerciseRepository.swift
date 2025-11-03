//
//  ExerciseRepository.swift
//  WRKT
//

import Foundation
import Combine
import OSLog



@MainActor
final class ExerciseRepository: ObservableObject {
    static let shared = ExerciseRepository()

    // MARK: Published data
    @Published private(set) var exercises: [Exercise] = []

    // MARK: Pagination state
    @Published private(set) var isLoadingPage = false
    @Published private(set) var currentPage = 0
    @Published private(set) var hasMorePages = true
    @Published private(set) var totalExerciseCount = 0

    // MARK: Cache
    private let cache = ExerciseCache()

    // MARK: Custom exercises
    private let customStore = CustomExerciseStore.shared

    // MARK: Indexes (legacy - kept for backward compatibility)
    public private(set) var byID: [String: Exercise] = [:]
    private(set) var bySlug: [String: Exercise] = [:]
    private(set) var bySubregion: [String: [Exercise]] = [:]

    // MARK: Media index
    private var mediaById:   [String: ExerciseMedia] = [:]
    private var mediaByName: [String: ExerciseMedia] = [:]

    // MARK: Load-state guards
    private var didKickoffExercises = false
    private var didLoadFull = false
    private var didLoadMedia = false

    private var isLoadingFull = false

    // MARK: Current filters (for pagination)
    private var currentFilters: ExerciseFilters = ExerciseFilters()

    // MARK: Init
    /// Auto-bootstraps using a *full* load so older code that relied on `init` keeps working.
    /// If you prefer the slim-then-full startup, call `bootstrap(useSlimPreload: true)` from your App shell.
    init() {
        //bootstrap(useSlimPreload: false) // keep old behavior intact
    }

    // MARK: Public API

    /// Call once at app launch - loads exercises into cache and first page
    func bootstrap(useSlimPreload: Bool = true) {
        if !didKickoffExercises {
            didKickoffExercises = true

            // Load exercises into cache and display first page
            Task {
                do {
                    // Load all exercises into cache (fast, not displayed yet)
                    try await cache.loadAllExercises()

                    // Merge catalog + custom exercises
                    await rebuildIndexes()

                    // Load first page for display
                    await loadFirstPage()

                    self.didLoadFull = true
                    AppLogger.success("ExerciseRepository: Bootstrap complete", category: AppLogger.app)
                } catch {
                    AppLogger.error("ExerciseRepository: Bootstrap failed: \(error)", category: AppLogger.app)
                }
            }
        }
        if !didLoadMedia {
            loadMedia()
        }
    }

    /// Rebuild indexes with custom exercises merged in
    func reloadWithCustomExercises() async {
        await rebuildIndexes()
        await loadFirstPage(with: currentFilters)
    }

    /// Build indexes from cache + custom exercises
    private func rebuildIndexes() async {
        let catalogExercises = await cache.getAllExercises()
        let customExercises = customStore.customExercises

        // Merge: custom exercises override catalog if same ID
        var merged: [String: Exercise] = Dictionary(uniqueKeysWithValues: catalogExercises.map { ($0.id, $0) })
        for custom in customExercises {
            merged[custom.id] = custom
        }

        let allExercises = Array(merged.values)

        // Build indexes
        self.byID = merged
        self.bySlug = self.byID
        self.bySubregion = allExercises.reduce(into: [String: [Exercise]]()) { dict, ex in
            for tag in ex.subregionTags { dict[tag, default: []].append(ex) }
        }

        AppLogger.debug("Rebuilt indexes: \(allExercises.count) total (\(customExercises.count) custom)", category: AppLogger.app)
    }

    /// Load the first page of exercises (resets pagination)
    func loadFirstPage(with filters: ExerciseFilters = ExerciseFilters()) async {
        currentFilters = filters
        currentPage = 0

        let page = await cache.getPage(0, matching: filters)
        let total = await cache.getTotalCount(matching: filters)

        self.exercises = page
        self.totalExerciseCount = total
        self.hasMorePages = page.count >= cache.pageSize

        AppLogger.debug("Loaded first page: \(page.count) exercises (total: \(total))", category: AppLogger.app)
    }

    /// Load the next page of exercises
    func loadNextPage() async {
        guard !isLoadingPage && hasMorePages else { return }

        isLoadingPage = true
        currentPage += 1

        let page = await cache.getPage(currentPage, matching: currentFilters)

        // Append new exercises
        self.exercises.append(contentsOf: page)
        self.hasMorePages = page.count >= cache.pageSize
        self.isLoadingPage = false

        AppLogger.debug("Loaded page \(currentPage): \(page.count) exercises (total loaded: \(exercises.count)/\(totalExerciseCount))", category: AppLogger.app)
    }

    /// Reset pagination with new filters
    func resetPagination(with filters: ExerciseFilters) async {
        AppLogger.debug("Resetting pagination with new filters", category: AppLogger.app)
        await loadFirstPage(with: filters)
    }

    func exercise(byID id: String) -> Exercise? {
        // Use legacy index (populated from cache during bootstrap)
        byID[id]
    }

    /// Get all exercises (for legacy views that need full list)
    /// Prefer using pagination or indexes for better performance
    func getAllExercises() async -> [Exercise] {
        await cache.getAllExercises()
    }

    /// Media lookup by id (slug) first, then by normalized name.
    func media(for exercise: Exercise) -> ExerciseMedia? {
        if let m = mediaById[exercise.id] { return m }
        return mediaByName[Self.norm(exercise.name)]
    }

    // MARK: Loading — Exercises

    /// Reads `exercises_clean.json` (ExcelExerciseDTO[]) from bundle, maps to [Exercise], indexes, and publishes.
    func loadFromBundle(fileName: String = "exercises_clean", fileExtension: String = "json", force: Bool = false) {
        // prevent duplicate/in-flight loads
        if (didLoadFull && !force) || isLoadingFull { return }
        isLoadingFull = true

        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            AppLogger.error("Missing \(fileName).\(fileExtension) in bundle.", category: AppLogger.app)
            isLoadingFull = false
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let data    = try Data(contentsOf: url)
                let dtoList = try JSONDecoder().decode([ExcelExerciseDTO].self, from: data)
                let mapped  = ExerciseMapping.mapDTOs(dtoList)
                let sorted  = mapped.sorted { $0.name < $1.name }

                let idIndex: [String: Exercise] = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
                let slugIndex = idIndex
                let subregionIndex = mapped.reduce(into: [String: [Exercise]]()) { dict, ex in
                    for tag in ex.subregionTags { dict[tag, default: []].append(ex) }
                }

                await MainActor.run {
                    self.exercises   = sorted
                    self.byID        = idIndex
                    self.bySlug      = slugIndex
                    self.bySubregion = subregionIndex
                    self.didLoadFull = true
                    self.isLoadingFull = false
                }
                AppLogger.success("Loaded \(sorted.count) exercises from \(fileName).\(fileExtension)", category: AppLogger.app)
            } catch {
                await MainActor.run { self.isLoadingFull = false }
                AppLogger.error("Failed to decode \(fileName).\(fileExtension): \(error)", category: AppLogger.app)
            }
        }
    }

    /// Optional slim-catalog preload for instant first paint. Then upgrades to full dataset.
    func preloadCatalogThenFull() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // 1) Try slim preload (non-fatal if missing)
            if let url = Bundle.main.url(forResource: "exercises_catalog", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let slim = try? JSONDecoder().decode([[String: String?]].self, from: data) {

                let mapped: [Exercise] = slim.compactMap { row in
                    // Decode forgivingly (String?? → trim or drop)
                    guard
                        let idWrapped   = row["id"], let id = idWrapped?.trimmed, !id.isEmpty,
                        let nameWrapped = row["exercise"], let name = nameWrapped?.trimmed, !name.isEmpty
                    else { return nil }

                    let categoryRaw: String?  = row["targetMuscleGroup"] ?? nil
                    let equipmentRaw: String? = row["primaryEquipment"] ?? nil

                    let category = (categoryRaw?.trimmedOrNil ?? "general").lowercased()
                    let equipment = equipmentRaw?.trimmedOrNil

                    return Exercise(
                        id: id,
                        name: name,
                        force: nil,
                        level: nil,
                        mechanic: nil,
                        equipment: equipment,
                        primaryMuscles: [],
                        secondaryMuscles: [],
                        tertiaryMuscles: [],
                        instructions: [],
                        images: nil,
                        category: category
                    )
                }

                // Publish the slim list quickly
                await MainActor.run {
                    self.exercises = mapped.sorted { $0.name < $1.name }
                    // clear heavy indexes; they'll be rebuilt on full load
                    self.byID.removeAll()
                    self.bySlug.removeAll()
                    self.bySubregion.removeAll()
                    AppLogger.debug("Preloaded slim catalog (\(self.exercises.count))", category: AppLogger.app)
                }

            }

            // 2) Upgrade to full dataset
            await self.loadFromBundle(fileName: "exercises_clean", fileExtension: "json")
        }
    }

    // MARK: Loading — Media

    private func loadMedia() {
        guard let url = Bundle.main.url(forResource: "exercise_media_final", withExtension: "json") else {
            AppLogger.warning("exercise_media_final.json not found in bundle", category: AppLogger.app)
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let data  = try Data(contentsOf: url)
                let items = try JSONDecoder().decode([ExerciseMedia].self, from: data)

                let byId   = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
                let byName = Dictionary(uniqueKeysWithValues: items.map { (normKey($0.exercise), $0) })
                
                await MainActor.run {
                    self.mediaById = byId
                    self.mediaByName = byName
                    self.didLoadMedia = true
                }
                AppLogger.success("Loaded \(items.count) media items", category: AppLogger.app)
            } catch {
                await MainActor.run { self.didLoadMedia = false }
                AppLogger.error("Failed to load media: \(error)", category: AppLogger.app)
            }
        }
    }

    // MARK: Query helpers

    /// Returns exercises for a deep subregion (e.g., parent=Chest, child=Upper Chest).
    /// Uses indexes for fast lookup, not affected by pagination
    func deepExercises(parent: String, child: String) -> [Exercise] {
        if let arr = bySubregion[child], !arr.isEmpty {
            return arr.sorted { $0.name < $1.name }
        }
        // Fallback: runtime heuristic using your taxonomy rules - use byID index
        let (inc, exc) = MuscleTaxonomy.deepRules(parent: parent, child: child)
        let incLC = inc.map { $0.lowercased() }
        let excLC = exc.map { $0.lowercased() }

        return byID.values.filter { ex in
            let muscPrimary   = ex.primaryMuscles.joined(separator: " ")
            let muscSecondary = ex.secondaryMuscles.joined(separator: " ")
            let hay           = (ex.name + " " + muscPrimary + " " + muscSecondary).lowercased()
            let ok  = incLC.contains { hay.contains($0) }
            let bad = excLC.contains { hay.contains($0) }
            return ok && !bad
        }
        .sorted { $0.name < $1.name }
    }

    /// Returns exercises that match a muscle group (e.g., "Chest", "Upper Chest", "Biceps"...).
    /// Uses indexes for fast lookup, not affected by pagination
    /// Includes both catalog and custom exercises
    func exercisesForMuscle(_ group: String) -> [Exercise] {
        let g = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty else { return [] }

        // If we already have an index for this subregion, use it (contains catalog + custom exercises)
        if let indexed = bySubregion[g], !indexed.isEmpty {
            return indexed.sorted { $0.name < $1.name }
        }

        // If it looks like a deep subregion, delegate to deep rules.
        if let parent = ExerciseRepository.guessParent(fromDeep: g) {
            return deepExercises(parent: parent, child: g)
        }

        // Parent-only filter with synonyms - use byID index (contains catalog + custom exercises)
        let keysLC = ExerciseRepository.synonyms(for: g).map { $0.lowercased() }
        return byID.values.filter { ex in
            let muscles = (ex.primaryMuscles + ex.secondaryMuscles).map { $0.lowercased() }
            let nameLC  = ex.name.lowercased()
            let hitMuscle = muscles.contains { m in keysLC.contains(where: { m.contains($0) }) }
            let hitName   = keysLC.contains { nameLC.contains($0) }
            return hitMuscle || hitName
        }
        .sorted { $0.name < $1.name }
    }

    struct SearchResult {
        let exercises: [Exercise]
        let muscleGroups: [String]
    }

    /// Fuzzy-ish search across exercise name, equipment, category and muscles.
    /// Also proposes muscle-group suggestions.
    /// Uses indexes for fast lookup, not affected by pagination
    func search(_ raw: String, limit: Int = 60) -> SearchResult {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .init(exercises: [], muscleGroups: []) }

        let qlc = q.lowercased()
        let tokens = qlc.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        // Build canonical muscle groups (parents + deeps)
        var groups = Set<String>()
        let parentsUpper = MuscleTaxonomy.subregions(for: .upper)
        let parentsLower = MuscleTaxonomy.subregions(for: .lower)
        let allParents = parentsUpper + parentsLower
        for p in allParents {
            groups.insert(p)
            if let deep = MuscleTaxonomy.deepSubregions(for: p) { deep.forEach { groups.insert($0) } }
        }

        // Suggest groups by name or synonyms overlap
        let suggestedGroups = groups
            .filter { g in
                let glc = g.lowercased()
                if glc.contains(qlc) { return true }
                let syns = ExerciseRepository.synonyms(for: g).map { $0.lowercased() }
                return syns.contains(where: { $0.contains(qlc) || qlc.contains($0) })
            }
            .sorted()

        // Exercise search: smart fuzzy search with typo tolerance
        // Use byID index (contains all exercises) instead of paginated exercises array
        let matches: [Exercise] = byID.values.filter { ex in
            let muscP = ex.primaryMuscles.joined(separator: " ")
            let muscS = ex.secondaryMuscles.joined(separator: " ")
            let searchableText = (ex.name + " " + (ex.equipment ?? "") + " " + ex.category + " " + muscP + " " + muscS)

            // Use smart search for typo tolerance and fuzzy matching
            return SmartSearch.matches(query: qlc, in: searchableText)
        }

        // Ranking: custom exercises > relevance score > alphabetical
        let ranked = matches.sorted { a, b in
            // 1. Prioritize custom exercises
            if a.isCustom != b.isCustom { return a.isCustom && !b.isCustom }

            // 2. Sort by relevance score (typo tolerance + proximity)
            let scoreA = SmartSearch.score(query: qlc, in: a.name)
            let scoreB = SmartSearch.score(query: qlc, in: b.name)
            if scoreA != scoreB { return scoreA > scoreB }

            // 3. Alphabetical fallback
            return a.name < b.name
        }

        return .init(
            exercises: Array(ranked.prefix(limit)),
            muscleGroups: Array(suggestedGroups.prefix(12))
        )
    }
}

@inline(__always)
fileprivate func normKey(_ s: String) -> String {
    s.folding(options: .diacriticInsensitive, locale: .current)
     .lowercased()
     .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
     .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

// MARK: - Static helpers
extension ExerciseRepository {
    /// Heuristic: infer parent from a deep label like "Upper Chest".
    fileprivate static func guessParent(fromDeep deep: String) -> String? {
        let lc = deep.lowercased()
        let parents = Set(
            MuscleTaxonomy.subregions(for: .upper) + MuscleTaxonomy.subregions(for: .lower)
        )
        return parents.first { lc.contains($0.lowercased()) && lc != $0.lowercased() }
    }

    /// Lightweight synonym map so filtering is robust even if naming varies.
    static func synonyms(for name: String) -> [String] {
        switch name.lowercased() {
        case "chest":       return ["chest","pectoralis","pec"]
        case "upper chest": return ["upper chest","incline","clavicular","upper pec"]
        case "mid chest":   return ["mid chest","flat bench","flat press","mid pec"]
        case "lower chest": return ["lower chest","decline","dip","dips","lower pec"]

        case "back":        return ["back","lat","lats","latissimus","trapezius","trap","rhomboid"]
        case "lats":        return ["lat","lats","latissimus","pulldown","pull-up","pullup","chin-up","chin up"]
        case "mid-back":    return ["mid back","rhomboid","t-bar","seated row","retraction"]
        case "lower back":  return ["lower back","roman chair","hyperextension","back extension","good morning"]
        case "traps":       return ["trap","traps","shrug","upright row"]

        case "shoulders":   return ["shoulder","deltoid","delts","front delt","side delt","rear delt"]
        case "biceps":      return ["bicep","biceps"]
        case "triceps":     return ["tricep","triceps"]
        case "forearms":    return ["forearm","brachioradialis","flexor","extensor"]

        case "abs":         return ["abs","abdominals","rectus abdominis","core"]
        case "obliques":    return ["oblique","external oblique","internal oblique"]

        case "glutes":      return ["glute","gluteus","butt","glute max","glute med","glute minimus"]
        case "quads":       return ["quad","quadriceps","vastus","rectus femoris"]
        case "hamstrings":  return ["hamstring","biceps femoris","semitendinosus","semimembranosus"]
        case "calves":      return ["calf","gastrocnemius","soleus"]
        case "adductors":   return ["adductor","adductors","inner thigh"]
        case "abductors":   return ["abductor","abductors","outer thigh","glute medius","glute minimus"]

        default:            return [name.lowercased()]
        }
    }

    // Normalizes strings for lookup keys (e.g., "Incline Press" → "incline-press")
    fileprivate static func norm(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

// MARK: - Small String helpers

