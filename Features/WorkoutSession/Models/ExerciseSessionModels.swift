//
//  ExerciseSessionModels.swift
//  WRKT
//
//  Extracted from ExerciseSessionView.swift
//

import SwiftUI

// MARK: - Theme (migrated to DS)
// ExerciseSessionTheme is now a typealias pointing to DS colors
// Files using ExerciseSessionTheme should gradually migrate to using DS directly

enum ExerciseSessionTheme {
    static let bg        = DS.Semantic.surface
    static let surface   = DS.Theme.cardTop
    static let surface2  = DS.Semantic.surface50
    static let border    = DS.Semantic.border
    static let text      = DS.Semantic.textPrimary
    static let secondary = DS.Semantic.textSecondary
    static let accent    = DS.Theme.accent
}

// MARK: - Exercise Guide Metadata

struct ExerciseGuideMeta: Hashable {
    let difficulty: String
    let equipment: String
    let classification: String
    let mechanics: String
    let forceType: String
    let pattern: String
    let plane: String
    let posture: String
    let grip: String
    let laterality: String
    let cues: [String]
}

// MARK: - Helper Extensions

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
#endif
