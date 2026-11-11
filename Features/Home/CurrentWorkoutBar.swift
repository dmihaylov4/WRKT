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
        .background(.ultraThinMaterial, in: DS.RoleShape(.control, legacy: Capsule()))
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

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

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
                                    .dsFont(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                let setsText = e.sets.map { set in
                                    return "\(set.reps)x @ \(unit.format(set.weight))"
                                }.joined(separator: ", ")

                                Text(setsText)
                                    .dsFont(.caption)
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
