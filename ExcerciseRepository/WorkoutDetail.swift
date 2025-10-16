//
//  WorkoutDetail.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import SwiftUI

struct WorkoutDetailView: View {
    let workout: CompletedWorkout
    var body: some View {
        List {
            Section(workout.date.formatted(date: .abbreviated, time: .shortened)) {
                ForEach(workout.entries) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(e.exerciseName).font(.headline)
                        if e.sets.isEmpty {
                            Text("No sets logged").font(.caption).foregroundStyle(.secondary)
                        } else {
                            let summary = e.sets.map { set in
                                let w = String(format: "%.1f", set.weight) // or: set.weight.formatted(.number.precision(.fractionLength(1)))
                                return "\(set.reps)x @ \(w)kg"
                            }.joined(separator: ", ")

                            Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}
