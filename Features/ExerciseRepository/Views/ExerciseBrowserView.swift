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
    @AppStorage("categoryFilter") private var category: CategoryBucket = .all

    // Track when filters change to reset pagination
    @State private var lastFilters: ExerciseFilters?
    @State private var searchDebounceTask: Task<Void, Never>?

    private var currentFilters: ExerciseFilters {
        ExerciseFilters(
            muscleGroup: muscleGroup,
            equipment: equip,
            moveType: move,
            category: category,
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
                ExerciseRowWithStats(exercise: ex, index: index, shouldLoadMore: shouldLoadMore)
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
        .safeAreaInset(edge: .top) { FiltersBar(equip: $equip, move: $move, category: $category) }
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

// Wrapper for exercise row with stats functionality
private struct ExerciseRowWithStats: View {
    let exercise: Exercise
    let index: Int
    let shouldLoadMore: (Int) -> Bool

    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var showingStats = false

    var body: some View {
        NavigationLink {
            ExerciseSessionView(
                exercise: exercise,
                initialEntryID: store.existingEntry(for: exercise.id)?.id
            )
        } label: {
            ExerciseRow(ex: exercise)
                .onAppear {
                    // Load more when approaching end of list
                    if shouldLoadMore(index) {
                        Task {
                            await repo.loadNextPage()
                        }
                    }
                }
        }
        .contextMenu {
            Button {
                showingStats = true
            } label: {
                Label("View Statistics", systemImage: "chart.bar.fill")
            }
        }
        .sheet(isPresented: $showingStats) {
            NavigationStack {
                ExerciseStatisticsView(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    trackingMode: TrackingMode(rawValue: exercise.trackingMode) ?? .weighted
                )
                .withDependencies()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// Simple row (adaptive metadata based on tracking mode)
private struct ExerciseRow: View {
    let ex: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ex.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                // Show category for Pilates/Yoga, equipment for others
                if ex.isTimedExercise || ex.isBodyweightExercise {
                    PremiumChip(
                        title: ex.category.capitalized,
                        icon: iconForCategory(ex.category),
                        color: colorForCategory(ex.category)
                    )
                } else {
                    PremiumChip(
                        title: ex.equipBucket.rawValue,
                        icon: "dumbbell.fill",
                        color: .blue
                    )
                }

                // Show tracking mode indicator
                PremiumChip(
                    title: ex.isTimedExercise ? "Timed" : ex.isBodyweightExercise ? "Bodyweight" : ex.moveBucket.rawValue,
                    icon: ex.isTimedExercise ? "timer" :
                          ex.isBodyweightExercise ? "figure.arms.open" :
                          ex.moveBucket == .pull ? "arrow.down.backward" :
                          ex.moveBucket == .push ? "arrow.up.forward" : "arrow.right",
                    color: ex.isTimedExercise ? .orange :
                           ex.isBodyweightExercise ? .purple :
                           chipColor(for: ex.moveBucket)
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

    private func iconForCategory(_ category: String) -> String {
        let cat = category.lowercased()
        if cat.contains("pilates") { return "figure.pilates" }
        if cat.contains("yoga") { return "figure.yoga" }
        if cat.contains("mobility") { return "figure.flexibility" }
        if cat.contains("cardio") { return "figure.run" }
        return "figure.strengthtraining.traditional"
    }

    private func colorForCategory(_ category: String) -> Color {
        let cat = category.lowercased()
        if cat.contains("pilates") { return .purple }
        if cat.contains("yoga") { return .mint }
        if cat.contains("mobility") { return .cyan }
        if cat.contains("cardio") { return .red }
        return .blue
    }
}


