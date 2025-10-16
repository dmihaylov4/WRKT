//
//  ExerciseTagRepository.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//


import Foundation

/// Sidecar tags for deep categories (e.g. "upper-chest", "lats").
/// JSON shape: { "upper-chest": ["ex-id-1","ex-id-2"], "lats": ["ex-id-9"] }
final class ExerciseTagRepository {
    static let shared = ExerciseTagRepository()

    // tagKey -> [exerciseID]
    private(set) var idIndex: [String: [String]] = [:]

    private init() { loadFromBundle() }  // make init private to enforce singleton

    func ids(for tag: String) -> [String]? { idIndex[tag] }

    private func loadFromBundle(fileName: String = "exercise_tags", fileExtension: String = "json") {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else { return }
        do {
            let data = try Data(contentsOf: url)
            idIndex = try JSONDecoder().decode([String: [String]].self, from: data)
        } catch {
            print("⚠️ Failed to load exercise_tags.json: \(error)")
            idIndex = [:]
        }
    }
}
