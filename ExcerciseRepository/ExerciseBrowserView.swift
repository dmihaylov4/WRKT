//
//  ExerciseBrowserView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// ExerciseBrowserView.swift
import SwiftUI

struct ExerciseBrowserView: View {
    @EnvironmentObject var repo: ExerciseRepository

    let muscleGroup: String?           // pass the selected muscle (e.g. "Chest"); nil = all
    @State private var search = ""
    @AppStorage("equipFilter") private var equip: EquipBucket = .all
    @AppStorage("moveFilter")  private var move: MoveBucket  = .all

    private var filtered: [Exercise] {
        repo.exercises
            .filter { $0.contains(muscleGroup: muscleGroup) }
            .filter { ex in equip == .all || ex.equipBucket == equip }
            .filter { ex in move  == .all || ex.moveBucket  == move  }
            .filter { $0.matches(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            // (Optional) tiny summary row
            if !filtered.isEmpty {
                Text("\(filtered.count) exercises")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(filtered) { ex in
                NavigationLink {
                    ExerciseSessionView(exercise: ex)   // your logger
                } label: {
                    ExerciseRow(ex: ex)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(muscleGroup ?? "Exercises")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .safeAreaInset(edge: .top) { FiltersBar(equip: $equip, move: $move) } // 👈 replaces difficulty chips
    }
}

// Simple row
private struct ExerciseRow: View {
    let ex: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ex.name).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Chip(ex.equipBucket.rawValue, system: "dumbbell.fill")
                Chip(ex.moveBucket.rawValue, system: ex.moveBucket == .pull ? "arrow.down.backward" :
                                              ex.moveBucket == .push ? "arrow.up.forward" : "arrow.right")
            }
        }
    }
    private func Chip(_ title: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system).font(.caption2)
            Text(title).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
    }
}

