//
//  CurrentWorkoutBar.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//


import SwiftUI


struct CurrentWorkoutBar: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var showSheet = false

    private var showBar: Bool {
        if let cw = store.currentWorkout { return !cw.entries.isEmpty }
        return false
    }

    var body: some View {
        Group {
            if showBar {
                let count = store.currentWorkout?.entries.count ?? 0
                Button(action: { showSheet = true }) {
                    CurrentWorkoutBarLabel(entryCount: count)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSheet) {
                    CurrentWorkoutSheet()
                        .environmentObject(store)
                }
                .padding(.bottom, 12)
                .padding(.horizontal)
            }
        }
    }
}

/// Split out the label to dramatically simplify the main body’s generic depth.
private struct CurrentWorkoutBarLabel: View {
    let entryCount: Int

    var body: some View {
        HStack {
            Image(systemName: "rectangle.stack.badge.plus")
            Text(title)
            Spacer()
            Image(systemName: "chevron.up")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 2, y: 1)
    }

    private var title: String {
        let noun = entryCount == 1 ? "exercise" : "exercises"
        return "Current Workout • \(entryCount) \(noun)"
    }
}
struct CurrentWorkoutSheet: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    let entries: [WorkoutEntry] = store.currentWorkout?.entries ?? []
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.exerciseName)
                            if e.sets.isEmpty {
                                Text("No sets logged")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                let setsText = e.sets.map { set in
                                    // Keep this simple for the type-checker; format weight once per set.
                                    let w = String(format: "%.1f", set.weight)
                                    return "\(set.reps)x @ \(w)kg"
                                }.joined(separator: ", ")

                                Text(setsText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Current Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        store.discardCurrentWorkout()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") {
                        store.finishCurrentWorkout()
                        dismiss()
                    }
                }
            }
        }
    }
}
