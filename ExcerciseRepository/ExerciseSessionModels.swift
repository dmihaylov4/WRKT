//
//  ExerciseSessionModels.swift
//  WRKT
//
//  Extracted from ExerciseSessionView.swift
//

import SwiftUI

// MARK: - Theme

enum ExerciseSessionTheme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
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
