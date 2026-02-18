//
//  FavoritesFirst.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//

// FavoritesSorting.swift
import Foundation

/// Returns favorites at the top, then custom exercises, then falls back to A–Z.
/// Stable when names match (keeps original order).
/// Priority: Favorites > Custom > Catalog (alphabetical)
func favoritesFirst(_ rows: [Exercise], favIDs: Set<String>) -> [Exercise] {
    rows.enumerated().sorted { lhs, rhs in
        let lIsFav = favIDs.contains(lhs.element.id)
        let rIsFav = favIDs.contains(rhs.element.id)
        let lIsCustom = lhs.element.isCustom
        let rIsCustom = rhs.element.isCustom

        // 1. Favorites always come first
        if lIsFav != rIsFav { return lIsFav && !rIsFav }

        // 2. Among non-favorites, custom exercises come before catalog
        if !lIsFav && !rIsFav && lIsCustom != rIsCustom {
            return lIsCustom && !rIsCustom
        }

        // 3. Within same category, sort alphabetically
        let cmp = lhs.element.name.localizedCaseInsensitiveCompare(rhs.element.name)
        if cmp != .orderedSame { return cmp == .orderedAscending }

        // 4. Stable sort (preserve original order if names are identical)
        return lhs.offset < rhs.offset
    }
    .map { $0.element }
}
