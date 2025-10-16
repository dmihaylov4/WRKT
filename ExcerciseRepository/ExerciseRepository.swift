//
//  ExerciseRepository.swift
//  WRKT
//

import Foundation
import Combine



@MainActor
final class ExerciseRepository: ObservableObject {
    static let shared = ExerciseRepository()

    // MARK: Published data
    @Published private(set) var exercises: [Exercise] = []

    // MARK: Indexes
    private(set) var byID: [String: Exercise] = [:]
    private(set) var bySlug: [String: Exercise] = [:]            // id == slug in this dataset
    private(set) var bySubregion: [String: [Exercise]] = [:]     // "Upper Chest" -> [Exercise]

    // MARK: Media index
    private var mediaById:   [String: ExerciseMedia] = [:]
    private var mediaByName: [String: ExerciseMedia] = [:]

    // MARK: Load-state guards
    private var didKickoffExercises = false
    private var didLoadFull = false
    private var didLoadMedia = false
    
    private var isLoadingFull = false

    // MARK: Init
    /// Auto-bootstraps using a *full* load so older code that relied on `init` keeps working.
    /// If you prefer the slim-then-full startup, call `bootstrap(useSlimPreload: true)` from your App shell.
    init() {
        //bootstrap(useSlimPreload: false) // keep old behavior intact
    }

    // MARK: Public API

    /// Call once at app launch (e.g., in AppShellView .task{}) if you want slim->full warm start.
    func bootstrap(useSlimPreload: Bool = true) {
        if !didKickoffExercises {
            didKickoffExercises = true
            if useSlimPreload {
                preloadCatalogThenFull()
            } else {
                loadFromBundle(fileName: "exercises_clean", fileExtension: "json")
            }
        }
        if !didLoadMedia {
            loadMedia()
        }
    }

    func exercise(byID id: String) -> Exercise? { byID[id] }

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
            print("❌ Missing \(fileName).\(fileExtension) in bundle.")
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
                print("✅ Loaded \(sorted.count) exercises from \(fileName).\(fileExtension)")
            } catch {
                await MainActor.run { self.isLoadingFull = false }
                print("❌ Failed to decode \(fileName).\(fileExtension): \(error)")
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
                    print("⚡️ Preloaded slim catalog (\(self.exercises.count))")
                }
                
            }

            // 2) Upgrade to full dataset
            await self.loadFromBundle(fileName: "exercises_clean", fileExtension: "json")
        }
    }

    // MARK: Loading — Media

    private func loadMedia() {
        guard let url = Bundle.main.url(forResource: "exercise_media_final", withExtension: "json") else {
            print("⚠️ exercise_media_final.json not found in bundle")
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
                print("🎬 Loaded \(items.count) media items")
            } catch {
                await MainActor.run { self.didLoadMedia = false }
                print("❌ Failed to load media: \(error)")
            }
        }
    }

    // MARK: Query helpers

    /// Returns exercises for a deep subregion (e.g., parent=Chest, child=Upper Chest).
    func deepExercises(parent: String, child: String) -> [Exercise] {
        if let arr = bySubregion[child], !arr.isEmpty {
            return arr.sorted { $0.name < $1.name }
        }
        // Fallback: runtime heuristic using your taxonomy rules
        let (inc, exc) = MuscleTaxonomy.deepRules(parent: parent, child: child)
        let incLC = inc.map { $0.lowercased() }
        let excLC = exc.map { $0.lowercased() }

        return exercises.filter { ex in
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
    func exercisesForMuscle(_ group: String) -> [Exercise] {
        let g = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty else { return [] }

        // If we already have an index for this subregion, use it.
        if let indexed = bySubregion[g], !indexed.isEmpty {
            return indexed.sorted { $0.name < $1.name }
        }

        // If it looks like a deep subregion, delegate to deep rules.
        if let parent = ExerciseRepository.guessParent(fromDeep: g) {
            return deepExercises(parent: parent, child: g)
        }

        // Parent-only filter with synonyms
        let keysLC = ExerciseRepository.synonyms(for: g).map { $0.lowercased() }
        return exercises.filter { ex in
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

        // Exercise search: require all tokens to appear in a combined haystack
        let matches: [Exercise] = exercises.filter { ex in
            let muscP = ex.primaryMuscles.joined(separator: " ")
            let muscS = ex.secondaryMuscles.joined(separator: " ")
            let hay   = (ex.name + " " + (ex.equipment ?? "") + " " + ex.category + " " + muscP + " " + muscS).lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }

        // Ranking: name prefix > name contains > alpha
        let ranked = matches.sorted { a, b in
            let al = a.name.lowercased(), bl = b.name.lowercased()
            let ap = al.hasPrefix(qlc),    bp = bl.hasPrefix(qlc)
            if ap != bp { return ap && !bp }
            let ac = al.contains(qlc),     bc = bl.contains(qlc)
            if ac != bc { return ac && !bc }
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

