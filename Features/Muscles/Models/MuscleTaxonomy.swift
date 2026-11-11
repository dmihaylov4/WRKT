//
//  MuscleTaxonomy.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import Foundation
import SwiftUI

enum MuscleTaxonomy {

    static func subregions(for region: BodyRegion) -> [String] {
        switch region {
        case .upper:
            return ["Chest","Back","Shoulders","Biceps","Triceps","Forearms","Abs","Obliques"]
        case .lower:
            return ["Glutes","Quads","Hamstrings","Calves","Adductors","Abductors"]
        }
    }

    /// Optional deeper layer for a given subregion (no JSON changes required).
    static func deepSubregions(for subregion: String) -> [String]? {
        switch subregion.lowercased() {
        case "chest":
            return ["Upper Chest","Mid Chest","Lower Chest"]
        case "back":
            return ["Lats","Mid-Back","Lower Back","Traps/Rear Delts"]
        default:
            return nil
        }
    }
    
    
    
    /// Keyword rules to classify into deep subregions (heuristics).
    // MuscleTaxonomy.swift — add this full implementation
    static func deepRules(parent: String, child: String) -> (include: [String], exclude: [String]) {
        let p = parent.lowercased()
        let c = child.lowercased()

        if p == "chest" {
            if c.contains("upper") {
                // e.g., incline bench/press/fly, clavicular head
                return (["incline", "upper", "clavicular"], ["decline", "lower"])
            }
            if c.contains("mid") || c.contains("middle") {
                // avoid incline/decline bias
                return (["flat", "press", "bench", "fly"], ["incline", "decline"])
            }
            if c.contains("lower") {
                return (["decline", "dip", "lower"], ["incline", "upper"])
            }
        }

        if p == "back" {
            if c.contains("lat") {
                return (["lat", "pulldown", "pull-up", "pullup", "chin-up", "row"], ["hyperextension", "good morning"])
            }
            if c.contains("mid") {
                return (["row", "rhomboid", "retraction", "seated row", "t-bar"], [])
            }
            if c.contains("lower") {
                return (["hyperextension", "roman chair", "back extension", "good morning"], [])
            }
            if c.contains("trap") || c.contains("rear") || c.contains("delt") {
                return (["shrug", "face pull", "upright row", "rear delt"], [])
            }
        }

        // Generic fallback: look for the child phrase in name or muscles
        return ([c], [])
    }
}
