//
//  DataQualityBadge.swift
//  WRKT
//

import SwiftUI

enum DataQuality {
    case estimated
    case lowData
    case ageBased
    case bodyweightEst

    var label: String {
        switch self {
        case .estimated:     return "~"
        case .lowData:       return "low data"
        case .ageBased:      return "age-based"
        case .bodyweightEst: return "estimated"
        }
    }
}

struct DataQualityBadge: View {
    let quality: DataQuality

    var body: some View {
        Text(quality.label)
            .dsFont(.caption2)
            .foregroundStyle(DS.Semantic.textSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(DS.Semantic.card, in: RoundedRectangle(cornerRadius: 4))
    }
}
