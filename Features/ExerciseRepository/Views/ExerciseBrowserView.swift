//
//  ExerciseBrowserView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// ExerciseBrowserView.swift
import SwiftUI
import Combine

struct ExerciseBrowserView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2

    let muscleGroup: String?           // pass the selected muscle (e.g. "Chest"); nil = all
    @State private var search = ""
    @State private var debouncedSearch = ""
    @AppStorage("equipFilter") private var equip: EquipBucket = .all
    @AppStorage("moveFilter")  private var move: MoveBucket  = .all

    // Track when filters change to reset pagination
    @State private var lastFilters: ExerciseFilters?
    @State private var searchDebounceTask: Task<Void, Never>?

    private var currentFilters: ExerciseFilters {
        ExerciseFilters(
            muscleGroup: muscleGroup,
            equipment: equip,
            moveType: move,
            searchQuery: debouncedSearch  // Use debounced search
        )
    }

    var body: some View {
        List {
            // Summary row
            if repo.totalExerciseCount > 0 {
                Text("\(repo.exercises.count) of \(repo.totalExerciseCount) exercises")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Exercise rows
            ForEach(Array(repo.exercises.enumerated()), id: \.element.id) { index, ex in
                NavigationLink {
                    ExerciseSessionView(
                        exercise: ex,
                        initialEntryID: store.existingEntry(for: ex.id)?.id
                    )
                } label: {
                    ExerciseRow(ex: ex)
                        .onAppear {
                            // Load more when approaching end of list
                            if shouldLoadMore(at: index) {
                                Task {
                                    await repo.loadNextPage()
                                }
                            }
                        }
                }
            }

            // Loading indicator
            if repo.isLoadingPage {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(muscleGroup ?? "Exercises")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .safeAreaInset(edge: .top) { FiltersBar(equip: $equip, move: $move) }
        .task {
            // Load first page on appear
            if lastFilters == nil {
                await repo.loadFirstPage(with: currentFilters)
                lastFilters = currentFilters
            }
        }
        .onChange(of: search) { _, newSearch in
            // Debounce search input (300ms delay)
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                guard !Task.isCancelled else { return }
                debouncedSearch = newSearch
            }
        }
        .onChange(of: currentFilters) { _, newFilters in
            // Reset pagination when filters change
            if lastFilters != newFilters {
                Task {
                    await repo.resetPagination(with: newFilters)
                    lastFilters = newFilters
                }
            }
        }
    }

    /// Determine if we should load more exercises
    /// Triggers when user scrolls to within 10 items of the end
    private func shouldLoadMore(at index: Int) -> Bool {
        guard repo.hasMorePages && !repo.isLoadingPage else { return false }
        return index >= repo.exercises.count - 10
    }
}

// Simple row
private struct ExerciseRow: View {
    let ex: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ex.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                PremiumChip(
                    title: ex.equipBucket.rawValue,
                    icon: "dumbbell.fill",
                    color: .blue
                )
                PremiumChip(
                    title: ex.moveBucket.rawValue,
                    icon: ex.moveBucket == .pull ? "arrow.down.backward" :
                          ex.moveBucket == .push ? "arrow.up.forward" : "arrow.right",
                    color: chipColor(for: ex.moveBucket)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func chipColor(for bucket: MoveBucket) -> Color {
        switch bucket {
        case .push: return .orange
        case .pull: return .green
        default: return .purple
        }
    }
}

// MARK: - Premium Chip Component
private struct PremiumChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                // Base dark background
                Capsule()
                    .fill(Color(hex: "#1A1A1A"))

                // Subtle color glow
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.4), color.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

