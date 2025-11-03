//
//  MuscleGroupView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import SwiftUI
import Foundation
import Combine

struct MuscleGroupView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var favs: FavoritesStore
    let group: String

    private var sortedExercises: [Exercise] {
        let exercises = repo.exercisesForMuscle(group)
        return favoritesFirst(exercises, favIDs: favs.ids)
    }

    var body: some View {
        List(sortedExercises) { ex in
            NavigationLink(value: SearchDestination.exercise(ex)) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(ex.name)
                            .font(.body.weight(.semibold))
                        if ex.isCustom {
                            CustomExerciseBadge()
                        }
                    }
                    Text(ex.equipment ?? ex.category.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(group.capitalized)
    }
}
