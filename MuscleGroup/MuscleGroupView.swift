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
    let group: String

    var body: some View {
        List(repo.exercisesForMuscle(group)) { ex in     // ← updated call
            NavigationLink(value: SearchDestination.exercise(ex)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name)
                        .font(.body.weight(.semibold))
                    Text(ex.equipment ?? ex.category.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(group.capitalized)
    }
}
