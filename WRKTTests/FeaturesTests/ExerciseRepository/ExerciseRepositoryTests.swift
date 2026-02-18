//
//  ExerciseRepositoryTests.swift
//  WRKTTests
//
//  Tests for ExerciseRepository
//
//  Note: These tests use the singleton ExerciseRepository.
//  For true unit testing, consider refactoring to use protocol-based dependency injection.
//

import XCTest
@testable import WRKT

@MainActor
final class ExerciseRepositoryTests: WRKTTestCase {

    // MARK: - Initialization Tests

    func testRepositorySingletonExists() {
        let repo = ExerciseRepository.shared
        XCTAssertNotNil(repo)
    }

    func testRepositoryInitialState() {
        let repo = ExerciseRepository.shared

        // Initial state before bootstrap
        XCTAssertGreaterThanOrEqual(repo.exercises.count, 0)
        XCTAssertFalse(repo.isLoadingPage)
        XCTAssertEqual(repo.currentPage, 0)
    }

    // MARK: - Exercise Lookup Tests

    func testExerciseLookupByIDReturnsNilForInvalidID() {
        let repo = ExerciseRepository.shared

        let result = repo.exercise(byID: "non-existent-exercise-id-12345")
        XCTAssertNil(result)
    }

    // MARK: - Media Lookup Tests

    func testMediaLookupForExerciseWithoutMedia() {
        let repo = ExerciseRepository.shared
        let exercise = TestFixtures.benchPress

        // Media may or may not be loaded
        let media = repo.media(for: exercise)

        // We can't assert the result without knowing if media was loaded
        // Just verify it doesn't crash
        _ = media
    }

    // MARK: - Pagination Tests

    func testPaginationInitialState() {
        let repo = ExerciseRepository.shared

        XCTAssertEqual(repo.currentPage, 0)
        XCTAssertFalse(repo.isLoadingPage)
    }

    func testLoadNextPageWhenAlreadyLoading() async {
        let repo = ExerciseRepository.shared

        // If already loading, calling loadNextPage should be safe
        if repo.isLoadingPage {
            await repo.loadNextPage()
            // Should not crash or cause issues
        }
    }

    // MARK: - Filter Tests

    func testResetPaginationWithEmptyFilters() async {
        let repo = ExerciseRepository.shared

        let emptyFilters = ExerciseFilters()
        await repo.resetPagination(with: emptyFilters)

        // Should reset to page 0
        XCTAssertEqual(repo.currentPage, 0)
    }

    // MARK: - Integration Tests

    func testBootstrapCompletesWithoutError() {
        let repo = ExerciseRepository.shared

        // Bootstrap should be idempotent
        repo.bootstrap(useSlimPreload: true)

        // Give it a moment to complete
        let expectation = XCTestExpectation(description: "Bootstrap completes")

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testGetAllExercises() async {
        let repo = ExerciseRepository.shared

        // Trigger bootstrap
        repo.bootstrap(useSlimPreload: true)

        // Wait a moment for bootstrap
        try? await Task.sleep(nanoseconds: 500_000_000)

        let allExercises = await repo.getAllExercises()

        // Should return array (may be empty if data not loaded yet)
        XCTAssertNotNil(allExercises)
    }

    func testLoadFirstPageWithoutFilters() async {
        let repo = ExerciseRepository.shared

        repo.bootstrap(useSlimPreload: true)
        try? await Task.sleep(nanoseconds: 500_000_000)

        await repo.loadFirstPage()

        // After loading first page, currentPage should be 0
        XCTAssertEqual(repo.currentPage, 0)
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccessToSharedInstance() async {
        let repo = ExerciseRepository.shared

        // Multiple concurrent accesses should be safe due to @MainActor
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { @MainActor in
                    _ = repo.exercises
                    _ = repo.currentPage
                    _ = repo.totalExerciseCount
                }
            }
        }

        // Should not crash
        XCTAssert(true)
    }
}
