//
//  ExerciseTagRepository.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//


import Foundation
import OSLog

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
            AppLogger.warning("Failed to load exercise_tags.json: \(error)", category: AppLogger.app)
            idIndex = [:]
        }
    }
}
