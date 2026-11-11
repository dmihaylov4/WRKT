//
//  BrowseRoute.swift
//  WRKT
//

import SwiftUI

// MARK: - Routes the Home stack can push to
enum BrowseRoute: Hashable {
    case region(BodyRegion)
    case regionAll(BodyRegion)                // Show all exercises for region with filters
    case allExercises                         // Show all exercises (no region filter)
    case subregion(String)                    // e.g. "Chest"
    case deep(parent: String, child: String)  // e.g. ("Chest","Upper Chest")
}
