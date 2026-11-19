import XCTest
@testable import WRKT

/// Launch waits for the full exercise catalog without polling, and still gives up after its timeout.
@MainActor
final class FullCatalogWaitTests: XCTestCase {
    func testWaitGivesUpAfterTheTimeoutWhenTheCatalogNeverLoads() async {
        let repository = ExerciseRepository()
        let started = ContinuousClock.now
        let loaded = await repository.waitForFullCatalog(timeout: .milliseconds(200))
        XCTAssertFalse(loaded)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(200))
        XCTAssertFalse(repository.didLoadFull)
    }

    func testWaitReturnsOnceTheCatalogHasLoaded() async {
        let repository = ExerciseRepository()
        repository.bootstrap(useSlimPreload: true)
        let loaded = await repository.waitForFullCatalog(timeout: .seconds(10))
        XCTAssertTrue(loaded)
        XCTAssertTrue(repository.didLoadFull)
        // Already loaded: returns at once.
        let again = await repository.waitForFullCatalog(timeout: .milliseconds(1))
        XCTAssertTrue(again)
    }
}
