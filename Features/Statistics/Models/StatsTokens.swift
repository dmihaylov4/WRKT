//
//  StatsTokens.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//


// StatsTokens.swift
import SwiftUI

enum StatsTokens {
    static let primary = Color(hex: "#CCFF00")  // Brand green
    static let accent  = Color(hex: "#DFFF66")  // Lighter brand green
    static let grid    = Color.gray.opacity(0.25)

    static func areaGradient() -> LinearGradient {
        LinearGradient(colors: [primary.opacity(0.55), primary.opacity(0.10)],
                       startPoint: .top, endPoint: .bottom)
    }

    static func barGradient() -> LinearGradient {
        LinearGradient(colors: [primary, accent], startPoint: .top, endPoint: .bottom)
    }
}
