//
//  LiveWorkoutView.swift
//  WRKT
//

import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var editingEntry: WorkoutEntry? = nil
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack {
            if let current = store.currentWorkout, !current.entries.isEmpty {
                List {
                    Section("In Progress") {
                        ForEach(current.entries) { e in
                            Button {
                                editingEntry = e
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "dumbbell").font(.headline)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(e.exerciseName).font(.headline)
                                        if !e.sets.isEmpty {
                                            Text(e.sets.map { "\($0.reps)×\($0.weight.safeInt)kg" }
                                                .joined(separator: "  •  "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("No sets yet")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { idxSet in
                            if let current = store.currentWorkout {
                                for idx in idxSet {
                                    let id = current.entries[idx].id
                                    store.removeEntry(entryID: id)
                                }
                            }
                        }
                    }
                }
                // Footer controls fixed above the tab bar
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 12) {
                        SwipeToConfirm(
                            text: "Slide to finish workout",
                            systemImage: "checkmark.seal.fill",
                            background: .thinMaterial
                        ) {
                            store.finishCurrentWorkout()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        .frame(height: 56)
                        Button(role: .destructive) {
                            showDiscardConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Discard Workout", systemImage: "trash")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .confirmationDialog("Discard Workout", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                            Button("Discard Workout", role: .destructive) {
                                store.discardCurrentWorkout()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to discard this workout? You can undo this action.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8) // breathing room from the tab bar
                    .background(.clear)
                }
            } else {
                ContentUnavailableView("No active workout", systemImage: "bolt.heart")
                    .padding()
            }
        }
        .sheet(item: $editingEntry) { entry in
            if let ex = store.exerciseForEntry(entry) {
                NavigationStack {
                    ExerciseSessionView(exercise: ex, initialEntryID: entry.id)
                        .environmentObject(store)
                }
            } else {
                Text("Exercise not found")
            }
        }
    }
}

extension UUID: @unchecked Sendable {} // (optional) for sheet(item:) on older compilers

// MARK: - Swipe to Confirm control



// Tiny helper
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
