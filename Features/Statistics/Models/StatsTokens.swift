//
//  StatsTokens.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//


// StatsTokens.swift
import SwiftUI

enum StatsTokens {
    static let primary = Color(hex: "#F4E409")
    static let accent  = Color(hex: "#FFE869")
    static let grid    = Color.gray.opacity(0.25)

    static func areaGradient() -> LinearGradient {
        LinearGradient(colors: [primary.opacity(0.55), primary.opacity(0.10)],
                       startPoint: .top, endPoint: .bottom)
    }

    static func barGradient() -> LinearGradient {
        LinearGradient(colors: [primary, accent], startPoint: .top, endPoint: .bottom)
    }
}
