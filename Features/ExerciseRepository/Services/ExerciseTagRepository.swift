//
//  ExerciseTagRepository.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//


import Foundation

/// Sidecar tags for precise deep filtering (e.g. "upper-chest", "lats").
/// Map a tag -> list of exercise IDs from your main dataset.
/// You can grow this file anytime without touching exercises.json.
//final class ExerciseTagRepository {
  //  static let shared = ExerciseTagRepository()
    //private(set) var idIndex: [String: [String]] = [:]

   // init() { loadFromBundle() }

    //func ids(for tag: String) -> [String]? { idIndex[tag] }

  //  private func loadFromBundle(fileName: String = "exercise_tags", fileExtension: String = "json") {
    //    guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else { return }
      //  do {
        //    let data = try Data(contentsOf: url)
          //  idIndex = try JSONDecoder().decode([String: [String]].self, from: data)
        //} catch {
          //  print("⚠️ Failed to load exercise_tags.json:", error)
           // idIndex = [:]
       // }
   // }/
//}


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
