//
//  ExerciseSearchVM.swift
//  WRKT
//
//  Shared ViewModel for exercise search and filtering

import Foundation
import Combine

@MainActor
final class ExerciseSearchVM: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var debouncedSearch: String = ""
    @Published var isShowingSearch: Bool = false
    @Published var equipmentFilter: EquipBucket = .all
    @Published var movementFilter: MoveBucket = .all
    @Published private var lastFilters: ExerciseFilters?

    private var bag = Set<AnyCancellable>()

    /// Track if user modified filters during this session
    private(set) var hasModifiedFilters: Bool = false

    var currentFilters: ExerciseFilters {
        ExerciseFilters(
            muscleGroup: nil,
            equipment: equipmentFilter,
            moveType: movementFilter,
            searchQuery: debouncedSearch
        )
    }

    init() {
        // Debounce search input using Combine (proper approach)
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .assign(to: &$debouncedSearch)

        // Track when filters are modified
        Publishers.CombineLatest3($searchQuery, $equipmentFilter, $movementFilter)
            .dropFirst() // Ignore initial values
            .sink { [weak self] _, _, _ in
                self?.hasModifiedFilters = true
            }
            .store(in: &bag)
    }

    func loadInitialPage(repo: ExerciseRepository) async {
        if lastFilters == nil {
            await repo.loadFirstPage(with: currentFilters)
            lastFilters = currentFilters
        }
    }

    func handleFiltersChanged(repo: ExerciseRepository) async {
        if lastFilters != currentFilters {
            await repo.resetPagination(with: currentFilters)
            lastFilters = currentFilters
        }
    }

    /// Reset to default state (call when sheet closes)
    func reset() {
        searchQuery = ""
        debouncedSearch = ""
        equipmentFilter = .all
        movementFilter = .all
        lastFilters = nil
        hasModifiedFilters = false
    }
}
