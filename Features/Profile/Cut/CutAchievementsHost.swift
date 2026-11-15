//
//  CutAchievementsHost.swift
//  WRKT
//
//  AchievementsView's state behind the Cut page: the same achievements query (newest change
//  first), the search field and the filter menu.
//

import SwiftUI
import SwiftData

struct CutAchievementsHost: View {
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @State private var search = ""
    @State private var filter: CutAchievementsFilter = .all

    var body: some View {
        CutAchievementsView(
            model: CutAchievementsLogic.model(
                achievements.map {
                    CutAchievementFacts(id: $0.id, title: $0.title, desc: $0.desc, progress: $0.progress,
                                        target: $0.target, unlockedAt: $0.unlockedAt)
                },
                search: search, filter: filter),
            filter: $filter
        )
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
    }
}
