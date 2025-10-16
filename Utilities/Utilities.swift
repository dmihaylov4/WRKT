//
//  Utilities.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//
import SwiftUI
import CoreData
import Foundation

extension String {
    var normalized: String {
        self.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}

extension Array where Element == Exercise {
    func allMuscleGroups() -> [String] {
        let muscles = self.flatMap { $0.primaryMuscles + $0.secondaryMuscles }
        let groups = Set(muscles)
        return groups.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct DayStat: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let workoutCount: Int
    let runCount: Int

    init(id: UUID = UUID(), date: Date, workoutCount: Int, runCount: Int) {
        self.id = id
        self.date = date
        self.workoutCount = workoutCount
        self.runCount = runCount
    }
}
