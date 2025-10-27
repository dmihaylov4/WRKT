//
//  FavoritesFirst.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//

// FavoritesSorting.swift
import Foundation

/// Returns favorites at the top, then falls back to A–Z.
/// Stable when names match (keeps original order).
func favoritesFirst(_ rows: [Exercise], favIDs: Set<String>) -> [Exercise] {
    rows.enumerated().sorted { lhs, rhs in
        let lIsFav = favIDs.contains(lhs.element.id)
        let rIsFav = favIDs.contains(rhs.element.id)
        if lIsFav != rIsFav { return lIsFav && !rIsFav }
        let cmp = lhs.element.name.localizedCaseInsensitiveCompare(rhs.element.name)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return lhs.offset < rhs.offset
    }
    .map { $0.element }
}
