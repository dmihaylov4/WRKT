//
//  ExerciseMapping.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 09.10.25.
//

import Foundation

enum ExerciseMapping {
    /// Map Excel DTO → domain model and attach deep subregion tags.
    static func mapDTOs(_ list: [ExcelExerciseDTO]) -> [Exercise] {
        list.map { dto in
            var model = Exercise(from: dto)         // uses your convenience init
            model.subregionTags = buildTags(for: model, dto: dto)
            return model
        }
    }

    /// Heuristic tags using MuscleTaxonomy rules (no JSON changes).
    static func buildTags(for ex: Exercise, dto: ExcelExerciseDTO) -> [String] {
        // Parent candidates (e.g. chest/back/…)
        let possibleParentsLowercased: [String] = (
            [ex.primaryMuscles.first, dto.targetMuscleGroup]
                .compactMap { $0?.lowercased() }
            + [ex.category.lowercased()]
        )

        // Build a searchable haystack (split for compiler perf)
        let muscP    = ex.primaryMuscles.joined(separator: " ")
        let muscS    = ex.secondaryMuscles.joined(separator: " ")
        let patterns = [dto.movementPattern1, dto.movementPattern2, dto.movementPattern3]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let base = ex.name + " " + muscP + " " + muscS
        let hay  = (base + " " + patterns).lowercased()

        var out = Set<String>()
        for p in possibleParentsLowercased {
            if let deep = MuscleTaxonomy.deepSubregions(for: p.capitalized) {
                for child in deep {
                    let (inc, exc) = MuscleTaxonomy.deepRules(parent: p, child: child)
                    let includeHit  = inc.contains { hay.contains($0.lowercased()) }
                    let excludeHit  = exc.contains { hay.contains($0.lowercased()) }
                    if includeHit && !excludeHit { out.insert(child) }
                }
            }
        }
        return Array(out)
    }
}
