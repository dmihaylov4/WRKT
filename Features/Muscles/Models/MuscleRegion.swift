// MuscleSVGMapper.swift
import Foundation
import SwiftUI
enum MuscleSVGMapper {
    // Which half to show for a set of regions



}


// MuscleRegion.swift
import Foundation

/// App-wide canonical set of regions your mappers & UI use.
enum MuscleRegion: Hashable, CaseIterable {
    // Chest
    case chestUpper, chestMid, chestLower
    // Upper body
    case shoulders, biceps, triceps, forearms, abs, obliques
    // Back
    case lats, midBack, lowerBack, trapsRear
    // Lower body
    case glutes, quads, hamstrings, calves, adductors, abductors
}
