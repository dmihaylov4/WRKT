//
//  ExerciseCache.swift
//  WRKT
//
//  Manages paginated loading of exercises to reduce memory usage
//  and improve app launch performance
//

import Foundation

/// Thread-safe cache for exercise data with pagination support
actor ExerciseCache {
    // MARK: - Properties

    /// All exercises loaded from disk (loaded once)
    private var allExercises: [Exercise] = []

    /// Full indexes (built once after loading all exercises)
    private var byID: [String: Exercise] = [:]
    private var bySlug: [String: Exercise] = [:]
    private var bySubregion: [String: [Exercise]] = [:]

    /// Loading state
    private var isLoadingAll = false
    private var didLoadAll = false

    // MARK: - Configuration

    let pageSize = 50

    // MARK: - Public API

    /// Returns whether all exercises have been loaded
    var isFullyLoaded: Bool {
        get async { didLoadAll }
    }

    /// Returns total count of exercises (0 until loaded)
    var totalCount: Int {
        get async { allExercises.count }
    }

    /// Load all exercises from bundle (called once at app launch)
    func loadAllExercises(from fileName: String = "exercises_clean", fileExtension: String = "json") async throws {
        // Prevent duplicate loads
        guard !didLoadAll && !isLoadingAll else { return }
        isLoadingAll = true

        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            isLoadingAll = false
            throw ExerciseCacheError.fileNotFound(fileName: "\(fileName).\(fileExtension)")
        }

        do {
            let data = try Data(contentsOf: url)
            let dtoList = try JSONDecoder().decode([ExcelExerciseDTO].self, from: data)
            let mapped = ExerciseMapping.mapDTOs(dtoList)
            let sorted = mapped.sorted { $0.name < $1.name }

            // Build indexes
            let idIndex: [String: Exercise] = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
            let slugIndex = idIndex
            let subregionIndex = mapped.reduce(into: [String: [Exercise]]()) { dict, ex in
                for tag in ex.subregionTags { dict[tag, default: []].append(ex) }
            }

            // Store in actor
            self.allExercises = sorted
            self.byID = idIndex
            self.bySlug = slugIndex
            self.bySubregion = subregionIndex
            self.didLoadAll = true
            self.isLoadingAll = false

            print("✅ ExerciseCache: Loaded \(sorted.count) exercises")
        } catch {
            isLoadingAll = false
            print("❌ ExerciseCache: Failed to load exercises: \(error)")
            throw error
        }
    }

    /// Get a page of exercises
    /// - Parameters:
    ///   - page: Page number (0-indexed)
    ///   - filters: Optional filter criteria
    /// - Returns: Array of exercises for the requested page
    func getPage(_ page: Int, matching filters: ExerciseFilters? = nil) async -> [Exercise] {
        guard didLoadAll else { return [] }

        let filtered: [Exercise]
        if let filters = filters {
            filtered = allExercises.filter { ex in
                // Muscle group filter
                if let muscleGroup = filters.muscleGroup, !muscleGroup.isEmpty {
                    guard ex.contains(muscleGroup: muscleGroup) else { return false }
                }

                // Equipment filter
                if filters.equipment != .all {
                    guard ex.equipBucket == filters.equipment else { return false }
                }

                // Move type filter
                if filters.moveType != .all {
                    guard ex.moveBucket == filters.moveType else { return false }
                }

                // Search query filter
                if !filters.searchQuery.isEmpty {
                    guard ex.matches(filters.searchQuery) else { return false }
                }

                return true
            }
        } else {
            filtered = allExercises
        }

        // Calculate page bounds
        let startIndex = page * pageSize
        let endIndex = min(startIndex + pageSize, filtered.count)

        guard startIndex < filtered.count else { return [] }

        return Array(filtered[startIndex..<endIndex])
    }

    /// Get total count of exercises matching filters
    func getTotalCount(matching filters: ExerciseFilters? = nil) async -> Int {
        guard didLoadAll else { return 0 }

        guard let filters = filters else { return allExercises.count }

        return allExercises.filter { ex in
            if let muscleGroup = filters.muscleGroup, !muscleGroup.isEmpty {
                guard ex.contains(muscleGroup: muscleGroup) else { return false }
            }
            if filters.equipment != .all {
                guard ex.equipBucket == filters.equipment else { return false }
            }
            if filters.moveType != .all {
                guard ex.moveBucket == filters.moveType else { return false }
            }
            if !filters.searchQuery.isEmpty {
                guard ex.matches(filters.searchQuery) else { return false }
            }
            return true
        }.count
    }

    /// Get exercise by ID (uses index for O(1) lookup)
    func exercise(byID id: String) async -> Exercise? {
        byID[id]
    }

    /// Get all exercises (use sparingly, prefer pagination)
    func getAllExercises() async -> [Exercise] {
        allExercises
    }

    /// Get exercises for a specific subregion
    func exercises(forSubregion subregion: String) async -> [Exercise] {
        bySubregion[subregion]?.sorted { $0.name < $1.name } ?? []
    }

    /// Search exercises (returns up to limit results)
    func search(_ query: String, limit: Int = 60) async -> [Exercise] {
        guard didLoadAll else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let qlc = q.lowercased()
        let tokens = qlc.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        // Filter exercises requiring all tokens to match
        let matches = allExercises.filter { ex in
            let muscP = ex.primaryMuscles.joined(separator: " ")
            let muscS = ex.secondaryMuscles.joined(separator: " ")
            let hay = (ex.name + " " + (ex.equipment ?? "") + " " + ex.category + " " + muscP + " " + muscS).lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }

        // Rank by relevance
        let ranked = matches.sorted { a, b in
            let al = a.name.lowercased(), bl = b.name.lowercased()
            let ap = al.hasPrefix(qlc), bp = bl.hasPrefix(qlc)
            if ap != bp { return ap && !bp }
            let ac = al.contains(qlc), bc = bl.contains(qlc)
            if ac != bc { return ac && !bc }
            return a.name < b.name
        }

        return Array(ranked.prefix(limit))
    }
}

// MARK: - Filter Model

struct ExerciseFilters: Equatable {
    var muscleGroup: String?
    var equipment: EquipBucket = .all
    var moveType: MoveBucket = .all
    var searchQuery: String = ""
}

// MARK: - Errors

enum ExerciseCacheError: LocalizedError {
    case fileNotFound(fileName: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let fileName):
            return "Exercise data file '\(fileName)' not found in bundle"
        }
    }
}
